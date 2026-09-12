import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Recordings, and the chunk queue that makes them survive reality.
///
/// The chunk table is the durability story in full: the OS kills the app, the network
/// drops, the battery dies mid-meeting, and on relaunch the pipeline resumes from these
/// rows and re-uploads only what did not finish. Chunks are rows, never objects in memory.
@DataClassName('Recording')
class Recordings extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// Path to the compressed copy kept for playback. The working PCM is deleted once
  /// every chunk reaches a terminal state.
  TextColumn get audioPath => text().nullable()();

  TextColumn get transcriptionProviderId => text().nullable()();
  TextColumn get structuringProviderId => text().nullable()();

  /// The model that actually produced the note, as the provider reported it. The
  /// provider id alone says nothing about the rate, so the cost meter prices on this.
  TextColumn get structuringModel => text().nullable()();

  /// The note document as returned, so a schema change never orphans an old note.
  TextColumn get noteJson => text().nullable()();
  TextColumn get noteSchemaVersion => text().nullable()();
  TextColumn get promptVersion => text().nullable()();

  IntColumn get inputTokens => integer().nullable()();
  IntColumn get outputTokens => integer().nullable()();

  /// The assembled transcript exactly as spoken, before any cleanup. Kept even when
  /// [cleanedTranscriptText] exists, so nothing the user said is ever only reachable
  /// through an edited version of it.
  TextColumn get transcriptText => text().nullable()();

  /// Timestamped transcript segments, including provider speaker labels.
  TextColumn get transcriptSegmentsJson => text().nullable()();

  /// User-edited names keyed by the provider's speaker label.
  TextColumn get speakerNamesJson => text().nullable()();

  /// [transcriptText] with filler words and stutters removed, when the punctuation and
  /// filler cleanup workflow feature is on. Null when the feature is off or cleanup has
  /// not run for this recording.
  TextColumn get cleanedTranscriptText => text().nullable()();

  /// Marked to jump the backlog when several recordings are waiting to be transcribed —
  /// see the priority transcription queue workflow feature.
  BoolColumn get priority => boolean().withDefault(const Constant(false))();

  /// When true, this recording may only use on-device or user-owned local providers.
  BoolColumn get localOnly => boolean().withDefault(const Constant(false))();

  /// The template used to structure this recording, if any.
  TextColumn get templateId => text().nullable()();

  /// BCP-47 override for this recording only, e.g. 'es-ES'. Null falls back to the
  /// global transcription language setting — set here when the auto-detected or
  /// default language turned out wrong for this particular recording.
  TextColumn get language => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One unit of work in the transcription queue.
class Chunks extends Table {
  TextColumn get id => text()();
  TextColumn get recordingId =>
      text().references(Recordings, #id, onDelete: KeyAction.cascade)();

  /// Position in the recording. Reassembly is ordered by this, never by completion.
  /// `index` is a SQL keyword; drift quotes it, but the Dart-side name stays explicit.
  IntColumn get chunkIndex => integer().named('index')();

  IntColumn get startMs => integer()();

  /// Where this chunk's new content begins; everything before it repeats the previous
  /// chunk's tail and is de-duplicated on reassembly.
  IntColumn get contentStartMs => integer()();
  IntColumn get endMs => integer()();

  /// Audio is sliced out of the recording's WAV on demand, so a chunk owns no file of
  /// its own. Kept nullable for a future streaming recorder that writes chunks directly.
  TextColumn get path => text().nullable()();
  IntColumn get bytes => integer().nullable()();

  TextColumn get state => textEnum<ChunkState>()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  /// Named `transcriptText` rather than `text`: a column getter called `text` shadows
  /// drift's own `Table.text()` builder and breaks every other column in the table.
  TextColumn get transcriptText => text().named('text').nullable()();

  /// Segment timings as JSON, so absolute offsets survive a restart.
  TextColumn get segmentsJson => text().nullable()();

  TextColumn get error => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class NoteTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get instructions => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ActionReminders extends Table {
  TextColumn get id => text()();
  TextColumn get recordingId =>
      text().references(Recordings, #id, onDelete: KeyAction.cascade)();
  TextColumn get taskId => text()();
  TextColumn get title => text()();
  DateTimeColumn get remindAt => dateTime()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PrivacyAudits extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get action => text()();
  TextColumn get detail => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The Codex: a personal library of notes the user keeps on purpose, independent of
/// any one recording.
///
/// A Codex note may start life as a line copied out of a transcript, but from the
/// moment it is saved it is its own row, not a view onto the recording. Deleting the
/// recording — or its audio, or the whole transcript — must never take the note with
/// it. [sourceRecordingId] is a soft, nullable link purely for "jump back to where
/// this came from"; the foreign key's `onDelete: setNull` is what actually enforces
/// the independence, so a vanished recording silently clears the pointer instead of
/// cascading, and [sourceRecordingTitle] is snapshotted at save time so the note can
/// still say where it came from after that.
///
/// Named `body` rather than `text`: a column getter called `text` shadows drift's own
/// `Table.text()` builder and breaks every other column in the table (see [Chunks]).
@DataClassName('CodexNote')
class CodexNotes extends Table {
  TextColumn get id => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get sourceRecordingId => text().nullable().references(
        Recordings,
        #id,
        onDelete: KeyAction.setNull,
      )();
  TextColumn get sourceRecordingTitle => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The Gantt chart: the plan a person built by hand out of a recording.
///
/// Nothing reaches this table because a model found a date. A note's own dates are a
/// suggestion — the chart is what someone decided to commit to, item by item, through
/// a form they filled in. That is the whole reason this is a table rather than a flag
/// on [Recordings.noteJson]: re-running the structuring stage rewrites the note and
/// would silently rewrite the plan with it.
///
/// Scoped to its recording with a cascade, unlike [CodexNotes]: this chart is only ever
/// reachable through the recording's own Gantt tab, so an entry that outlived the
/// recording would be a row nobody could see or delete.
@DataClassName('GanttEntry')
class GanttEntries extends Table {
  TextColumn get id => text()();
  TextColumn get recordingId =>
      text().references(Recordings, #id, onDelete: KeyAction.cascade)();

  TextColumn get title => text()();

  /// Inclusive start and finish. A milestone stores the same date in both, so the
  /// zero-duration convention needs no special case anywhere downstream.
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();

  /// Who is doing it, and which phase or workstream it belongs to. Free text: no two
  /// teams name their swimlanes the same way, and a picker would only be a worse
  /// version of typing.
  TextColumn get owner => text().nullable()();
  TextColumn get workstream => text().nullable()();

  /// 0-100, as reported. Never derived from the calendar — a bar whose dates have
  /// passed is late, not finished.
  IntColumn get percentComplete => integer().withDefault(const Constant(0))();

  BoolColumn get milestone => boolean().withDefault(const Constant(false))();

  /// Other [GanttEntries.id] values that must finish first, as a JSON array. A join
  /// table would buy referential integrity the chart does not need: a dependency on an
  /// entry that has since been deleted is simply not drawn.
  TextColumn get dependsOnJson => text().nullable()();

  /// 'explicit' or 'inferred', matching DateBasis. An entry the user placed from a
  /// model's own guess without correcting it stays marked as inferred, because
  /// accepting a prefilled form does not turn a guess into something that was said.
  TextColumn get dateBasis =>
      text().withDefault(const Constant('explicit'))();

  /// The note task this was placed from, when it came from one, so the tray beside the
  /// chart can stop offering work that is already on it.
  TextColumn get sourceTaskId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

enum ChunkState {
  pending,
  uploading,

  /// Retryable failure: waiting on backoff. `nextAttemptAt` says when.
  backoff,

  transcribed,

  /// Terminal. Becomes a marked gap in the transcript rather than a failed recording.
  failed,
}

@DriftDatabase(
  tables: [
    Recordings,
    Chunks,
    NoteTemplates,
    ActionReminders,
    PrivacyAudits,
    CodexNotes,
    GanttEntries,
  ],
)
class TranscriptDatabase extends _$TranscriptDatabase {
  TranscriptDatabase() : super(_open());

  TranscriptDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedSummaryPresets();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(recordings, recordings.transcriptText);
            await m.addColumn(recordings, recordings.cleanedTranscriptText);
            await m.addColumn(recordings, recordings.priority);
          }
          if (from < 3) {
            await m.addColumn(recordings, recordings.localOnly);
            await m.addColumn(recordings, recordings.templateId);
          }
          if (from < 4) {
            await m.addColumn(recordings, recordings.transcriptSegmentsJson);
            await m.addColumn(recordings, recordings.speakerNamesJson);
          }
          if (from < 5) {
            await m.createTable(privacyAudits);
          }
          if (from < 6) {
            await m.createTable(codexNotes);
          }
          if (from < 7) {
            await m.addColumn(recordings, recordings.language);
          }
          if (from < 8) {
            await _seedSummaryPresets();
          }
          if (from < 9) {
            await m.createTable(ganttEntries);
          }
        },
        beforeOpen: (details) async {
          // SQLite disables foreign keys by default, so the cascade from a deleted
          // recording to its chunks silently does nothing and the orphaned rows resume
          // forever against a recording that no longer exists.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Built-in summary presets, seeded as ordinary [NoteTemplates] rows so the existing
  /// template picker, activation, and deletion machinery needs no changes to offer
  /// them. Fixed ids and `insertOnConflictUpdate` make this safe to call on every
  /// upgrade path without duplicating rows or resurrecting one the user deleted on
  /// purpose — conflicts only occur on the id itself, and a deleted preset's id is
  /// simply gone, not reinserted.
  Future<void> _seedSummaryPresets() async {
    final now = DateTime.now();
    const presets = {
      'preset_meeting': (
        'Meeting',
        'Emphasize decisions made, action items with owners, and open questions. '
            'Note who committed to what.',
      ),
      'preset_lecture': (
        'Lecture',
        'Emphasize key concepts and structure the note by topic, with a glossary of '
            'unfamiliar terms. Action items are rare here — do not invent any.',
      ),
      'preset_interview': (
        'Interview',
        'Preserve direct quotes verbatim where they support a point. Note follow-up '
            'questions raised and any commitments the interviewee made.',
      ),
      'preset_call': (
        'Call',
        'Keep it brief: next steps, owners, and any dates mentioned. Favor what '
            'changes as a result of this call over exhaustive detail.',
      ),
      'preset_brainstorming': (
        'Brainstorming',
        'Capture every idea raised, even half-formed ones, grouped by theme. Do not '
            'assign owners or due dates unless someone explicitly volunteered.',
      ),
    };
    for (final entry in presets.entries) {
      await into(noteTemplates).insertOnConflictUpdate(
        NoteTemplatesCompanion.insert(
          id: entry.key,
          name: entry.value.$1,
          instructions: entry.value.$2,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  /// Recordings with chunks still outstanding, priority ones first — see the priority
  /// transcription queue workflow feature. Called at launch: this is what turns a
  /// process the OS killed mid-meeting into work that simply resumes.
  Future<List<String>> recordingsWithUnfinishedChunks() async {
    final rows = await (select(chunks)
          ..where((c) =>
              c.state.equalsValue(ChunkState.transcribed).not() &
              c.state.equalsValue(ChunkState.failed).not()))
        .get();
    final ids = {for (final row in rows) row.recordingId};
    if (ids.isEmpty) return const [];

    final recordingRows = await (select(recordings)
          ..where((r) => r.id.isIn(ids))
          ..orderBy([(r) => OrderingTerm.desc(r.priority)]))
        .get();
    return recordingRows.map((r) => r.id).toList();
  }

  /// Work the queue can pick up right now, oldest first, bounded by the caller so no
  /// more than two or three uploads are ever in flight.
  Future<List<Chunk>> claimable(String recordingId, {int limit = 3}) {
    final now = DateTime.now();
    return (select(chunks)
          ..where((c) => c.recordingId.equals(recordingId))
          ..where((c) =>
              c.state.equalsValue(ChunkState.pending) |
              (c.state.equalsValue(ChunkState.backoff) &
                  c.nextAttemptAt.isSmallerOrEqualValue(now)))
          ..orderBy([(c) => OrderingTerm(expression: c.chunkIndex)])
          ..limit(limit))
        .get();
  }

  /// Exponential backoff with jitter. A 429 should honour `Retry-After` instead — the
  /// caller passes that through as [override].
  Future<void> markForRetry(String chunkId, int attempts, {Duration? override}) {
    final delay = override ??
        Duration(seconds: (1 << attempts.clamp(0, 6)) + (chunkId.hashCode % 5).abs());
    return (update(chunks)..where((c) => c.id.equals(chunkId))).write(
      ChunksCompanion(
        state: const Value(ChunkState.backoff),
        attempts: Value(attempts),
        nextAttemptAt: Value(DateTime.now().add(delay)),
      ),
    );
  }

  Future<bool> isComplete(String recordingId) async {
    final pending = await (select(chunks)
          ..where((c) => c.recordingId.equals(recordingId))
          ..where((c) => c.state.equalsValue(ChunkState.transcribed).not() &
              c.state.equalsValue(ChunkState.failed).not()))
        .get();
    return pending.isEmpty;
  }

  /// Returns every chunk that can be retried manually, including failures that the
  /// automatic backoff has stopped retrying.
  Future<void> retryRecording(String recordingId) =>
      (update(chunks)..where((c) => c.recordingId.equals(recordingId))).write(
        const ChunksCompanion(
          state: Value(ChunkState.pending),
          nextAttemptAt: Value(null),
          error: Value(null),
        ),
      );
}

LazyDatabase _open() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(dir.path, 'transcript.sqlite')),
      );
    });
