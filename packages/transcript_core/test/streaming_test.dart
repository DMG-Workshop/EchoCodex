import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

/// Yields scripted chunks, so chunk boundaries can be put exactly where they hurt.
class ChunkedTransport extends HttpTransport {
  ChunkedTransport(this.chunks, {this.stall = false});

  final List<String> chunks;
  final bool stall;
  final List<HttpCall> calls = [];

  @override
  Future<HttpReply> send(HttpCall call) async {
    calls.add(call);
    return HttpReply(200, chunks.join());
  }

  @override
  Stream<String> sendStreaming(HttpCall call,
      {Duration idleTimeout = const Duration(seconds: 120)}) async* {
    calls.add(call);
    for (final chunk in chunks) {
      yield chunk;
    }
    if (stall) {
      // Never completes: stands in for a server that went quiet mid-generation.
      await Completer<void>().future;
    }
  }
}

String sse(String content) => 'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': content},
            },
          ],
        })}\n\n';

void main() {
  group('reassembling a stream', () {
    test('deltas join into the text that was generated', () {
      final acc = SseAccumulator();
      final out = StringBuffer()
        ..write(acc.add(sse('{"meta"')))
        ..write(acc.add(sse(':{"title"')))
        ..write(acc.add(sse(':"Kickoff"}}')))
        ..write(acc.flush());

      expect(out.toString(), '{"meta":{"title":"Kickoff"}}');
    });

    test('a data line split across chunks survives', () {
      final acc = SseAccumulator();
      final frame = sse('hello');
      final cut = frame.length ~/ 2;

      final out = StringBuffer()
        ..write(acc.add(frame.substring(0, cut)))
        ..write(acc.add(frame.substring(cut)))
        ..write(acc.flush());

      expect(out.toString(), 'hello',
          reason: 'chunk boundaries fall wherever TCP puts them');
    });

    test('[DONE], blank lines and keep-alive comments are ignored', () {
      final acc = SseAccumulator();
      final out = StringBuffer()
        ..write(acc.add(': keep-alive\n\n'))
        ..write(acc.add(sse('real')))
        ..write(acc.add('\n\ndata: [DONE]\n\n'))
        ..write(acc.flush());

      expect(out.toString(), 'real');
    });

    test('a malformed frame costs its own tokens, not the generation', () {
      final acc = SseAccumulator();
      final out = StringBuffer()
        ..write(acc.add('data: {not json\n\n'))
        ..write(acc.add(sse('kept')))
        ..write(acc.flush());

      expect(out.toString(), 'kept',
          reason: 'throwing would lose a generation that took minutes');
    });

    test('the Ollama and completions shapes are both understood', () {
      final acc = SseAccumulator();
      final out = StringBuffer()
        ..write(acc.add('data: ${jsonEncode({
              'message': {'content': 'a'},
            })}\n\n'))
        ..write(acc.add('data: ${jsonEncode({
              'choices': [
                {'text': 'b'},
              ],
            })}\n\n'))
        ..write(acc.add('data: ${jsonEncode({'response': 'c'})}\n\n'))
        ..write(acc.flush());

      expect(out.toString(), 'abc');
    });

    test('a frame with no trailing newline is still delivered by flush', () {
      final acc = SseAccumulator();
      final partial = sse('tail').trimRight();

      expect(acc.add(partial), isEmpty);
      expect(acc.flush(), 'tail');
    });
  });

  group('the local provider over a stream', () {
    LocalStructuringProvider providerWith(ChunkedTransport transport) =>
        LocalStructuringProvider(
          transport: transport,
          baseUrl: Uri.parse('http://192.168.1.50:11434'),
          model: 'qwen2.5:7b',
        );

    const request = StructureRequest(
      systemPrompt: 'write a note',
      userContent: 'a transcript',
      schema: {'type': 'object'},
    );

    test('a streamed reply is reassembled into the note', () async {
      final transport = ChunkedTransport([sse('{"a":'), sse('1}')]);
      final response = await providerWith(transport).structure(request);

      expect(response.rawText, '{"a":1}');
    });

    test('the request actually asks for a stream', () async {
      final transport = ChunkedTransport([sse('{}')]);
      await providerWith(transport).structure(request);

      final body = transport.calls.single.jsonBody! as Map<String, dynamic>;
      expect(body['stream'], isTrue,
          reason:
              'without this the server sends nothing until it has finished, '
              'and the response deadline becomes a thinking deadline');
    });

    test('a server that ignores stream and sends plain JSON still works',
        () async {
      final transport = ChunkedTransport([
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{"from":"whole body"}'},
            },
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 4},
        }),
      ]);

      final response = await providerWith(transport).structure(request);

      expect(response.rawText, '{"from":"whole body"}',
          reason: 'older llama.cpp builds and some proxies do exactly this');
      expect(response.outputTokens, 4);
    });

    test('a reply that is neither SSE nor JSON is handed back as-is', () async {
      final transport = ChunkedTransport(['upstream connect error']);
      final response = await providerWith(transport).structure(request);

      expect(response.rawText, 'upstream connect error',
          reason: 'the repair loop should show the user the real reply rather '
              'than an invented error');
    });

    test('an empty reply is an error, not an empty note', () async {
      final transport = ChunkedTransport(const []);

      await expectLater(
        providerWith(transport).structure(request),
        throwsA(isA<ProviderException>()
            .having((e) => e.message, 'message', contains('returned nothing'))),
      );
    });

    test('strict mode constrains the reply to the schema', () async {
      final transport = ChunkedTransport([sse('{}')]);
      await providerWith(transport).structure(request);

      final body = transport.calls.single.jsonBody! as Map<String, dynamic>;
      expect(body['response_format'], isNotNull);
      expect(
        ((body['messages'] as List).first as Map)['content'],
        'write a note',
        reason: 'the schema is in the request, so it need not be in the prompt',
      );
    });

    test('without strict mode the schema moves into the prompt', () async {
      final transport = ChunkedTransport([sse('{}')]);
      await LocalStructuringProvider(
        transport: transport,
        baseUrl: Uri.parse('http://192.168.1.50:11434'),
        model: 'qwen2.5:7b',
        strictSchema: false,
      ).structure(request);

      final body = transport.calls.single.jsonBody! as Map<String, dynamic>;
      expect(body.containsKey('response_format'), isFalse,
          reason:
              'constraining every token to a grammar is most of the work on '
              'a processor-only machine');
      final system =
          ((body['messages'] as List).first as Map)['content'] as String;
      expect(system, contains('SCHEMA'));
      expect(system, contains('"type"'),
          reason: 'a model asked for a schema it was never shown invents a '
              'plausible one, which costs the whole repair budget');
    });

    test('turning strict off is reported through capabilities', () {
      final transport = ChunkedTransport(const []);
      expect(providerWith(transport).capabilities.nativeJsonSchema, isTrue);
      expect(
        LocalStructuringProvider(
          transport: transport,
          baseUrl: Uri.parse('http://192.168.1.50:11434'),
          model: 'qwen2.5:7b',
          strictSchema: false,
        ).capabilities.nativeJsonSchema,
        isFalse,
      );
    });

    test('going quiet is reported as stopping, not as being slow', () async {
      final transport = _SilentTransport();

      await expectLater(
        LocalStructuringProvider(
          transport: transport,
          baseUrl: Uri.parse('http://192.168.1.50:11434'),
          model: 'qwen2.5:7b',
        ).structure(request),
        throwsA(isA<ProviderException>().having((e) => e.message, 'message',
            contains('stopped responding part-way'))),
      );
    });
  });
}

/// Raises the idle timeout the way a real transport would.
class _SilentTransport extends HttpTransport {
  @override
  Future<HttpReply> send(HttpCall call) async => HttpReply(200, '');

  @override
  Stream<String> sendStreaming(HttpCall call,
      {Duration idleTimeout = const Duration(seconds: 120)}) async* {
    yield sse('{"partial"');
    throw const TransportException(
        TransportFailure.timeout, 'sent nothing for 120s');
  }
}
