import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transcript_core/transcript_core.dart';

/// Adapts `dio` to the core package's [HttpTransport] seam.
///
/// The core package deliberately has no HTTP dependency, so every adapter is testable
/// with a fake. This is the one place the real client is wired in, which is also the one
/// place to add logging, retry policy and cancellation.
class DioTransport extends HttpTransport {
  DioTransport({Dio? dio, this.onAudit}) : _dio = dio ?? Dio() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          // Never let a header carrying an API key reach a log sink or crash report.
          e.requestOptions.headers
              .removeWhere((k, _) => _secretHeaders.contains(k));
          handler.next(e);
        },
      ),
    );
  }

  static const _secretHeaders = {
    'x-api-key',
    'authorization',
    'x-goog-api-key'
  };

  final Dio _dio;
  final Future<void> Function(String action, String detail)? onAudit;

  @override
  Future<HttpReply> send(HttpCall call) async {
    try {
      final binaryResponse =
          call.headers.keys.any((key) => key.toLowerCase() == 'range');
      final response = await _dio.requestUri<dynamic>(
        call.url,
        data: call.jsonBody ?? call.bodyBytes,
        options: Options(
          method: call.method,
          headers: {
            ...call.headers,
            if (call.contentType != null) 'content-type': call.contentType,
          },
          responseType:
              binaryResponse ? ResponseType.bytes : ResponseType.plain,
          sendTimeout: call.timeout,
          receiveTimeout: call.timeout,
          // Handled by the adapters, which turn status codes into user-facing advice.
          validateStatus: (_) => true,
        ),
      );

      await _audit(
        'provider_request',
        '${call.method} ${call.url.host}${call.url.path} -> ${response.statusCode ?? 0}',
      );

      return HttpReply(
        response.statusCode ?? 0,
        binaryResponse ? '' : (response.data as String? ?? ''),
        headers: {
          for (final entry in response.headers.map.entries)
            entry.key: entry.value.join(', '),
        },
        bodyBytes: binaryResponse && response.data is List<int>
            ? response.data as List<int>
            : null,
      );
    } on DioException catch (e) {
      await _audit(
        'provider_request_failed',
        '${call.method} ${call.url.host}${call.url.path} -> ${e.type.name}',
      );
      throw TransportException(_classify(e), e.message ?? e.type.name);
    }
  }

  /// Streams the body, and fails only when the far end goes quiet.
  ///
  /// This exists because Dio applies `receiveTimeout` to `request.close()`, which
  /// completes when the response HEADERS arrive — and a non-streaming completion from
  /// a local model sends no headers until the whole thing is generated. A ten-minute
  /// receive timeout therefore became a ten-minute deadline on total generation, and a
  /// CPU-bound server producing grammar-constrained JSON blew straight through it
  /// while working perfectly well.
  ///
  /// With a streamed response the headers arrive at once, so that deadline stops being
  /// a generation limit. Dio then applies no timeout at all to the body, which would
  /// hang forever on a stalled server — so [idleTimeout] is enforced here, on the
  /// decoded stream. That is the honest question anyway: not "is this taking a while"
  /// but "has it stopped".
  @override
  Stream<String> sendStreaming(
    HttpCall call, {
    Duration idleTimeout = const Duration(seconds: 120),
  }) async* {
    Response<ResponseBody> response;
    try {
      response = await _dio.requestUri<ResponseBody>(
        call.url,
        data: call.jsonBody ?? call.bodyBytes,
        options: Options(
          method: call.method,
          headers: {
            ...call.headers,
            if (call.contentType != null) 'content-type': call.contentType,
          },
          responseType: ResponseType.stream,
          sendTimeout: call.timeout,
          // Headers only, now that the body has its own liveness check.
          receiveTimeout: call.timeout,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      await _audit(
        'provider_request_failed',
        '${call.method} ${call.url.host}${call.url.path} -> ${e.type.name}',
      );
      throw TransportException(_classify(e), e.message ?? e.type.name);
    }

    final status = response.statusCode ?? 0;
    await _audit(
      'provider_request',
      '${call.method} ${call.url.host}${call.url.path} -> $status',
    );

    final body = response.data;
    if (body == null) {
      throw const TransportException(
          TransportFailure.other, 'The response had no body.');
    }

    // A refusal still arrives as a stream; read it so the message is the server's
    // own rather than a bare status code.
    if (status < 200 || status >= 300) {
      final text = await utf8.decoder.bind(body.stream).join();
      throw TransportException(TransportFailure.other, 'HTTP $status: $text');
    }

    // Decode across chunk boundaries: a multi-byte character split by TCP would
    // otherwise come out as replacement characters mid-word.
    final decoded = utf8.decoder.bind(body.stream);
    yield* decoded.timeout(
      idleTimeout,
      onTimeout: (sink) {
        sink.addError(TransportException(
          TransportFailure.timeout,
          'The service sent nothing for ${idleTimeout.inSeconds}s and was '
              'assumed to have stopped.',
        ));
        sink.close();
      },
    );
  }

  static TransportFailure _classify(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          TransportFailure.timeout,
        DioExceptionType.badCertificate => TransportFailure.tls,
        DioExceptionType.connectionError => _classifyConnectionError(e),
        _ => TransportFailure.other,
      };

  /// A refused connection and an OS-level block are the same socket error on both
  /// platforms, so the message text is the only signal available.
  static TransportFailure _classifyConnectionError(DioException e) {
    final message = e.message?.toLowerCase() ?? '';
    if (message.contains('refused')) return TransportFailure.refused;
    if (message.contains('failed host lookup') ||
        message.contains('nodename')) {
      return TransportFailure.unresolved;
    }
    return TransportFailure.refused;
  }

  Future<void> _audit(String action, String detail) async {
    if (onAudit != null) {
      await onAudit!(action, detail);
      return;
    }
    try {
      final directory = await getApplicationDocumentsDirectory();
      await File('${directory.path}/provider-audit.log').writeAsString(
        '${DateTime.now().toIso8601String()} [$action] $detail\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // Diagnostics must never make a provider request fail.
    }
  }
}
