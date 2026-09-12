import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:transcript_core/transcript_core.dart' hide ChunkState;

import 'database.dart';

/// Persistence for recordings and their notes.
///
/// The transcript is stored the moment it exists, before structuring is attempted, so a
/// model failure never costs the user their recording. The note is stored as the raw JSON
/// the provider returned alongside the schema and prompt versions that produced it, so an
/// old note stays readable after either changes.
class RecordingRepository {
  const RecordingRepository(this._db);

  final TranscriptDatabase _db;

  Future<void> recordPrivacyAudit(String action, String detail) =>
      _db.into(_db.privacyAudits).insert(
            PrivacyAuditsCompanion.insert(
              id: 'audit_${DateTime.now().microsecondsSinceEpoch}',
              createdAt: DateTime.now(),
              action: action,
              detail: detail,
            ),
          );

  Future<void> restoreBackupRecording(
    Map<String, dynamic> data, {
    List<int>? audioBytes,
    String? audioExtension,
  }) async {
    final id = data['id'] as String?;
    if (id == null || id.isEmpty) return;
    String? audioPath;
    if (audioBytes != null && audioBytes.isNotEmpty) {
      final directory = await getApplicationDocumentsDirectory();
      final path =
          p.join(directory.path, 'restored_$id${audioExtension ?? '.wav'}');
      await File(path).writeAsBytes(audioBytes);
      audioPath = path;
    }
    await _db.into(_db.recordings).insertOnConflictUpdate(
          RecordingsCompanion.insert(
            id: id,
            startedAt: DateTime.tryParse(data['startedAt'] as String? ?? '') ??
                DateTime.now(),
            title: Value(data['title'] as String? ?? ''),
            durationMs: Value(data['durationMs'] as int? ?? 0),
            transcriptionProviderId:
                Value(data['transcriptionProviderId'] as String?),
            structuringProviderId:
                Value(data['structuringProviderId'] as String?),
            structuringModel: Value(data['structuringModel'] as String?),
            noteJson: Value(data['noteJson'] as String?),
            transcriptText: Value(data['transcriptText'] as String?),
            cleanedTranscriptText:
                Value(data['cleanedTranscriptText'] as String?),
            localOnly: Value(data['localOnly'] as bool? ?? false),
            audioPath: Value(audioPath),
          ),
        );
  }

  Future<List<PrivacyAudit>> privacyAudits() => (_db.select(_db.privacyAudits)
        ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
      .get();

  Future<List<ProcessingQueueItem>> processingQueue() async {
    final recordings = await all();
    final result = <ProcessingQueueItem>[];
    for (final recording in recordings) {
      final chunks = await (_db.select(_db.chunks)
            ..where((c) => c.recordingId.equals(recording.id)))
          .get();
      if (chunks.isEmpty ||
          chunks.every((c) => c.state == ChunkState.transcribed)) {
        continue;
      }
      final retryable = chunks
          .where((c) =>
              c.state == ChunkState.failed || c.state == ChunkState.backoff)
          .length;
      final nextRetry = chunks
          .map((c) => c.nextAttemptAt)
          .whereType<DateTime>()
          .fold<DateTime?>(
              null,
              (current, value) =>
                  current == null || value.isBefore(current) ? value : current);
      result.add(ProcessingQueueItem(
        recording: recording,
        total: chunks.length,
        completed:
            chunks.where((c) => c.state == ChunkState.transcribed).length,
        failed: chunks.where((c) => c.state == ChunkState.failed).length,
        retryable: retryable,
        nextRetryAt: nextRetry,
      ));
    }
    return result;
  }

  Future<void> retryRecording(String recordingId) =>
      _db.retryRecording(recordingId);

  /// [title] is set for an imported file, where the file's own name is a better
  /// placeholder than the empty string until the transcript supplies one.
  Future<String> createRecording({
    required String path,
    required Duration duration,
    required String transcriptionProviderId,
    required String structuringProviderId,
    String? title,
    bool localOnly = false,
    String? templateId,
  }) async {
    final id = 'r_${DateTime.now().microsecondsSinceEpoch}';
    await _db.into(_db.recordings).insert(RecordingsCompanion.insert(
          id: id,
          startedAt: DateTime.now(),
          title: title == null ? const Value.absent() : Value(title),
          audioPath: Value(path),
          durationMs: Value(duration.inMilliseconds),
          transcriptionProviderId: Value(transcriptionProviderId),
          structuringProviderId: Value(structuringProviderId),
          localOnly: Value(localOnly),
          templateId: Value(templateId),
        ));
    return id;
  }

  /// Saves the transcript on its own. Called before structuring is attempted.
  ///
  /// [cleaned] is the same transcript with filler and stutters removed, computed by the
  /// caller only when the punctuation and filler cleanup workflow feature is on — the
  /// raw text is always kept alongside it, never replaced.
  Future<void> saveTranscript(
    String recordingId,
    Transcript transcript, {
    String? cleaned,
  }) =>
      (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
          .write(
        RecordingsCompanion(
          title: Value(_provisionalTitle(transcript)),
          transcriptText: Value(transcript.plainText),
          transcriptSegmentsJson: Value(jsonEncode(transcript.segments
              .map((segment) => {
                    'startMs': segment.startMs,
                    'endMs': segment.endMs,
                    'text': segment.text,
                    if (segment.speaker != null) 'speaker': segment.speaker,
                  })
              .toList())),
          cleanedTranscriptText: Value(cleaned),
          noteJson: const Value.absent(),
        ),
      );

  Future<void> saveSpeakerNames(
    String recordingId,
    Map<String, String> names,
  ) =>
      (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
          .write(
        RecordingsCompanion(speakerNamesJson: Value(jsonEncode(names))),
      );

  /// Corrects the text of a single transcript segment \u2014 typically caught while
  /// listening back to the recording. Recomputes the assembled transcript text from the
  /// edited segments so the two never drift out of sync; the separately-cached cleaned
  /// transcript is left untouched, since a wording fix here does not warrant re-running
  /// the cleanup pass.
  Future<void> updateTranscriptSegment(
    String recordingId,
    int index,
    String text,
  ) async {
    final row = await (_db.select(_db.recordings)
          ..where((r) => r.id.equals(recordingId)))
        .getSingleOrNull();
    final raw = row?.transcriptSegmentsJson;
    if (raw == null) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List || index < 0 || index >= decoded.length) return;

    final segments = decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    segments[index]['text'] = text;

    await (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
        .write(RecordingsCompanion(
      transcriptSegmentsJson: Value(jsonEncode(segments)),
      transcriptText: Value(
        segments.map((s) => s['text'] as String? ?? '').join(' '),
      ),
    ));
  }

  /// Marks or unmarks a recording as urgent, so it is transcribed before the rest of the
  /// backlog on the next launch — see the priority transcription queue workflow feature.
  Future<void> setPriority(String recordingId, bool priority) =>
      (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
          .write(RecordingsCompanion(priority: Value(priority)));

  Future<void> setLocalOnly(String recordingId, bool localOnly) =>
      (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
          .write(RecordingsCompanion(localOnly: Value(localOnly)));

  /// Sets or clears this recording's own transcription language, overriding the global
  /// default the next time it is (re)transcribed \u2014 e.g. after auto-detect guessed
  /// wrong and the recording needs a retry with the correct language.
  Future<void> setLanguage(String recordingId, String? language) =>
      (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
          .write(RecordingsCompanion(language: Value(language)));

  Future<List<NoteTemplate>> templates() => (_db.select(_db.noteTemplates)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();

  Future<void> saveTemplate({
    required String id,
    required String name,
    required String instructions,
  }) async {
    final now = DateTime.now();
    await _db.into(_db.noteTemplates).insertOnConflictUpdate(
          NoteTemplatesCompanion.insert(
            id: id,
            name: name,
            instructions: instructions,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> deleteTemplate(String id) =>
      (_db.delete(_db.noteTemplates)..where((t) => t.id.equals(id))).go();

  Future<void> saveReminder({
    required String recordingId,
    required String taskId,
    required String title,
    required DateTime remindAt,
  }) async {
    await _db.into(_db.actionReminders).insertOnConflictUpdate(
          ActionRemindersCompanion.insert(
            id: '${recordingId}_$taskId',
            recordingId: recordingId,
            taskId: taskId,
            title: title,
            remindAt: remindAt,
          ),
        );
  }

  Future<List<ActionReminder>> reminders({bool pendingOnly = false}) {
    final query = _db.select(_db.actionReminders)
      ..orderBy([(r) => OrderingTerm.asc(r.remindAt)]);
    if (pendingOnly) {
      query.where((r) => r.enabled & r.completed.not());
    }
    return query.get();
  }

  Future<void> completeReminder(String id, bool completed) =>
      (_db.update(_db.actionReminders)..where((r) => r.id.equals(id))).write(
        ActionRemindersCompanion(completed: Value(completed)),
      );

  Future<void> deleteReminder(String recordingId, String taskId) =>
      (_db.delete(_db.actionReminders)
            ..where((r) => r.id.equals('${recordingId}_$taskId')))
          .go();

  Future<void> saveNote(String recordingId, StructureOutcome outcome) =>
      (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
          .write(
        RecordingsCompanion(
          title: Value(outcome.document.meta.title),
          noteJson: Value(jsonEncode(outcome.raw)),
          structuringModel: Value(outcome.model),
          noteSchemaVersion: const Value(noteSchemaVersion),
          promptVersion: const Value(StructuringPrompts.promptVersion),
          inputTokens: Value(outcome.inputTokens),
          outputTokens: Value(outcome.outputTokens),
        ),
      );

  /// Persists an edited note.
  ///
  /// Board edits write the whole document back rather than patching a task in place:
  /// the note is stored as the JSON the provider returned, and keeping it one value
  /// means an edit can never leave the stored document half-updated.
  Future<void> updateNote(String recordingId, NoteDocument document) =>
      (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
          .write(
        RecordingsCompanion(
          noteJson: Value(jsonEncode(document.toJson())),
          title: Value(document.meta.title),
        ),
      );

  Future<List<Recording>> all() => (_db.select(_db.recordings)
        ..orderBy([(r) => OrderingTerm.desc(r.startedAt)]))
      .get();

  Stream<List<Recording>> watchAll() => (_db.select(_db.recordings)
        ..orderBy([(r) => OrderingTerm.desc(r.startedAt)]))
      .watch();

  Future<Recording?> byId(String id) =>
      (_db.select(_db.recordings)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  /// Deletes the row and the audio file together, so storage does not leak recordings
  /// the user believes they removed.
  Future<void> delete(String id) async {
    final recording = await byId(id);
    final path = recording?.audioPath;
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
    await (_db.delete(_db.recordings)..where((r) => r.id.equals(id))).go();
  }

  // --- Codex ---------------------------------------------------------
  //
  // Independent of the recordings table on purpose: a Codex note outlives the
  // transcript it may have started from. See CodexNotes in database.dart for why
  // sourceRecordingId is a soft, nullable link rather than a hard reference.

  Stream<List<CodexNote>> watchCodexNotes() => (_db.select(_db.codexNotes)
        ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
      .watch();

  Future<List<CodexNote>> codexNotes() => (_db.select(_db.codexNotes)
        ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
      .get();

  /// Adds a freeform note, or one copied from a transcript line — [sourceRecordingId]
  /// and [sourceRecordingTitle] are set only in the latter case, and are provenance
  /// only: nothing about the note's lifetime depends on that recording still existing.
  Future<String> createCodexNote(
    String body, {
    String? sourceRecordingId,
    String? sourceRecordingTitle,
  }) async {
    final now = DateTime.now();
    final id = 'codex_${now.microsecondsSinceEpoch}';
    await _db.into(_db.codexNotes).insert(
          CodexNotesCompanion.insert(
            id: id,
            body: body,
            createdAt: now,
            updatedAt: now,
            sourceRecordingId: Value(sourceRecordingId),
            sourceRecordingTitle: Value(sourceRecordingTitle),
          ),
        );
    return id;
  }

  Future<void> updateCodexNote(String id, String body) =>
      (_db.update(_db.codexNotes)..where((n) => n.id.equals(id))).write(
        CodexNotesCompanion(
          body: Value(body),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteCodexNote(String id) =>
      (_db.delete(_db.codexNotes)..where((n) => n.id.equals(id))).go();

  // --- Gantt chart --------------------------------------------------
  //
  // Scoped to its recording and written only by hand: see GanttEntries in
  // database.dart for why a model's dates never land here on their own.

  Stream<List<GanttEntry>> watchGanttEntries(String recordingId) =>
      (_db.select(_db.ganttEntries)
            ..where((e) => e.recordingId.equals(recordingId))
            ..orderBy([
              (e) => OrderingTerm(expression: e.startDate),
              (e) => OrderingTerm(expression: e.title),
            ]))
          .watch();

  Future<List<GanttEntry>> ganttEntries(String recordingId) =>
      (_db.select(_db.ganttEntries)
            ..where((e) => e.recordingId.equals(recordingId))
            ..orderBy([
              (e) => OrderingTerm(expression: e.startDate),
              (e) => OrderingTerm(expression: e.title),
            ]))
          .get();

  /// Puts one item on the chart, or rewrites the one already there.
  ///
  /// [id] is supplied by the caller when editing and minted here otherwise, so an edit
  /// can never quietly become a second bar for the same piece of work.
  Future<String> saveGanttEntry({
    required String recordingId,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    String? id,
    String? owner,
    String? workstream,
    int percentComplete = 0,
    bool milestone = false,
    List<String> dependsOn = const [],
    DateBasis dateBasis = DateBasis.explicit,
    String? sourceTaskId,
  }) async {
    final now = DateTime.now();
    // A finish before its start is rejected at the form, but storage should not depend
    // on that: an inverted row would be a bar of negative length forever. A milestone
    // collapses to a single date, so the zero-duration convention needs no special
    // case anywhere downstream.
    final from = startDate.isAfter(endDate) ? endDate : startDate;
    final start = milestone ? startDate : from;
    final end = milestone ? startDate : endDate;

    final fields = GanttEntriesCompanion(
      recordingId: Value(recordingId),
      title: Value(title),
      startDate: Value(start),
      endDate: Value(end),
      owner: Value(owner),
      workstream: Value(workstream),
      percentComplete: Value(percentComplete.clamp(0, 100)),
      milestone: Value(milestone),
      dependsOnJson: Value(dependsOn.isEmpty ? null : jsonEncode(dependsOn)),
      dateBasis: Value(dateBasis.name),
      sourceTaskId: Value(sourceTaskId),
      updatedAt: Value(now),
    );

    // An edit rewrites the row in place and leaves createdAt alone: when the item was
    // first committed to is part of the record, and an upsert would quietly reset it.
    if (id != null) {
      final rows = await (_db.update(_db.ganttEntries)
            ..where((e) => e.id.equals(id)))
          .write(fields);
      if (rows > 0) return id;
    }

    final entryId = id ?? 'gantt_${now.microsecondsSinceEpoch}';
    await _db.into(_db.ganttEntries).insert(
          fields.copyWith(id: Value(entryId), createdAt: Value(now)),
        );
    return entryId;
  }

  Future<void> deleteGanttEntry(String id) =>
      (_db.delete(_db.ganttEntries)..where((e) => e.id.equals(id))).go();

  Future<void> deleteSourceAudio(String id) async {
    final recording = await byId(id);
    final path = recording?.audioPath;
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
    await (_db.update(_db.recordings)..where((r) => r.id.equals(id))).write(
      const RecordingsCompanion(audioPath: Value(null)),
    );
    await recordPrivacyAudit('source_audio_deleted', 'Recording $id');
  }

  /// Until the model has named the recording, the first words of it will do.
  static String _provisionalTitle(Transcript transcript) {
    final text = transcript.plainText.trim();
    if (text.isEmpty) return 'Untitled recording';
    final words = text.split(RegExp(r'\s+')).take(6).join(' ');
    return words.length > 48 ? '${words.substring(0, 48)}…' : words;
  }
}

class ProcessingQueueItem {
  const ProcessingQueueItem({
    required this.recording,
    required this.total,
    required this.completed,
    required this.failed,
    required this.retryable,
    required this.nextRetryAt,
  });

  final Recording recording;
  final int total;
  final int completed;
  final int failed;
  final int retryable;
  final DateTime? nextRetryAt;

  double get fraction => total == 0 ? 0 : completed / total;
}

/// Decodes a stored note back into a document. Returns null for a recording whose
/// structuring failed or has not run — the transcript is still there either way.
NoteDocument? decodeNote(Recording recording) {
  final raw = recording.noteJson;
  if (raw == null) return null;
  final decoded = jsonDecode(raw);
  return decoded is Map<String, dynamic>
      ? NoteDocument.fromJson(decoded)
      : null;
}
