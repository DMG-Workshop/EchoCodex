import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

import 'fixtures.dart';

void main() {
  const source = RecallSource(
    recordingId: 'rec_1',
    recordingTitle: 'Auth migration kickoff',
    recordedOn: '2026-09-05',
  );

  Transcript speech(int turns, {String word = 'discussion'}) => Transcript([
        for (var i = 0; i < turns; i++)
          TranscriptSegment(
            startMs: i * 5000,
            endMs: (i + 1) * 5000,
            text: 'Turn number $i of the $word, with enough words in it to '
                'count as a real sentence someone actually said.',
          ),
      ]);

  group('cutting a recording into passages', () {
    test('a passage carries where it came from, to the second', () {
      final chunks = const RecallChunker().fromTranscript(speech(3), source);

      expect(chunks, isNotEmpty);
      final first = chunks.first;
      expect(first.source.recordingId, 'rec_1');
      expect(first.source.startMs, 0);
      expect(first.source.endMs, isNotNull);
      expect(first.render(), contains('Auth migration kickoff'),
          reason: 'an answer is worth nothing unless it can be checked');
    });

    test('ids are stable, so re-indexing replaces rather than duplicates', () {
      final once = const RecallChunker().fromTranscript(speech(12), source);
      final twice = const RecallChunker().fromTranscript(speech(12), source);

      expect(once.map((c) => c.id), twice.map((c) => c.id));
      expect(once.map((c) => c.id).toSet(), hasLength(once.length));
    });

    test('a long recording becomes several passages', () {
      final chunks = const RecallChunker().fromTranscript(speech(30), source);
      expect(chunks.length, greaterThan(1));
    });

    test('consecutive passages overlap, so a straddling answer survives', () {
      final chunks = const RecallChunker(targetChars: 200, overlapChars: 60)
          .fromTranscript(speech(20), source);

      expect(chunks.length, greaterThan(2));
      final tailWords = chunks.first.text.split(' ').reversed.take(4).toList();
      expect(chunks[1].text, contains(tailWords.last),
          reason:
              'an answer cut in half by a boundary is found by neither side');
    });

    test('a fragment is not indexed', () {
      final chunks = const RecallChunker().fromTranscript(
        const Transcript([
          TranscriptSegment(startMs: 0, endMs: 500, text: 'Yes.'),
        ]),
        source,
      );

      expect(chunks, isEmpty,
          reason:
              '"Yes." retrieves against everything and means nothing alone');
    });

    test('an empty recording indexes nothing rather than throwing', () {
      expect(const RecallChunker().fromTranscript(const Transcript([]), source),
          isEmpty);
    });

    test('a timestamp on every transcript passage', () {
      final chunks = const RecallChunker().fromTranscript(speech(20), source);
      for (final chunk in chunks) {
        expect(chunk.source.startMs, isNotNull);
        expect(chunk.source.endMs, isNotNull);
      }
    });
  });

  group('cutting a note into passages', () {
    final note = NoteDocument.fromJson(validNoteJson());

    test('each extracted item is its own passage', () {
      final chunks = const RecallChunker().fromNote(note, source);

      expect(chunks.where((c) => c.text.startsWith('Decision:')), isNotEmpty);
      expect(chunks.where((c) => c.text.startsWith('Task:')), isNotEmpty);
      expect(chunks.map((c) => c.id).toSet(), hasLength(chunks.length),
          reason: 'a decision and an unrelated question share only a document');
    });

    test('an extracted item keeps the moment its quote came from', () {
      final chunks = const RecallChunker()
          .fromNote(note, source)
          .where((c) => c.kind == RecallKind.extract);

      expect(chunks, isNotEmpty);
      for (final chunk in chunks) {
        expect(chunk.source.startMs, isNotNull,
            reason: 'a hit here still has to trace to the words behind it');
      }
    });

    test('the summary is indexed as a summary, not as speech', () {
      final chunks = const RecallChunker().fromNote(note, source);
      expect(chunks.first.kind, RecallKind.summary);
    });
  });

  group('finding the passages that match', () {
    EmbeddedChunk embedded(String id, List<double> vector) => EmbeddedChunk(
          chunk: RecallChunk(
            id: id,
            text: 'passage $id',
            kind: RecallKind.transcript,
            source: source,
          ),
          vector: vector,
        );

    test('the closest passage comes first', () {
      final hits = const RecallIndex().search([
        1.0,
        0.0
      ], [
        embedded('rec_1:t0', [0.2, 1.0]),
        embedded('rec_1:t1', [1.0, 0.1]),
      ]);

      expect(hits.first.chunk.id, 'rec_1:t1');
    });

    test('nothing similar enough returns nothing, not the nearest thing', () {
      final hits = const RecallIndex().search([
        1.0,
        0.0
      ], [
        embedded('rec_1:t0', [0.0, 1.0]),
      ]);

      expect(hits, isEmpty,
          reason: 'retrieval always returns something; this is what lets the '
              'caller say nothing here answers that');
    });

    test('results are capped', () {
      final hits = const RecallIndex().search(
        [1.0, 0.0],
        [
          for (var i = 0; i < 20; i++) embedded('rec_1:t$i', [1.0, 0.0])
        ],
        limit: 5,
      );
      expect(hits, hasLength(5));
    });

    test('a vector of the wrong width is skipped, not compared', () {
      final hits = const RecallIndex().search([
        1.0,
        0.0
      ], [
        embedded('rec_1:t0', [1.0, 0.0, 0.0]),
        embedded('rec_1:t1', [1.0, 0.0]),
      ]);

      expect(hits.map((h) => h.chunk.id), ['rec_1:t1'],
          reason: 'changing the embedding model must not corrupt the results');
    });

    test('an empty corpus or query is safe', () {
      expect(const RecallIndex().search([1.0, 0.0], const []), isEmpty);
      expect(
          const RecallIndex().search(const [], [
            embedded('a', [1.0])
          ]),
          isEmpty);
    });

    test('cosine similarity behaves', () {
      expect(cosineSimilarity([1, 0], [1, 0]), closeTo(1.0, 1e-9));
      expect(cosineSimilarity([1, 0], [0, 1]), closeTo(0.0, 1e-9));
      expect(cosineSimilarity([1, 0], [-1, 0]), closeTo(-1.0, 1e-9));
      expect(cosineSimilarity([0, 0], [1, 0]), 0,
          reason: 'a zero vector has no direction to compare');
      expect(cosineSimilarity([1, 0], [1, 0, 0]), 0);
    });
  });

  group('checking the answer against the evidence', () {
    RecallHit hit(String id) => RecallHit(
          score: 0.8,
          chunk: RecallChunk(
            id: id,
            text: 'something that was said',
            kind: RecallKind.transcript,
            source: source,
          ),
        );

    test('citations are matched back to the passages supplied', () {
      final answer = const RecallPrompts().verify(
        'The team agreed to retire the session store [rec_1:t3].',
        [hit('rec_1:t3'), hit('rec_1:n0')],
      );

      expect(answer.citations.map((c) => c.id), ['rec_1:t3']);
      expect(answer.hadEvidence, isTrue);
    });

    test('a citation that was never retrieved is dropped, not shown', () {
      final answer = const RecallPrompts().verify(
        'They agreed to ship on Friday [rec_9:t7].',
        [hit('rec_1:t3')],
      );

      expect(answer.citations, isEmpty);
      expect(answer.hadEvidence, isFalse,
          reason: 'a fluent, plausible, untraceable answer is the worst thing '
              'this app could produce');
    });

    test('an answer citing nothing is not treated as grounded', () {
      final answer = const RecallPrompts().verify(
          'Teams usually migrate auth incrementally.', [hit('rec_1:t3')]);

      expect(answer.hadEvidence, isFalse);
    });

    test('saying it does not know is a valid, empty answer', () {
      final answer = const RecallPrompts()
          .verify('Nothing in these recordings covers that.', const []);

      expect(answer.isEmpty, isTrue);
      expect(answer.citations, isEmpty);
    });

    test('an ordinary aside in brackets is not read as a citation', () {
      expect(
        RecallPrompts.citedIds('They agreed [after some debate] to ship.'),
        isEmpty,
      );
    });

    test('each cited id is listed once, in the order cited', () {
      expect(
        RecallPrompts.citedIds(
            'A [rec_1:n2] then B [rec_1:t0] then A [rec_1:n2]'),
        ['rec_1:n2', 'rec_1:t0'],
      );
    });

    test('the prompt shows every passage with the id it must cite', () {
      final prompt = const RecallPrompts()
          .user('What did we decide?', [hit('rec_1:t3'), hit('rec_1:n0')]);

      expect(prompt, contains('[rec_1:t3]'));
      expect(prompt, contains('[rec_1:n0]'));
      expect(prompt, contains('What did we decide?'));
    });

    test('the rules put "say you do not know" above everything else', () {
      expect(RecallPrompts.system, contains('ONLY the passages supplied'));
      expect(RecallPrompts.system, contains('Do not answer'));
    });
  });
}
