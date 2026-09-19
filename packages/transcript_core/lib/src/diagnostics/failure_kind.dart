import 'dart:async';

import '../providers/errors.dart';

/// What went wrong, in the terms someone debugging actually thinks in.
///
/// The point of naming these is triage. "Request failed" tells the reader nothing they
/// can act on; "the network went away nine seconds in" and "the provider answered 429"
/// lead to completely different fixes, and a log that cannot tell them apart makes the
/// reader re-run the failure to find out.
enum FailureKind {
  /// The request was still open when the client gave up. The provider may well have
  /// completed it — which is why the chunk queue treats a timed-out chunk as unknown
  /// rather than failed.
  timeout,

  /// The connection could not be made or was cut. Distinct from [timeout]: nothing was
  /// waiting on a slow answer, the path itself was gone.
  network,

  /// The provider answered, and the answer was a refusal. [ProviderException.statusCode]
  /// is the detail that matters.
  provider,

  /// The process ran out of memory.
  ///
  /// Worth its own kind, and worth being honest about: a Dart-side `OutOfMemoryError`
  /// is sometimes catchable, but a native allocation failure kills the process with no
  /// Dart frame at all. When that happens this value never gets recorded — the evidence
  /// is the RSS trend in the lines *before* the log stops. That is exactly why memory is
  /// sampled per chunk rather than only reported on failure.
  outOfMemory,

  /// Anything else. Not a bucket to be ashamed of: an honest `unknown` with the type
  /// name attached beats a confident misclassification.
  unknown;
}

/// Classifies [error] for the log.
///
/// Deliberately matches on runtime type *names* for the transport cases rather than
/// importing `dart:io` or any HTTP client. Requests here travel through whatever
/// transport the app supplies — `dart:io` sockets on mobile and desktop, a Dio
/// interceptor, a mocked client in tests — and each raises its own type for the same
/// underlying event. Matching names keeps this package free of a transport dependency
/// and correctly classifies clients it has never heard of.
FailureKind classifyFailure(Object? error) {
  if (error == null) return FailureKind.unknown;
  if (error is TimeoutException) return FailureKind.timeout;
  if (error is ProviderException) return FailureKind.provider;
  if (error is OutOfMemoryError) return FailureKind.outOfMemory;

  final name = error.runtimeType.toString();
  if (name.contains('Timeout')) return FailureKind.timeout;
  if (name == 'SocketException' ||
      name == 'HandshakeException' ||
      name == 'HttpException' ||
      name == 'ClientException' ||
      name == 'WebSocketException') {
    return FailureKind.network;
  }

  // Dio funnels every transport failure through one type and distinguishes them by a
  // `type` field, so the name alone is not enough; its message carries the distinction.
  final text = error.toString().toLowerCase();
  if (name == 'DioException' || name.startsWith('Dio')) {
    if (text.contains('timeout')) return FailureKind.timeout;
    return FailureKind.network;
  }

  if (text.contains('out of memory') || text.contains('cannot allocate')) {
    return FailureKind.outOfMemory;
  }
  return FailureKind.unknown;
}

/// The fields every failure contributes to a log line.
///
/// One shape for every failure, so a reader scanning a long log compares like with
/// like instead of re-learning the format at each error.
Map<String, Object?> failureFields(Object? error) => {
      'failure': classifyFailure(error).name,
      'errorType': error == null ? 'none' : error.runtimeType.toString(),
      if (error is ProviderException) ...{
        'provider': error.provider,
        'status': error.statusCode,
        if (error.retryAfter != null)
          'retryAfterMs': error.retryAfter!.inMilliseconds,
      },
    };
