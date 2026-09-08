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

  /// Marks or unmarks a recording as urgent, so it is transcribed before the rest of the
  /// backlog on the next launch — see the priority transcription queue workflow feature.
  Future<void> setPriority(String recordingId, bool priority) =>
      (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
          .write(RecordingsCompanion(priority: Value(priority)));

  Future<void> setLocalOnly(String recordingId, bool localOnly) =>
      (_db.update(_db.recordings)..where((r) => r.id.equals(recordingId)))
          .write(RecordingsCompanion(localOnly: Value(localOnly)));

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
