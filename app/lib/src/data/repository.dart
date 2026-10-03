import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /// Names the user has given speakers in other recordings, most recent first.
  ///
  /// Diarization gives every recording its own labels — the same colleague is
  /// SPEAKER_01 on Monday and SPEAKER_02 on Tuesday — so without this, naming starts
  /// from nothing every time. These are offered as suggestions and never applied on
  /// their own: matching a voice to a person is exactly the kind of confident guess
  /// this app does not make, and misattributing a decision is worse than typing a name.
  ///
  /// A value still equal to its provider label is not a name, so it is skipped.
  Future<List<String>> knownSpeakerNames({int limit = 12}) async {
    final rows = await (_db.select(_db.recordings)
          ..orderBy([(r) => OrderingTerm.desc(r.startedAt)]))
        .get();

    final seen = <String>{};
    final out = <String>[];
    for (final row in rows) {
      final raw = row.speakerNamesJson;
      if (raw == null || raw.isEmpty) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        // A row written by an older build, or corrupted. One recording's worth of
        // names is not worth failing the whole lookup over.
        continue;
      }
      if (decoded is! Map) continue;
      for (final entry in decoded.entries) {
        final label = '${entry.key}';
        final name = '${entry.value}'.trim();
        if (name.isEmpty || name == label) continue;
        if (seen.add(name)) out.add(name);
        if (out.length >= limit) return out;
      }
    }
    return out;
  }

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

  // --- Tags and folders ---------------------------------------------------------
  //
  // Two mechanisms because they answer two different questions. A folder is where a
  // recording sits, one at a time, for people who think in filing. Tags are what it is
  // about, any number at once, for people who think in filters. Offering only one of
  // them means half the library stays unsorted.

  /// Lower-cased, trimmed, whitespace collapsed.
  ///
  /// The only definition of "the same tag". Exposed so the UI can tell, before saving,
  /// that what someone typed is a tag they already have.
  static String normalizeTag(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Every tag, alphabetical, with how many recordings carry each.
  ///
  /// The count is what makes the list usable: a filter row of forty tags is unreadable,
  /// and the ones worth showing first are the ones actually used.
  Stream<List<TagWithCount>> watchTags() {
    final uses = _db.recordingTags.tagId.count();
    final query = _db.select(_db.tags).join([
      leftOuterJoin(
        _db.recordingTags,
        _db.recordingTags.tagId.equalsExp(_db.tags.id),
      ),
    ])
      ..addColumns([uses])
      ..groupBy([_db.tags.id])
      ..orderBy([OrderingTerm.asc(_db.tags.normalized)]);

    return query.watch().map((rows) => [
          for (final row in rows)
            TagWithCount(row.readTable(_db.tags), row.read(uses) ?? 0),
        ]);
  }

  /// The tags on one recording, alphabetical.
  Stream<List<TagRow>> watchTagsFor(String recordingId) {
    final query = _db.select(_db.recordingTags).join([
      innerJoin(_db.tags, _db.tags.id.equalsExp(_db.recordingTags.tagId)),
    ])
      ..where(_db.recordingTags.recordingId.equals(recordingId))
      ..orderBy([OrderingTerm.asc(_db.tags.normalized)]);

    return query
        .watch()
        .map((rows) => [for (final row in rows) row.readTable(_db.tags)]);
  }

  /// The tag called [name], creating it only if no existing tag normalizes to the same
  /// thing.
  ///
  /// Returns the existing row in that case rather than failing on the unique index, so
  /// typing "Work" when "work" exists tags the recording instead of showing an error
  /// about a tag the user cannot see.
  Future<TagRow> ensureTag(String name) async {
    final normalized = normalizeTag(name);
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a tag needs a name');
    }
    final existing = await (_db.select(_db.tags)
          ..where((t) => t.normalized.equals(normalized)))
        .getSingleOrNull();
    if (existing != null) return existing;

    final row = TagRow(
      id: 'tag_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      normalized: normalized,
      createdAt: DateTime.now(),
    );
    await _db.into(_db.tags).insert(row);
    return row;
  }

  /// Puts [name] on a recording, creating the tag if it is new.
  Future<TagRow> tagRecording(String recordingId, String name) async {
    final tag = await ensureTag(name);
    await _db.into(_db.recordingTags).insertOnConflictUpdate(
          RecordingTagRow(recordingId: recordingId, tagId: tag.id),
        );
    return tag;
  }

  /// Takes one tag off one recording. The tag itself survives, because it is probably
  /// on other recordings and because deleting it here would be a surprise.
  Future<void> untagRecording(String recordingId, String tagId) =>
      (_db.delete(_db.recordingTags)
            ..where((rt) =>
                rt.recordingId.equals(recordingId) & rt.tagId.equals(tagId)))
          .go();

  /// Renames a tag, keeping it on everything it was on.
  ///
  /// Merges into an existing tag when the new name normalizes to one: renaming "wrk" to
  /// "work" when "work" exists has to mean one tag afterwards, not a unique-index
  /// failure the user cannot act on.
  Future<TagRow> renameTag(String tagId, String name) async {
    final normalized = normalizeTag(name);
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a tag needs a name');
    }
    final clash = await (_db.select(_db.tags)
          ..where((t) => t.normalized.equals(normalized) & t.id.equals(tagId).not()))
        .getSingleOrNull();

    if (clash != null) {
      await _mergeTags(from: tagId, into: clash.id);
      return clash;
    }

    await (_db.update(_db.tags)..where((t) => t.id.equals(tagId))).write(
      TagsCompanion(name: Value(name.trim()), normalized: Value(normalized)),
    );
    return (await (_db.select(_db.tags)..where((t) => t.id.equals(tagId)))
        .getSingle());
  }

  /// Moves every recording from one tag to another, then removes the empty one.
  Future<void> _mergeTags({required String from, required String into}) async {
    final moving = await (_db.select(_db.recordingTags)
          ..where((rt) => rt.tagId.equals(from)))
        .get();
    await _db.batch((batch) {
      for (final row in moving) {
        // insertOnConflictUpdate, not insert: a recording already carrying both tags
        // would otherwise fail the primary key on the way through the merge.
        batch.insert(
          _db.recordingTags,
          RecordingTagRow(recordingId: row.recordingId, tagId: into),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    await (_db.delete(_db.tags)..where((t) => t.id.equals(from))).go();
  }

  /// Removes a tag everywhere. The cascade takes it off every recording.
  Future<void> deleteTag(String tagId) =>
      (_db.delete(_db.tags)..where((t) => t.id.equals(tagId))).go();

  /// Which tags are on which recordings.
  ///
  /// One query feeding both the filter and the chips on each tile. The library already
  /// holds every recording in memory to search their text, so filtering it by tag
  /// belongs in the same pass — a separate SQL query per selected tag would be a second
  /// source of "which recordings are showing" that search would then have to agree with.
  Stream<Map<String, Set<String>>> watchTagIndex() =>
      _db.select(_db.recordingTags).watch().map((rows) {
        final index = <String, Set<String>>{};
        for (final row in rows) {
          (index[row.recordingId] ??= <String>{}).add(row.tagId);
        }
        return index;
      });

  /// Every folder a recording has been filed in, alphabetical.
  ///
  /// Derived rather than stored, so there is no such thing as an empty folder to clean
  /// up and no second place for the truth to live.
  Stream<List<String>> watchFolders() => (_db.selectOnly(_db.recordings)
        ..addColumns([_db.recordings.folder])
        ..where(_db.recordings.folder.isNotNull())
        ..groupBy([_db.recordings.folder])
        ..orderBy([OrderingTerm.asc(_db.recordings.folder)]))
      .watch()
      .map((rows) => [
            for (final row in rows)
              if (row.read(_db.recordings.folder) case final String folder)
                folder,
          ]);

  /// Files a recording, or unfiles it with null.
  Future<void> setFolder(String recordingId, String? folder) {
    final cleaned = folder?.trim();
    return (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
        .write(RecordingsCompanion(
      folder: Value(cleaned == null || cleaned.isEmpty ? null : cleaned),
    ));
  }

  /// Renames a folder and everything nested under it.
  ///
  /// A path rename, so "Work" becoming "Clients" takes "Work/Acme" with it. Without the
  /// separator check, renaming "Work" would also catch "Workshop".
  Future<int> renameFolder(String from, String to) async {
    final target = to.trim();
    if (target.isEmpty) {
      throw ArgumentError.value(to, 'to', 'a folder needs a name');
    }
    final affected = await (_db.select(_db.recordings)
          ..where((r) => r.folder.equals(from) | r.folder.like('$from/%')))
        .get();
    await _db.batch((batch) {
      for (final recording in affected) {
        batch.update(
          _db.recordings,
          RecordingsCompanion(
            folder: Value(target + recording.folder!.substring(from.length)),
          ),
          where: (r) => r.id.equals(recording.id),
        );
      }
    });
    return affected.length;
  }

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

  // --- Recall index ---------------------------------------------------
  //
  // A derived cache. See RecallChunks in database.dart for why it is safe to drop
  // wholesale when the embedding model changes.

  /// Replaces everything indexed for one recording.
  ///
  /// Delete-then-insert rather than upsert: a re-index after the note is rewritten
  /// produces a different number of passages, and leaving the old surplus behind means
  /// answers citing text that is no longer in the note.
  Future<void> saveRecallChunks(
    String recordingId,
    List<EmbeddedChunk> chunks, {
    required String embeddingModel,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.delete(_db.recallChunks)
            ..where((c) => c.recordingId.equals(recordingId)))
          .go();
      for (final entry in chunks) {
        if (entry.vector.isEmpty) continue;
        await _db.into(_db.recallChunks).insert(
              RecallChunksCompanion.insert(
                id: entry.chunk.id,
                recordingId: recordingId,
                kind: entry.chunk.kind.name,
                body: entry.chunk.text,
                startMs: Value(entry.chunk.source.startMs),
                endMs: Value(entry.chunk.source.endMs),
                vector: packVector(entry.vector),
                dimensions: entry.vector.length,
                embeddingModel: embeddingModel,
                indexedAt: now,
              ),
            );
      }
    });
  }

  /// Everything indexed, for a linear scan.
  ///
  /// Rows whose width does not match [dimensions] are left out rather than returned
  /// and skipped later: they cannot be compared, and handing them to the caller only
  /// moves the same check somewhere less obvious.
  Future<List<EmbeddedChunk>> recallCorpus({
    required int dimensions,
    required String embeddingModel,
  }) async {
    final rows = await (_db.select(_db.recallChunks)
          ..where((c) =>
              c.dimensions.equals(dimensions) &
              c.embeddingModel.equals(embeddingModel)))
        .get();
    if (rows.isEmpty) return const [];

    // One pass over the recordings so each passage can name the recording it came
    // from without a query per row.
    final titles = {
      for (final recording in await all())
        recording.id: (recording.title, recording.startedAt),
    };

    final out = <EmbeddedChunk>[];
    for (final row in rows) {
      final meta = titles[row.recordingId];
      if (meta == null) continue;
      out.add(EmbeddedChunk(
        vector: unpackVector(row.vector),
        chunk: RecallChunk(
          id: row.id,
          text: row.body,
          kind: RecallKind.values
                  .where((k) => k.name == row.kind)
                  .firstOrNull ??
              RecallKind.transcript,
          source: RecallSource(
            recordingId: row.recordingId,
            recordingTitle:
                meta.$1.isEmpty ? 'Untitled recording' : meta.$1,
            recordedOn: _isoDay(meta.$2),
            startMs: row.startMs,
            endMs: row.endMs,
          ),
        ),
      ));
    }
    return out;
  }

  /// How much is indexed, and how much is not — what the ask screen needs to say
  /// whether an empty answer means "nothing was said about that" or "nothing has
  /// been indexed yet".
  Future<(int indexed, int total)> recallCoverage() async {
    final recordings = await all();
    final rows = await _db.select(_db.recallChunks).get();
    final withChunks = {for (final row in rows) row.recordingId};
    final eligible =
        recordings.where((r) => r.transcriptText != null).toList();
    return (
      eligible.where((r) => withChunks.contains(r.id)).length,
      eligible.length,
    );
  }

  /// Drops the whole index. Cheap to rebuild and wrong to keep once the model that
  /// produced it has changed.
  Future<void> clearRecallIndex() => _db.delete(_db.recallChunks).go();

  static String _isoDay(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';

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


/// Packs a vector as little-endian float32.
///
/// float32 rather than float64 on purpose: embedding models emit float32 to begin
/// with, cosine similarity over them is unaffected at this precision, and it halves a
/// table that grows with every hour recorded.
Uint8List packVector(List<double> vector) {
  final floats = Float32List.fromList(vector);
  return Uint8List.view(floats.buffer, 0, floats.lengthInBytes);
}

/// Reads back what [packVector] wrote.
List<double> unpackVector(Uint8List bytes) {
  // A view needs 4-byte alignment and a blob out of sqlite offers no such promise,
  // so copy when the offset is not aligned rather than throwing on some rows only.
  final aligned = bytes.offsetInBytes % 4 == 0
      ? bytes
      : Uint8List.fromList(bytes);
  return Float32List.view(
    aligned.buffer,
    aligned.offsetInBytes,
    aligned.lengthInBytes ~/ 4,
  ).toList();
}

/// A tag and how many recordings carry it.
class TagWithCount {
  const TagWithCount(this.tag, this.count);

  final TagRow tag;
  final int count;
}
