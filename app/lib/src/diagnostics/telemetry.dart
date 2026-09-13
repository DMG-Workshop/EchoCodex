import 'dart:async';
import 'dart:io';

import 'package:transcript_core/transcript_core.dart';

/// Turns the transcription queue's own event stream into diagnostic lines.
///
/// ## Why this is a subscriber and not a set of log calls in the pipeline
///
/// [ChunkQueue] already emits a structured event for every transition it makes. Putting
/// log statements inside it would mean `transcript_core` — the package that analyses in
/// seconds with no Flutter toolchain, no filesystem and no network — growing a
/// dependency on a logger, a clock and somewhere to write. Subscribing instead keeps all
/// of that on this side of the line, and costs nothing: when Debug Mode is off, nothing
/// subscribes at all.
///
/// ## What it measures
///
/// Latency is timed here rather than reported by the queue, because the question worth
/// answering is "how long did the user wait", which is wall-clock from the moment the
/// chunk was claimed. Against it sits [QueueStarted.audioMs], the amount of audio that
/// bought: a realtime factor above 1.0 means transcription is falling behind the
/// recording, which is the number that predicts a backlog.
///
/// Memory is sampled either side of each chunk. A single reading says little; the
/// *trend* across chunks is what distinguishes a leak from a large model that loaded
/// once. It is also the only evidence that survives a real out-of-memory kill, which
/// takes the process down with no Dart frame to catch — see [FailureKind.outOfMemory].
class QueueTelemetry {
  QueueTelemetry({
    required this.log,
    DateTime Function()? clock,
    int Function()? residentBytes,
  })  : _now = clock ?? DateTime.now,
        _rss = residentBytes ?? _currentRss;

  final DebugLog log;
  final DateTime Function() _now;
  final int Function() _rss;

  final Map<int, _InFlight> _started = {};
  StreamSubscription<QueueEvent>? _subscription;

  /// Starts recording [events] for [recordingId].
  ///
  /// Returns immediately and does nothing at all when the log is off, so the caller can
  /// wire this up unconditionally rather than duplicating the flag check at every site.
  void watch(Stream<QueueEvent> events, {required String recordingId}) {
    if (!log.isOn) return;
    _subscription?.cancel();
    _started.clear();
    log.info('queue', () => 'watching the transcription queue',
        fields: () => {'recording': recordingId, 'rssBytes': _rss()});
    _subscription = events.listen(
      _onEvent,
      onError: (Object e, StackTrace s) => log.error(
        'queue',
        () => 'the queue event stream failed',
        error: e,
        stack: s,
      ),
    );
  }

  void _onEvent(QueueEvent event) {
    // Cheap re-check: Debug Mode can be switched off mid-recording, and the stream does
    // not know that.
    if (!log.isOn) return;
    try {
      switch (event) {
        case QueueStarted(:final index, :final attempt, :final audioMs):
          _started[index] = _InFlight(at: _now(), rss: _rss(), audioMs: audioMs);
          log.info('queue', () => 'chunk $index sent',
              fields: () => {
                    'chunk': index,
                    'attempt': attempt,
                    if (audioMs != null) 'audioMs': audioMs,
                    'sentAt': _now().toUtc().toIso8601String(),
                    'rssBefore': _rss(),
                  });

        case QueueSucceeded(:final index):
          final started = _started.remove(index);
          log.info('queue', () => 'chunk $index transcribed',
              fields: () => _completionFields(index, started));

        case QueueRetrying(:final index, :final attempt, :final delay, :final cause):
          final started = _started.remove(index);
          log.warning('queue', () => 'chunk $index failed and will be retried',
              fields: () => {
                    ..._completionFields(index, started),
                    'attempt': attempt,
                    'retryInMs': delay.inMilliseconds,
                    ...failureFields(cause),
                  });

        case QueueGaveUp(:final index, :final reason, :final cause):
          final started = _started.remove(index);
          log.error('queue', () => 'chunk $index gave up and became a gap',
              error: reason,
              fields: () => {
                    ..._completionFields(index, started),
                    ...failureFields(cause),
                  });

        case QueueWaiting(:final delay):
          log.info('queue', () => 'every chunk is waiting on backoff',
              fields: () => {'waitMs': delay.inMilliseconds});

        case QueueReclaimed(:final index):
          log.warning(
              'queue',
              () => 'chunk $index was left mid-upload by a process that died, '
                  'and has been requeued',
              fields: () => {'chunk': index});
      }
    } catch (e, s) {
      // Telemetry must never be the thing that breaks the pipeline it is watching.
      log.error('queue', () => 'a telemetry handler threw', error: e, stack: s);
    }
  }

  Map<String, Object?> _completionFields(int index, _InFlight? started) {
    final rss = _rss();
    if (started == null) {
      return {'chunk': index, 'rssAfter': rss};
    }
    final latency = _now().difference(started.at);
    final audioMs = started.audioMs;
    return {
      'chunk': index,
      'latencyMs': latency.inMilliseconds,
      if (audioMs != null) ...{
        'audioMs': audioMs,
        // Above 1.0, transcription is slower than the audio arrives — the number that
        // predicts a backlog rather than describing one.
        'realtimeFactor': audioMs == 0
            ? null
            : (latency.inMilliseconds / audioMs).toStringAsFixed(2),
      },
      'rssBefore': started.rss,
      'rssAfter': rss,
      'rssDeltaBytes': rss - started.rss,
    };
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started.clear();
  }

  /// Resident set size, or 0 where the platform will not say.
  ///
  /// Read through a function so a test can supply a rising sequence and assert on the
  /// delta rather than on whatever this machine happens to be using.
  static int _currentRss() {
    try {
      return ProcessInfo.currentRss;
    } on UnsupportedError {
      return 0;
    }
  }
}

class _InFlight {
  const _InFlight({required this.at, required this.rss, required this.audioMs});
  final DateTime at;
  final int rss;
  final int? audioMs;
}

/// Logs what [AudioHealthMonitor] finds, and nothing else.
///
/// The monitor is pure and the thresholds are tested; this is only the translation into
/// log lines. Each finding is phrased to say what was observed *and* that it was
/// inferred, because a reader who believes the OS reported a sample-rate drop will stop
/// looking for the real cause.
class RecorderTelemetry {
  RecorderTelemetry({required this.log, AudioHealthMonitor? monitor})
      : monitor = monitor ?? AudioHealthMonitor();

  final DebugLog log;
  final AudioHealthMonitor monitor;

  void started({required int sampleRate, required int channels, String? path}) {
    monitor.reset();
    log.info('audio', () => 'capture started',
        fields: () => {
              'sampleRate': sampleRate,
              'channels': channels,
              'expectedBytesPerSecond': monitor.expectedBytesPerSecond,
              if (path != null) 'path': path,
            });
  }

  /// Feeds one observation. Call sites guard on [DebugLog.isOn] before building the
  /// sample, because this runs on the amplitude tick.
  void observe(AudioSample sample) {
    for (final finding in monitor.observe(sample)) {
      switch (finding) {
        case AudioFinding.silence:
          log.warning(
              'audio',
              () => 'nothing but the noise floor for a sustained stretch — the room '
                  'may simply be quiet, but the microphone may also be muted',
              fields: () => _fields(sample));

        case AudioFinding.microphoneLost:
          log.error(
              'audio',
              () => 'the capture has gone silent AND stopped producing bytes, which a '
                  'muted microphone does not do: treat this as the input going away '
                  'mid-recording',
              fields: () => _fields(sample));

        case AudioFinding.bufferOverrun:
          log.warning(
              'audio',
              () => 'the file fell behind the clock briefly and caught up again — '
                  'inferred dropped capture buffers, not a reported one',
              fields: () => _fields(sample));

        case AudioFinding.sampleRateDrop:
          log.error(
              'audio',
              () => 'the file has been growing too slowly to be the format that was '
                  'requested — inferred from bytes against wall clock, not reported '
                  'by the platform',
              fields: () => _fields(sample));

        case AudioFinding.recovered:
          log.info('audio', () => 'the capture rate is back to nominal',
              fields: () => _fields(sample));
      }
    }
  }

  void stopped({required Duration elapsed, required int bytes}) {
    log.info('audio', () => 'capture stopped',
        fields: () => {
              'elapsedMs': elapsed.inMilliseconds,
              'bytes': bytes,
              'averageBytesPerSecond': elapsed.inMilliseconds == 0
                  ? null
                  : (bytes * 1000 / elapsed.inMilliseconds).round(),
            });
  }

  void failed(Object error, StackTrace stack, {String? whileDoing}) => log.error(
        'audio',
        () => whileDoing == null
            ? 'the recorder failed'
            : 'the recorder failed while $whileDoing',
        error: error,
        stack: stack,
      );

  Map<String, Object?> _fields(AudioSample sample) => {
        'elapsedMs': sample.elapsed.inMilliseconds,
        'db': sample.amplitudeDb,
        'bytes': sample.bytesWritten,
        'bytesPerSecond': monitor.lastBytesPerSecond?.round(),
        'expectedBytesPerSecond': monitor.expectedBytesPerSecond,
      };
}
