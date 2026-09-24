import 'dart:async';

import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

void main() {
  late AudioHealthMonitor monitor;

  setUp(() => monitor = AudioHealthMonitor(silenceSamplesBeforeWarning: 3));

  /// 16kHz mono 16-bit: 32,000 bytes a second, 3,200 per 100ms tick.
  const perTick = 3200;

  /// Feeds [count] ticks at [db], each growing the file by [bytes].
  List<AudioFinding> feed(
    int count, {
    double db = -20,
    int bytes = perTick,
    required int fromTick,
  }) {
    final out = <AudioFinding>[];
    for (var i = 0; i < count; i++) {
      final tick = fromTick + i;
      out.addAll(monitor.observe(AudioSample(
        elapsed: Duration(milliseconds: 100 * (tick + 1)),
        amplitudeDb: db,
        bytesWritten: perTick * (tick + 1) - (perTick - bytes) * (i + 1),
      )));
    }
    return out;
  }

  test('the expected rate comes from the format that was asked for', () {
    expect(monitor.expectedBytesPerSecond, 32000);
    expect(
      AudioHealthMonitor(sampleRate: 44100, channels: 2).expectedBytesPerSecond,
      176400,
    );
  });

  test('a healthy capture reports nothing at all', () {
    final findings = feed(20, fromTick: 0);
    expect(findings, isEmpty,
        reason: 'a monitor that cries wolf is a monitor nobody reads');
  });

  test('a pause between sentences is not silence', () {
    final findings = feed(2, db: -160, fromTick: 0);
    expect(findings, isEmpty);
  });

  test('a sustained floor reading is reported once, not every tick', () {
    final findings = <AudioFinding>[];
    for (var i = 0; i < 20; i++) {
      findings.addAll(monitor.observe(AudioSample(
        elapsed: Duration(milliseconds: 100 * (i + 1)),
        amplitudeDb: -160,
        bytesWritten: perTick * (i + 1),
      )));
    }

    expect(findings.where((f) => f == AudioFinding.silence), hasLength(1),
        reason:
            'repeating "still silent" 20 times buries the line that matters');
  });

  test('silence with the file still growing is only suspicious', () {
    final findings = <AudioFinding>[];
    for (var i = 0; i < 10; i++) {
      findings.addAll(monitor.observe(AudioSample(
        elapsed: Duration(milliseconds: 100 * (i + 1)),
        amplitudeDb: -160,
        bytesWritten: perTick * (i + 1),
      )));
    }

    expect(findings, contains(AudioFinding.silence));
    expect(findings, isNot(contains(AudioFinding.microphoneLost)),
        reason: 'a muted mic still writes zero-valued samples at full rate');
  });

  test('silence with the file no longer growing is a lost microphone', () {
    final findings = <AudioFinding>[];
    for (var i = 0; i < 10; i++) {
      findings.addAll(monitor.observe(AudioSample(
        elapsed: Duration(milliseconds: 100 * (i + 1)),
        amplitudeDb: -160,
        // Frozen: the stream stopped producing bytes altogether.
        bytesWritten: perTick,
      )));
    }

    expect(findings, contains(AudioFinding.microphoneLost));
    expect(
        findings.where((f) => f == AudioFinding.microphoneLost), hasLength(1));
  });

  test('sound returning re-arms the warnings', () {
    for (var i = 0; i < 10; i++) {
      monitor.observe(AudioSample(
        elapsed: Duration(milliseconds: 100 * (i + 1)),
        amplitudeDb: -160,
        bytesWritten: perTick,
      ));
    }

    // Someone speaks again, then it goes quiet a second time.
    monitor.observe(AudioSample(
      elapsed: const Duration(milliseconds: 1100),
      amplitudeDb: -20,
      bytesWritten: perTick * 11,
    ));
    final second = <AudioFinding>[];
    for (var i = 11; i < 20; i++) {
      second.addAll(monitor.observe(AudioSample(
        elapsed: Duration(milliseconds: 100 * (i + 1)),
        amplitudeDb: -160,
        bytesWritten: perTick * 11,
      )));
    }

    expect(second, contains(AudioFinding.microphoneLost),
        reason: 'a second failure is news, not a duplicate');
  });

  group('the byte rate against the clock', () {
    test('a short deficit that recovers is dropped buffers', () {
      final findings = <AudioFinding>[];
      var bytes = 0;
      for (var i = 0; i < 10; i++) {
        // Two lean ticks in the middle, then back to full rate.
        bytes += (i == 4 || i == 5) ? 800 : perTick;
        findings.addAll(monitor.observe(AudioSample(
          elapsed: Duration(milliseconds: 100 * (i + 1)),
          amplitudeDb: -20,
          bytesWritten: bytes,
        )));
      }

      expect(findings, contains(AudioFinding.bufferOverrun));
      expect(findings, isNot(contains(AudioFinding.sampleRateDrop)));
    });

    test('a deficit that never recovers is a rate that changed', () {
      final findings = <AudioFinding>[];
      var bytes = 0;
      for (var i = 0; i < 10; i++) {
        // Half rate for good: 8kHz where 16kHz was asked for.
        bytes += perTick ~/ 2;
        findings.addAll(monitor.observe(AudioSample(
          elapsed: Duration(milliseconds: 100 * (i + 1)),
          amplitudeDb: -20,
          bytesWritten: bytes,
        )));
      }

      expect(findings, contains(AudioFinding.sampleRateDrop));
      expect(
          findings.where((f) => f == AudioFinding.sampleRateDrop), hasLength(1),
          reason: 'one line per episode, not per tick');
    });

    test('a rate that comes back says so, to bound the damage', () {
      final findings = <AudioFinding>[];
      var bytes = 0;
      for (var i = 0; i < 12; i++) {
        bytes += i < 6 ? perTick ~/ 2 : perTick;
        findings.addAll(monitor.observe(AudioSample(
          elapsed: Duration(milliseconds: 100 * (i + 1)),
          amplitudeDb: -20,
          bytesWritten: bytes,
        )));
      }

      expect(findings, contains(AudioFinding.sampleRateDrop));
      expect(findings, contains(AudioFinding.recovered),
          reason:
              'otherwise the reader assumes the rest of the file is suspect');
    });

    test('a little slack does not read as a fault', () {
      final findings = <AudioFinding>[];
      var bytes = 0;
      for (var i = 0; i < 10; i++) {
        // 95% of nominal: sampling jitter, not a fault.
        bytes += (perTick * 0.95).round();
        findings.addAll(monitor.observe(AudioSample(
          elapsed: Duration(milliseconds: 100 * (i + 1)),
          amplitudeDb: -20,
          bytesWritten: bytes,
        )));
      }

      expect(findings, isEmpty);
    });

    test('the first sample establishes a baseline and reports nothing', () {
      final findings = monitor.observe(const AudioSample(
        elapsed: Duration(milliseconds: 100),
        amplitudeDb: -20,
        bytesWritten: 0,
      ));
      expect(findings, isEmpty,
          reason:
              'a rate needs two points; one would divide by the whole recording');
    });

    test('two samples at the same instant are ignored, never divided by zero',
        () {
      monitor.observe(const AudioSample(
          elapsed: Duration(milliseconds: 100),
          amplitudeDb: -20,
          bytesWritten: perTick));
      expect(
        () => monitor.observe(const AudioSample(
            elapsed: Duration(milliseconds: 100),
            amplitudeDb: -20,
            bytesWritten: perTick)),
        returnsNormally,
      );
    });
  });

  test('reset forgets one session so it cannot leak into the next', () {
    for (var i = 0; i < 10; i++) {
      monitor.observe(AudioSample(
        elapsed: Duration(milliseconds: 100 * (i + 1)),
        amplitudeDb: -160,
        bytesWritten: perTick,
      ));
    }

    monitor.reset();
    expect(monitor.lastBytesPerSecond, isNull);
    expect(
      monitor.observe(const AudioSample(
          elapsed: Duration(milliseconds: 100),
          amplitudeDb: -160,
          bytesWritten: 0)),
      isEmpty,
      reason: 'the run counter starts again with the recording',
    );
  });

  group('classifying what went wrong', () {
    test('a timeout is not a network drop', () {
      expect(classifyFailure(TimeoutException('slow')), FailureKind.timeout);
    });

    test('a provider refusal carries its status', () {
      const error = ProviderException('whisper', 429, 'rate limited');
      expect(classifyFailure(error), FailureKind.provider);
      expect(failureFields(error)['status'], 429);
      expect(failureFields(error)['provider'], 'whisper');
    });

    test('a transport this package has never heard of still classifies', () {
      expect(classifyFailure(_FakeSocketException()), FailureKind.network);
      expect(classifyFailure(_FakeDioException('connection timeout')),
          FailureKind.timeout);
      expect(classifyFailure(_FakeDioException('connection refused')),
          FailureKind.network);
    });

    test('running out of memory is its own kind', () {
      expect(classifyFailure(_FakeOom()), FailureKind.outOfMemory);
    });

    test('an unrecognised failure says so rather than guessing', () {
      expect(
          classifyFailure(StateError('something else')), FailureKind.unknown);
      expect(classifyFailure(null), FailureKind.unknown);
      expect(failureFields(StateError('x'))['errorType'], 'StateError');
    });
  });
}

class _FakeSocketException implements Exception {
  @override
  Type get runtimeType => SocketException;
}

class SocketException {}

class _FakeDioException implements Exception {
  _FakeDioException(this.message);
  final String message;

  @override
  Type get runtimeType => DioException;

  @override
  String toString() => 'DioException: $message';
}

class DioException {}

class _FakeOom implements Exception {
  @override
  String toString() => 'Out of Memory';
}
