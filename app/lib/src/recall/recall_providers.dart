import 'package:transcript_core/transcript_core.dart';

/// Embeddings from whichever server is already writing the notes.
///
/// Deliberately not a fourth thing to configure. A user who has an Ollama box set up
/// for notes has the same box available for embeddings; asking them to pick a provider
/// and an endpoint again, for a feature they have not tried yet, is how a feature goes
/// unused. Only the model name is asked for, because that is the one thing that
/// genuinely differs — an embedding model is not a chat model.
class EndpointEmbeddingProvider extends EmbeddingProvider {
  EndpointEmbeddingProvider({
    required HttpTransport transport,
    required this.baseUrl,
    required this.model,
    required this.native,
    this.apiKey,
    this.dimensions = 0,
  }) : _transport = transport;

  final HttpTransport _transport;
  final Uri baseUrl;
  final String model;

  /// Whether to use Ollama's own `/api/embed` rather than the OpenAI shape.
  final bool native;

  final String? apiKey;

  @override
  final int dimensions;

  @override
  ProviderId get id => const ProviderId('endpoint-embeddings');

  @override
  String get displayName => 'Embeddings ($model)';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        acceptsAudio: false,
        acceptsText: true,
        nativeJsonSchema: false,
        requiresApiKey: false,
      );

  Map<String, String> get _headers => apiKey == null || apiKey!.isEmpty
      ? const {}
      : {'authorization': 'Bearer $apiKey'};

  /// Embeds one short string, which is the cheapest honest reachability check: a
  /// server that answers /v1/models may still have no embedding model loaded.
  @override
  Future<ConnectionResult> test() async {
    try {
      final vectors = await embed(const ['connection test']);
      final width = vectors.single.length;
      return ConnectionResult.success(
        summary: 'Embeddings ready · $model · $width dimensions',
      );
    } on ProviderException catch (e) {
      return ConnectionResult.failure(
        summary: 'The server would not embed with $model',
        detail: e.message,
        remedy: native
            ? 'Pull an embedding model, for example `ollama pull '
                'nomic-embed-text`, then name it here.'
            : 'Load an embedding model in the server and name it here. A chat '
                'model will not do — it has no embedding endpoint.',
      );
    }
  }

  @override
  Future<List<List<double>>> embed(List<String> texts) => native
      ? ollamaEmbed(_transport, baseUrl, _headers, model, texts)
      : openAiStyleEmbed(
          _transport, baseUrl, _headers, displayName, model, texts);
}
