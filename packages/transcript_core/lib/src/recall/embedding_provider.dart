import '../providers/errors.dart';
import '../providers/http_transport.dart';
import '../providers/provider.dart';

/// Turns text into vectors, so passages can be found by meaning rather than by word.
///
/// A third provider slot beside transcription and structuring, and for the same reason
/// those are two rather than one: the model that writes a note is rarely the model that
/// embeds well, and a user running Ollama typically pulls a dedicated embedding model
/// alongside their chat model.
abstract class EmbeddingProvider extends AiProvider {
  /// Vectors for [texts], in the same order.
  ///
  /// Batched because embedding is per-call overhead dominated: a hundred passages in
  /// one request is a fraction of the cost of a hundred requests, and indexing a
  /// recording is exactly that shape.
  Future<List<List<double>>> embed(List<String> texts);

  /// Width of the vectors this provider returns. Vectors of different widths cannot be
  /// compared, so a change here invalidates the whole index — the caller stores it
  /// alongside them so it can notice.
  int get dimensions;
}

/// `POST /v1/embeddings` — the OpenAI shape, which LM Studio and llama.cpp also serve.
Future<List<List<double>>> openAiStyleEmbed(
  HttpTransport transport,
  Uri baseUrl,
  Map<String, String> headers,
  String providerName,
  String model,
  List<String> texts, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  if (texts.isEmpty) return const [];

  final reply = await transport.send(HttpCall(
    method: 'POST',
    url: baseUrl.resolve('/v1/embeddings'),
    headers: {'content-type': 'application/json', ...headers},
    jsonBody: {'model': model, 'input': texts},
    timeout: timeout,
  ));

  if (!reply.ok) {
    throw ProviderException(
      providerName,
      reply.statusCode,
      'The embedding request was refused.',
    );
  }

  final data = reply.json?['data'];
  if (data is! List) {
    throw ProviderException(
      providerName,
      reply.statusCode,
      'The embedding response had no data array.',
    );
  }

  // Order matters and the API does not promise it, so honour `index` where it is
  // given: a silently reordered batch mislabels every passage in it, and nothing
  // downstream could ever detect that.
  final out =
      List<List<double>>.filled(texts.length, const [], growable: false);
  var fallback = 0;
  for (final entry in data) {
    if (entry is! Map) continue;
    final vector = _vectorOf(entry['embedding']);
    if (vector == null) continue;
    final index = entry['index'];
    final at =
        index is int && index >= 0 && index < texts.length ? index : fallback;
    out[at] = vector;
    fallback++;
  }

  if (out.any((v) => v.isEmpty)) {
    throw ProviderException(
      providerName,
      reply.statusCode,
      'The embedding response was missing a vector for '
      '${out.where((v) => v.isEmpty).length} of ${texts.length} passages.',
    );
  }
  return out;
}

/// `POST /api/embed` — Ollama's own endpoint.
///
/// Worth having rather than relying on Ollama's OpenAI-compatible route: the native
/// endpoint is present on every version, batches in one call, and is what an Ollama
/// user's own tooling already targets.
Future<List<List<double>>> ollamaEmbed(
  HttpTransport transport,
  Uri baseUrl,
  Map<String, String> headers,
  String model,
  List<String> texts, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  if (texts.isEmpty) return const [];

  final reply = await transport.send(HttpCall(
    method: 'POST',
    url: baseUrl.resolve('/api/embed'),
    headers: {'content-type': 'application/json', ...headers},
    jsonBody: {'model': model, 'input': texts},
    timeout: timeout,
  ));

  if (!reply.ok) {
    throw ProviderException(
      'Ollama',
      reply.statusCode,
      'The embedding request was refused. Pull an embedding model first, for '
          'example `ollama pull nomic-embed-text`.',
    );
  }

  final embeddings = reply.json?['embeddings'];
  if (embeddings is! List || embeddings.length != texts.length) {
    throw ProviderException(
      'Ollama',
      reply.statusCode,
      'Expected ${texts.length} vectors back and got '
          '${embeddings is List ? embeddings.length : 0}.',
    );
  }

  final out = <List<double>>[];
  for (final entry in embeddings) {
    final vector = _vectorOf(entry);
    if (vector == null) {
      throw ProviderException(
          'Ollama', reply.statusCode, 'A vector was unreadable.');
    }
    out.add(vector);
  }
  return out;
}

List<double>? _vectorOf(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final out = <double>[];
  for (final value in raw) {
    if (value is num) {
      out.add(value.toDouble());
    } else {
      return null;
    }
  }
  return out;
}
