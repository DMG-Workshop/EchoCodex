import 'dart:convert';

import '../../discovery/local_discovery.dart';
import '../../schema/dialects.dart';
import '../capabilities.dart';
import '../connection.dart';
import '../errors.dart';
import '../http_transport.dart';
import '../provider.dart';
import 'openai.dart';

/// Which local server is on the other end. Both speak the OpenAI chat API; they differ in
/// their native management endpoints, which is where the context window lives.
enum LocalFlavor {
  ollama(defaultPort: 11434, label: 'Ollama'),
  lmStudio(defaultPort: 1234, label: 'LM Studio');

  const LocalFlavor({required this.defaultPort, required this.label});

  final int defaultPort;
  final String label;
}

/// A model running on the user's own machine.
///
/// The interesting problem here is not the protocol — it is that the context window is
/// small and unknown. A 7B model served at 4096 tokens cannot hold a one-hour transcript,
/// and the failure mode is silent truncation. So this adapter discovers the real context
/// length at connection-test time and reports it through [capabilities], which is what the
/// pipeline uses to decide between a single pass and map/reduce.
class LocalStructuringProvider extends StructuringProvider {
  LocalStructuringProvider({
    required HttpTransport transport,
    required this.baseUrl,
    required this.model,
    this.flavor = LocalFlavor.ollama,
    this.apiKey,
    this.strictSchema = true,
  }) : _transport = transport;

  /// Local models are slow to first token when cold — loading a 7B from disk can take
  /// most of a minute. A cloud-scale timeout here produces spurious failures.
  static const Duration localTimeout = Duration(minutes: 10);

  final HttpTransport _transport;
  final Uri baseUrl;
  final String model;
  final LocalFlavor flavor;

  /// Some users put a reverse proxy with auth in front of their model server.
  final String? apiKey;

  /// Whether to constrain generation to the schema with `response_format`.
  ///
  /// On by default because the output is then valid by construction. The cost is
  /// severe on CPU: llama.cpp compiles the schema into a GBNF grammar and checks every
  /// sampled token against it, which for a schema this size is most of the work — it
  /// is why a 30-second recording can saturate every core for minutes.
  ///
  /// Off, the schema goes in the prompt instead and the pipeline's repair loop handles
  /// a model that strays. Faster, and usually fine on a capable model; worse on a
  /// small one, which is exactly when someone would be reaching for this.
  final bool strictSchema;

  int _discoveredContext = 0;

  @override
  ProviderId get id => ProviderId('local:${flavor.name}:${baseUrl.host}');

  @override
  String get displayName => '${flavor.label} (${baseUrl.host})';

  @override
  bool get isLocalEndpoint => true;

  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
        acceptsAudio: false,
        acceptsText: true,
        // False when the schema is only in the prompt, so anything downstream
        // deciding how much to trust the shape of the reply sees the truth.
        nativeJsonSchema: strictSchema,
        requiresApiKey: false,
        runsOnDevice: false, // on the user's network, not on the phone
        contextWindowTokens: _discoveredContext,
        maxOutputTokens: 4096,
      );

  Map<String, String> get _headers => {
        'accept': 'application/json',
        if (apiKey != null && apiKey!.isNotEmpty)
          'authorization': 'Bearer $apiKey',
      };

  @override
  Future<ConnectionResult> test() async {
    final result = await openAiStyleTest(
      _transport,
      baseUrl,
      _headers,
      flavor.label,
      model,
      isLocalEndpoint: true,
    );
    if (!result.ok) return result;

    final context = await _discoverContextWindow();
    if (context == null) {
      return ConnectionResult.success(
        summary: '${result.summary} · context window unknown',
        models: result.models,
        latency: result.latency,
        detail:
            'Long recordings will be processed in sections, conservatively.',
      );
    }

    _discoveredContext = context;
    return ConnectionResult.success(
      summary: '${result.summary} · ${_formatTokens(context)} context',
      models: result.models,
      latency: result.latency,
      detail:
          '${ModelCapacity.describe(context)}. Anything longer is processed in '
          'sections and merged.',
    );
  }

  Future<int?> _discoverContextWindow() => contextWindowFor(model);

  /// The real context length of [modelName], read from Ollama's `/api/show`.
  ///
  /// LM Studio does not expose it over HTTP at all, so callers get null and the pipeline
  /// stays conservative rather than guessing a number the model picker would then show
  /// as fact.
  Future<int?> contextWindowFor(String modelName) async {
    if (flavor != LocalFlavor.ollama) return null;
    try {
      final reply = await _transport.send(HttpCall(
        method: 'POST',
        url: baseUrl.resolve('/api/show'),
        headers: _headers,
        jsonBody: {'model': modelName},
        timeout: const Duration(seconds: 30),
      ));
      if (!reply.ok) return null;

      final info = reply.json?['model_info'];
      if (info is! Map<String, dynamic>) return null;
      for (final entry in info.entries) {
        if (entry.key.endsWith('.context_length') && entry.value is int) {
          return entry.value as int;
        }
      }
      return null;
    } on TransportException {
      return null; // the chat endpoint already tested fine; this is a bonus
    }
  }

  /// How long the server may stay silent before it is assumed to have stopped.
  ///
  /// The meaningful check for a local model, replacing a deadline on total generation
  /// time. A 7B on CPU emits a token every few hundred milliseconds even when badly
  /// loaded; two minutes of nothing at all means something has gone wrong, while an
  /// hour of steady output is simply a slow machine doing its job.
  static const Duration idleTimeout = Duration(minutes: 2);

  @override
  Future<StructureResponse> structure(StructureRequest request) async {
    final call = HttpCall(
      method: 'POST',
      url: baseUrl.resolve('/v1/chat/completions'),
      headers: _headers,
      timeout: localTimeout,
      jsonBody: {
        'model': model,
        'max_tokens': request.maxOutputTokens,
        // Streamed so the response starts immediately. Without this the server sends
        // nothing until the entire note is generated, and any timeout on the response
        // becomes a timeout on how long the model is allowed to think — which on a
        // CPU-bound box producing grammar-constrained JSON is the bug users hit as
        // "it times out when it makes the notes".
        'stream': true,
        'messages': [
          {
            'role': 'system',
            'content': strictSchema
                ? request.systemPrompt
                : _promptWithSchema(request),
          },
          for (final turn in request.priorTurns)
            {'role': turn.role, 'content': turn.content},
          {'role': 'user', 'content': request.userContent},
        ],
        if (strictSchema)
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'note_document',
              'strict': true,
              'schema':
                  renderSchema(request.schema, SchemaDialect.openAiStrict),
            },
          },
      },
    );

    final accumulator = SseAccumulator();
    final text = StringBuffer();
    final raw = StringBuffer();
    try {
      await for (final chunk
          in _transport.sendStreaming(call, idleTimeout: idleTimeout)) {
        raw.write(chunk);
        text.write(accumulator.add(chunk));
      }
      text.write(accumulator.flush());
    } on TransportException catch (e) {
      throw ProviderException(displayName, 0, _transportMessage(e));
    }

    final streamed = text.toString();
    if (streamed.isNotEmpty) {
      // Token counts are not worth a second request: a streamed response carries
      // usage only on some servers, and the cost meter prices cloud calls anyway.
      return StructureResponse(rawText: streamed, model: model);
    }

    // Nothing came out of the SSE parse. Either the server ignored `stream` and sent
    // an ordinary JSON body, or it streamed a shape this does not know. Reading the
    // raw text as a normal completion recovers the first case, which is the one that
    // actually happens — older llama.cpp builds and some proxies do exactly that.
    return _fromWholeBody(raw.toString());
  }

  /// The schema, carried in the prompt because the request will not constrain it.
  ///
  /// Same shape the on-device Gemma adapter uses, for the same reason: a model asked
  /// for "the NoteDocument schema" without being shown it will invent a plausible one,
  /// and a plausible wrong shape costs the whole repair budget before anyone learns
  /// what went wrong.
  String _promptWithSchema(StructureRequest request) =>
      '${request.systemPrompt}\n\n'
      'SCHEMA — the NoteDocument JSON Schema referenced above. Conform to it '
      'exactly: every property it requires must be present, and no other '
      'properties may be added. Reply with that JSON object and nothing else — '
      'no prose, no code fence.\n'
      '${jsonEncode(renderSchema(request.schema, SchemaDialect.plain))}';

  /// Parses a non-streamed chat completion, for a server that ignored `stream`.
  StructureResponse _fromWholeBody(String body) {
    if (body.trim().isEmpty) {
      throw ProviderException(
        displayName,
        0,
        'The service accepted the request and returned nothing at all.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      // Not JSON either — hand back what arrived rather than inventing an error, so
      // the structuring pipeline's own repair loop can show the user the real reply.
      return StructureResponse(rawText: body, model: model);
    }
    if (decoded is! Map) return StructureResponse(rawText: body, model: model);

    final choices = decoded['choices'];
    var text = '';
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map) text = message['content']?.toString() ?? '';
        if (text.isEmpty && first['text'] is String) {
          text = first['text'] as String;
        }
      }
    }
    final usage = (decoded['usage'] as Map?)?.cast<String, dynamic>();
    return StructureResponse(
      rawText: text,
      inputTokens: usage?['prompt_tokens'] as int?,
      outputTokens: usage?['completion_tokens'] as int?,
      model: decoded['model']?.toString() ?? model,
    );
  }

  String _transportMessage(TransportException e) => e.kind ==
          TransportFailure.timeout
      ? 'The service stopped responding part-way through writing the note. '
          'On a local model this usually means it ran out of memory or was '
          'stopped; a smaller model or a shorter recording will get further.'
      : e.message;

  static String _formatTokens(int tokens) =>
      tokens >= 1000 ? '${(tokens / 1000).round()}k' : '$tokens';
}

/// Candidate addresses to probe when the user asks the app to find their model server.
/// mDNS is unreliable on mobile, so discovery is a scan of the obvious ports on the
/// device's own subnet plus the emulator loopback aliases.
List<Uri> localCandidates(String subnetPrefix) => [
      for (final flavor in LocalFlavor.values) ...[
        Uri.parse('http://$subnetPrefix.1:${flavor.defaultPort}'),
        // Android emulator alias for the host machine.
        Uri.parse('http://10.0.2.2:${flavor.defaultPort}'),
      ],
    ];
