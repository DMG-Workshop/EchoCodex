import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transcript_app/src/data/database.dart';
import 'package:transcript_app/src/data/repository.dart';
import 'package:transcript_core/transcript_core.dart' as core;

void main() {
  late TranscriptDatabase db;
  late RecordingRepository repository;

  setUp(() {
    db = TranscriptDatabase.forTesting(NativeDatabase.memory());
    repository = RecordingRepository(db);
  });

  tearDown(() => db.close());

  Future<void> insertRecordingWithOpenChunk(String id) async {
    await db.into(db.recordings).insert(
          RecordingsCompanion.insert(id: id, startedAt: DateTime.now()),
        );
    await db.into(db.chunks).insert(ChunksCompanion.insert(
          id: '${id}_c0',
          recordingId: id,
          chunkIndex: 0,
          startMs: 0,
          contentStartMs: 0,
          endMs: 1000,
          state: ChunkState.pending,
        ));
  }

  test('recordings with unfinished chunks come back priority-first', () async {
    await insertRecordingWithOpenChunk('r1');
    await insertRecordingWithOpenChunk('r2');
    await insertRecordingWithOpenChunk('r3');

    await repository.setPriority('r2', true);

    final pending = await db.recordingsWithUnfinishedChunks();
    expect(pending.first, 'r2');
    expect(pending.toSet(), {'r1', 'r2', 'r3'});
  });

  test('a recording with nothing outstanding is not returned', () async {
    await db.into(db.recordings).insert(
          RecordingsCompanion.insert(id: 'done', startedAt: DateTime.now()),
        );

    expect(await db.recordingsWithUnfinishedChunks(), isEmpty);
  });

  test('saveTranscript stores the raw text and, when given one, the cleaned '
      'text alongside it', () async {
    await db.into(db.recordings).insert(
          RecordingsCompanion.insert(id: 'r1', startedAt: DateTime.now()),
        );

    final transcript = core.Transcript(const [
      core.TranscriptSegment(startMs: 0, endMs: 1000, text: 'um so hello'),
    ]);
    await repository.saveTranscript(
      'r1',
      transcript,
      cleaned: 'So hello.',
    );

    final row = await repository.byId('r1');
    expect(row!.transcriptText, 'um so hello');
    expect(row.cleanedTranscriptText, 'So hello.');
  });

  test('saveTranscript without a cleaned version leaves it null', () async {
    await db.into(db.recordings).insert(
          RecordingsCompanion.insert(id: 'r1', startedAt: DateTime.now()),
        );

    final transcript = core.Transcript(
      const [core.TranscriptSegment(startMs: 0, endMs: 1000, text: 'hello')],
    );
    await repository.saveTranscript('r1', transcript);

    final row = await repository.byId('r1');
    expect(row!.transcriptText, 'hello');
    expect(row.cleanedTranscriptText, isNull);
  });

  test('setPriority toggles the flag', () async {
    await db.into(db.recordings).insert(
          RecordingsCompanion.insert(id: 'r1', startedAt: DateTime.now()),
        );

    expect((await repository.byId('r1'))!.priority, isFalse);
    await repository.setPriority('r1', true);
    expect((await repository.byId('r1'))!.priority, isTrue);
  });
}
