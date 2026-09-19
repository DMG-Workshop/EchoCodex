import 'dart:convert';

import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

void main() {
  final base = Uri.parse('http://192.168.1.50:11434');

  HttpReply ok(Object body) => HttpReply(200, jsonEncode(body));

  group('the OpenAI embedding shape', () {
    Future<List<List<double>>> embed(
      HttpReply reply,
      List<String> texts,
    ) =>
        openAiStyleEmbed(
          RecordingTransport.single(reply),
          base,
          const {},
          'LM Studio',
          'nomic-embed-text',
          texts,
        );

    test('vectors come back in the order the texts went in', () async {
      // Deliberately out of order, with index saying where each belongs.
      final vectors = await embed(
        ok({
          'data': [
            {
              'index': 1,
              'embedding': [0.0, 1.0]
            },
            {
              'index': 0,
              'embedding': [1.0, 0.0]
            },
          ],
        }),
        ['first', 'second'],
      );

      expect(
          vectors,
          [
            [1.0, 0.0],
            [0.0, 1.0],
          ],
          reason:
              'a silently reordered batch mislabels every passage in it, and '
              'nothing downstream could ever detect that');
    });

    test('a response missing a vector fails loudly', () async {
      await expectLater(
        embed(
          ok({
            'data': [
              {
                'index': 0,
                'embedding': [1.0, 0.0]
              },
            ],
          }),
          ['first', 'second'],
        ),
        throwsA(isA<ProviderException>()),
      );
    });

    test('integers in the vector are accepted', () async {
      final vectors = await embed(
        ok({
          'data': [
            {
              'index': 0,
              'embedding': [1, 0]
            },
          ],
        }),
        ['only'],
      );
      expect(vectors.single, [1.0, 0.0]);
    });

    test('a refusal carries the status', () async {
      await expectLater(
        embed(HttpReply(404, '{}'), ['first']),
        throwsA(isA<ProviderException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('a response that is not an array of data fails', () async {
      await expectLater(
        embed(ok({'oops': true}), ['first']),
        throwsA(isA<ProviderException>()),
      );
    });

    test('embedding nothing costs no request', () async {
      final transport = RecordingTransport(const []);
      final vectors = await openAiStyleEmbed(
          transport, base, const {}, 'LM Studio', 'm', const []);

      expect(vectors, isEmpty);
      expect(transport.calls, isEmpty);
    });

    test('the request names the model and sends every text at once', () async {
      final transport = RecordingTransport.single(ok({
        'data': [
          {
            'index': 0,
            'embedding': [1.0]
          },
          {
            'index': 1,
            'embedding': [1.0]
          },
        ],
      }));
      await openAiStyleEmbed(
          transport, base, const {}, 'LM Studio', 'nomic', ['a', 'b']);

      expect(transport.calls, hasLength(1),
          reason: 'a hundred passages in one request beats a hundred requests');
      expect(transport.lastCall.url.path, '/v1/embeddings');
      final body = transport.lastCall.jsonBody! as Map<String, dynamic>;
      expect(body['model'], 'nomic');
      expect(body['input'], ['a', 'b']);
    });
  });

  group("Ollama's own endpoint", () {
    test('vectors come back in order', () async {
      final vectors = await ollamaEmbed(
        RecordingTransport.single(ok({
          'embeddings': [
            [1.0, 0.0],
            [0.0, 1.0],
          ],
        })),
        base,
        const {},
        'nomic-embed-text',
        ['first', 'second'],
      );

      expect(vectors, [
        [1.0, 0.0],
        [0.0, 1.0],
      ]);
    });

    test('a short batch fails rather than mislabelling', () async {
      await expectLater(
        ollamaEmbed(
          RecordingTransport.single(ok({
            'embeddings': [
              [1.0, 0.0],
            ],
          })),
          base,
          const {},
          'nomic',
          ['first', 'second'],
        ),
        throwsA(isA<ProviderException>()),
      );
    });

    test('a refusal says how to get an embedding model', () async {
      await expectLater(
        ollamaEmbed(RecordingTransport.single(HttpReply(404, '{}')), base,
            const {}, 'nomic', ['first']),
        throwsA(isA<ProviderException>()
            .having((e) => e.message, 'message', contains('ollama pull'))),
      );
    });

    test('it uses the native endpoint, not the compatibility route', () async {
      final transport = RecordingTransport.single(ok({
        'embeddings': [
          [1.0],
        ],
      }));
      await ollamaEmbed(transport, base, const {}, 'nomic', ['a']);

      expect(transport.lastCall.url.path, '/api/embed');
    });
  });
}
