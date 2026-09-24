import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

/// A minimal HTTP seam.
///
/// The core package has no runtime dependencies, so adapters never import a client
/// directly. The Flutter app injects a `dio`-backed transport (for interceptors, cancel
/// tokens and per-provider retry policy); tests inject [RecordingTransport] and assert on
/// the exact bytes each adapter puts on the wire, with no network involved.
abstract class HttpTransport {
  Future<HttpReply> send(HttpCall call);

  /// Sends [call] and yields the response body as it arrives.
  ///
  /// Exists for one specific reason: a non-streaming completion from a local model
  /// sends no bytes at all until the whole thing is generated, so any deadline on the
  /// response becomes a deadline on total generation time. On a CPU-bound server
  /// producing grammar-constrained JSON that is minutes, and the request dies with a
  /// timeout while the model is working perfectly well.
  ///
  /// Streaming turns that into a liveness question instead: bytes arrive continuously,
  /// so the only thing worth failing on is the model going quiet. [idleTimeout] is that
  /// check, and it has to live here because no HTTP client applies one to a body
  /// stream — they time the headers and then wait forever.
  ///
  /// Default implementation falls back to [send] and yields the body in one piece, so
  /// a transport that cannot stream still works and simply keeps the old behaviour.
  Stream<String> sendStreaming(
    HttpCall call, {
    Duration idleTimeout = const Duration(seconds: 120),
  }) async* {
    final reply = await send(call);
    if (!reply.ok) {
      throw TransportException(
        TransportFailure.other,
        'HTTP ${reply.statusCode}: ${reply.body}',
      );
    }
    yield reply.body;
  }
}

/// Reassembles an OpenAI-style `text/event-stream` into the text it carries.
///
/// Tolerant on purpose. Chunk boundaries fall wherever TCP puts them, so a `data:`
/// line routinely arrives in two pieces, and servers differ on whether they send
/// `[DONE]`, keep-alive comments, or blank lines between events. Anything unparseable
/// is skipped rather than thrown: losing one malformed frame costs a few tokens, while
/// throwing loses a generation that may have taken minutes.
class SseAccumulator {
  final StringBuffer _pending = StringBuffer();

  /// Feeds a raw chunk and returns whatever complete text it completed.
  String add(String chunk) {
    _pending.write(chunk);
    final buffered = _pending.toString();

    // Keep the trailing partial line for the next chunk.
    final lastBreak = buffered.lastIndexOf('\n');
    if (lastBreak == -1) return '';
    final ready = buffered.substring(0, lastBreak);
    _pending
      ..clear()
      ..write(buffered.substring(lastBreak + 1));

    final out = StringBuffer();
    for (final line in ready.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      out.write(_textOf(payload));
    }
    return out.toString();
  }

  /// Whatever is left once the stream ends.
  String flush() {
    final rest = _pending.toString().trim();
    _pending.clear();
    if (!rest.startsWith('data:')) return '';
    final payload = rest.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return '';
    return _textOf(payload);
  }

  static String _textOf(String payload) {
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return '';
    }
    if (decoded is! Map) return '';

    // Chat completions put it under choices[].delta.content; the older completions
    // shape uses choices[].text; Ollama's native stream uses message.content.
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final delta = first['delta'];
        if (delta is Map && delta['content'] is String) {
          return delta['content'] as String;
        }
        if (first['text'] is String) return first['text'] as String;
      }
    }
    final message = decoded['message'];
    if (message is Map && message['content'] is String) {
      return message['content'] as String;
    }
    if (decoded['response'] is String) return decoded['response'] as String;
    return '';
  }
}

class HttpCall {
  const HttpCall({
    required this.method,
    required this.url,
    this.headers = const {},
    this.jsonBody,
    this.bodyBytes,
    this.contentType,
    this.timeout = const Duration(seconds: 60),
  }) : assert(jsonBody == null || bodyBytes == null,
            'Set jsonBody or bodyBytes, not both.');

  final String method;
  final Uri url;
  final Map<String, String> headers;

  /// Encoded as JSON with `content-type: application/json`.
  final Object? jsonBody;

  /// Pre-encoded body, for multipart audio uploads. Requires [contentType].
  final List<int>? bodyBytes;
  final String? contentType;

  final Duration timeout;

  HttpCall copyWith({Duration? timeout}) => HttpCall(
        method: method,
        url: url,
        headers: headers,
        jsonBody: jsonBody,
        bodyBytes: bodyBytes,
        contentType: contentType,
        timeout: timeout ?? this.timeout,
      );

  /// The decoded JSON body, for tests asserting on request shape.
  Map<String, dynamic> get jsonBodyMap => jsonBody as Map<String, dynamic>;
}

class HttpReply {
  const HttpReply(
    this.statusCode,
    this.body, {
    this.headers = const {},
    this.bodyBytes,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  /// Raw bytes of the response, populated for binary responses such as a model download.
  /// JSON adapters ignore it and read [body]; the transport fills it only when asked.
  final List<int>? bodyBytes;

  bool get ok => statusCode >= 200 && statusCode < 300;

  /// Decoded body, or null when the response was not JSON. Providers return HTML error
  /// pages more often than their docs admit — a reverse proxy in front of a local model
  /// server is a common cause — so this never throws.
  Map<String, dynamic>? get json {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

/// Raised for transport-level failures, before any HTTP status exists.
class TransportException implements Exception {
  const TransportException(this.kind, this.message);

  final TransportFailure kind;
  final String message;

  @override
  String toString() => 'TransportException($kind): $message';
}

enum TransportFailure {
  /// Nothing accepted the connection. For a LAN endpoint this usually means the model
  /// server is not running, is bound to localhost only, or the device is on another network.
  refused,

  /// DNS or hostname resolution failed.
  unresolved,

  /// The request exceeded its timeout. Local models legitimately take 20-60s for a first
  /// token on a cold model — this is why local timeouts are generous.
  timeout,

  /// TLS negotiation failed, typically a self-signed certificate on a LAN endpoint.
  tls,

  /// Anything else, including the platform blocking the request outright. On iOS a
  /// missing NSLocalNetworkUsageDescription and on Android a missing cleartext exception
  /// both surface here, which is why the message is preserved verbatim.
  other,
}

/// Default `dart:io` transport. Used by tests and the CLI; the app supplies its own.
class IoHttpTransport extends HttpTransport {
  IoHttpTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<HttpReply> send(HttpCall call) async {
    try {
      final request =
          await _client.openUrl(call.method, call.url).timeout(call.timeout);

      call.headers.forEach(request.headers.set);
      if (call.jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(call.jsonBody));
      } else if (call.bodyBytes != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, call.contentType!);
        request.add(call.bodyBytes!);
      }

      final response = await request.close().timeout(call.timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(call.timeout);

      final headers = <String, String>{};
      response.headers.forEach((k, v) => headers[k] = v.join(', '));
      return HttpReply(response.statusCode, body, headers: headers);
    } on TimeoutException {
      throw TransportException(
        TransportFailure.timeout,
        'No response within ${call.timeout.inSeconds}s.',
      );
    } on SocketException catch (e) {
      final failure =
          e.osError?.errorCode == 111 || e.message.contains('refused')
              ? TransportFailure.refused
              : e.message.contains('Failed host lookup')
                  ? TransportFailure.unresolved
                  : TransportFailure.other;
      throw TransportException(failure, e.message);
    } on HandshakeException catch (e) {
      throw TransportException(TransportFailure.tls, e.message);
    }
  }

  void close() => _client.close(force: true);
}

/// Test double. Records every call and replays queued replies in order.
class RecordingTransport extends HttpTransport {
  RecordingTransport(this._replies);

  /// Convenience for the common single-reply case.
  RecordingTransport.single(HttpReply reply) : _replies = [reply];

  final List<Object> _replies;
  final List<HttpCall> calls = [];

  HttpCall get lastCall => calls.last;

  @override
  Future<HttpReply> send(HttpCall call) async {
    calls.add(call);
    if (_replies.isEmpty) {
      throw StateError(
          'RecordingTransport ran out of replies on call ${calls.length}');
    }
    final next = _replies.removeAt(0);
    if (next is TransportException) throw next;
    return next as HttpReply;
  }
}

/// Builds a `multipart/form-data` body. Needed only for OpenAI's audio endpoints; every
/// other call in the app is JSON.
class MultipartBody {
  MultipartBody()
      : boundary = 'transcript-${DateTime.now().microsecondsSinceEpoch}';

  final String boundary;
  final BytesBuilder _out = BytesBuilder();

  String get contentType => 'multipart/form-data; boundary=$boundary';

  void addField(String name, String value) {
    _out
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('content-disposition: form-data; name="$name"\r\n\r\n'))
      ..add(utf8.encode(value))
      ..add(utf8.encode('\r\n'));
  }

  void addFile(String name, String filename, List<int> bytes, String mimeType) {
    _out
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode(
          'content-disposition: form-data; name="$name"; filename="$filename"\r\n'))
      ..add(utf8.encode('content-type: $mimeType\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n'));
  }

  List<int> finish() {
    final copy = BytesBuilder()
      ..add(_out.toBytes())
      ..add(utf8.encode('--$boundary--\r\n'));
    return copy.takeBytes();
  }
}

/// Answers by URL rather than by call order.
///
/// [RecordingTransport] replays a queue, which cannot express "these ten probes go out
/// at once and three of them answer". Discovery needs exactly that, so this fake matches
/// on a substring of the request URL and lets everything else fail as unreachable.
class RoutingTransport extends HttpTransport {
  RoutingTransport(this.routes, {this.latency = Duration.zero});

  /// URL substring -> reply. First match wins, so put the more specific route first.
  final Map<String, HttpReply> routes;

  /// Simulated round-trip time, so concurrency and timeouts are observable.
  final Duration latency;

  final List<HttpCall> calls = [];

  @override
  Future<HttpReply> send(HttpCall call) async {
    calls.add(call);
    if (latency > Duration.zero) await Future<void>.delayed(latency);

    for (final entry in routes.entries) {
      if (call.url.toString().contains(entry.key)) return entry.value;
    }
    throw const TransportException(
      TransportFailure.refused,
      'Connection refused',
    );
  }
}
