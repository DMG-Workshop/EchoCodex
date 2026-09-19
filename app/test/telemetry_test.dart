import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/diagnostics/telemetry.dart';
import 'package:transcript_core/transcript_core.dart';

class _Sink implements DebugSink {
  final List<DebugEntry> entries = [];

  @override
  Future<void> append(List<DebugEntry> batch) async => entries.addAll(batch);

  @override
  Future<void> purgeBefore(DateTime cutoff) async {}

  @override
  Future<List<DebugEntry>> read() async => List.of(entries);

  @override
  Future<void> clear() async => entries.clear();
}

void main() {
  late _Sink sink;
  late DebugLog log;
  late StreamController<QueueEvent> events;
  late DateTime now;
  late int rss;

  setUp(() {
    sink = _Sink();
    now = DateTime.utc(2026, 9, 12, 10);
    rss = 100 * 1024 * 1024;
    log = DebugLog(sink: sink, clock: () => now);
    events = StreamController<QueueEvent>.broadcast();
  });

  tearDown(() async {
    await events.close();
    await log.dispose();
  });

  QueueTelemetry telemetry() => QueueTelemetry(
        log: log,
        clock: () => now,
        residentBytes: () => rss,
      );

  /// Lets the broadcast stream deliver and the log flush.
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await log.flush();
  }

  DebugEntry named(String fragment) =>
      sink.entries.firstWhere((e) => e.message.contains(fragment));

  test('nothing is recorded while debug mode is off', () async {
    final t = telemetry();
    t.watch(events.stream, recordingId: 'r_1');
    events.add(const QueueStarted(0, 1, audioMs: 30000));
    await settle();

    expect(sink.entries, isEmpty,
        reason: 'the subscription is never even made when the log is off');
    await t.dispose();
  });

  test('a chunk being sent records when, how much audio, and memory', () async {
    await log.setEnabled(true);
    final t = telemetry();
    addTearDown(t.dispose);
    t.watch(events.stream, recordingId: 'r_1');

    events.add(const QueueStarted(2, 1, audioMs: 30000));
    await settle();

    final entry = named('chunk 2 sent');
    expect(entry.level, DebugLevel.info);
    expect(entry.fields['audioMs'], 30000);
    expect(entry.fields['attempt'], 1);
    expect(entry.fields['sentAt'], '2026-09-12T10:00:00.000Z');
    expect(entry.fields['rssBefore'], 100 * 1024 * 1024);
  });

  test('a finished chunk records latency against the audio it bought', () async {
    await log.setEnabled(true);
    final t = telemetry();
    addTearDown(t.dispose);
    t.watch(events.stream, recordingId: 'r_1');

    events.add(const QueueStarted(0, 1, audioMs: 30000));
    await settle();
    now = now.add(const Duration(seconds: 45));
    rss += 20 * 1024 * 1024;
    events.add(const QueueSucceeded(0));
    await settle();

    final entry = named('chunk 0 transcribed');
    expect(entry.fields['latencyMs'], 45000);
    expect(entry.fields['realtimeFactor'], '1.50',
        reason: 'above 1.0 means transcription is losing ground to the recording');
    expect(entry.fields['rssDeltaBytes'], 20 * 1024 * 1024,
        reason: 'the trend across chunks is what separates a leak from a load');
  });

  test('a timeout is logged as a timeout, not as a network drop', () async {
    await log.setEnabled(true);
    final t = telemetry();
    addTearDown(t.dispose);
    t.watch(events.stream, recordingId: 'r_1');

    events.add(const QueueStarted(1, 1, audioMs: 30000));
    await settle();
    events.add(QueueRetrying(1, 1, const Duration(seconds: 4),
        cause: TimeoutException('no answer')));
    await settle();

    final entry = named('chunk 1 failed and will be retried');
    expect(entry.level, DebugLevel.warning);
    expect(entry.fields['failure'], 'timeout');
    expect(entry.fields['retryInMs'], 4000);
    expect(entry.fields['latencyMs'], isNotNull,
        reason: 'how long it hung before giving up is the whole question');
  });

  test('a provider refusal carries its status and retry-after', () async {
    await log.setEnabled(true);
    final t = telemetry();
    addTearDown(t.dispose);
    t.watch(events.stream, recordingId: 'r_1');

    events.add(const QueueStarted(0, 2, audioMs: 1000));
    await settle();
    events.add(QueueGaveUp(0, 'rate limited',
        cause: const ProviderException('whisper', 429, 'slow down',
            retryAfter: Duration(seconds: 30))));
    await settle();

    final entry = named('chunk 0 gave up');
    expect(entry.level, DebugLevel.error);
    expect(entry.fields['failure'], 'provider');
    expect(entry.fields['status'], 429);
    expect(entry.fields['retryAfterMs'], 30000);
  });

  test('a chunk reclaimed from a dead process is a warning, with why',
      () async {
    await log.setEnabled(true);
    final t = telemetry();
    addTearDown(t.dispose);
    t.watch(events.stream, recordingId: 'r_1');

    events.add(const QueueReclaimed(3));
    await settle();

    final entry = named('left mid-upload');
    expect(entry.level, DebugLevel.warning);
    expect(entry.fields['chunk'], 3);
  });

  test('switching debug mode off mid-recording stops the log there', () async {
    await log.setEnabled(true);
    final t = telemetry();
    addTearDown(t.dispose);
    t.watch(events.stream, recordingId: 'r_1');

    events.add(const QueueStarted(0, 1, audioMs: 1000));
    await settle();
    final before = sink.entries.length;

    await log.setEnabled(false);
    events.add(const QueueSucceeded(0));
    await settle();

    expect(sink.entries.length, before,
        reason: 'the stream does not know the flag changed — the log does');
  });

  test('a completion with no matching start is still recorded', () async {
    await log.setEnabled(true);
    final t = telemetry();
    addTearDown(t.dispose);
    t.watch(events.stream, recordingId: 'r_1');

    // Debug Mode switched on mid-recording: the start happened before anyone
    // was listening.
    events.add(const QueueSucceeded(7));
    await settle();

    final entry = named('chunk 7 transcribed');
    expect(entry.fields['chunk'], 7);
    expect(entry.fields.containsKey('latencyMs'), isFalse,
        reason: 'a latency nobody measured must not be invented');
  });

  group('the recorder side', () {
    test('a lost microphone is an error that says it was inferred', () async {
      await log.setEnabled(true);
      final recorder = RecorderTelemetry(
        log: log,
        monitor: AudioHealthMonitor(silenceSamplesBeforeWarning: 2),
      );

      recorder.started(sampleRate: 16000, channels: 1, path: '/tmp/a.wav');
      for (var i = 0; i < 6; i++) {
        recorder.observe(AudioSample(
          elapsed: Duration(milliseconds: 100 * (i + 1)),
          amplitudeDb: -160,
          bytesWritten: 3200,
        ));
      }
      await log.flush();

      expect(named('capture started').fields['expectedBytesPerSecond'], 32000);
      final lost = named('the input going away');
      expect(lost.level, DebugLevel.error);
      expect(lost.fields['bytesPerSecond'], 0);
    });

    test('a recorder failure is logged with what it was doing', () async {
      await log.setEnabled(true);
      final recorder = RecorderTelemetry(log: log);

      recorder.failed(StateError('device busy'), StackTrace.current,
          whileDoing: 'starting the capture');
      await log.flush();

      final entry = named('failed while starting the capture');
      expect(entry.level, DebugLevel.error);
      expect(entry.fields['error'], contains('device busy'));
    });

    test('nothing is recorded from the audio path while off', () async {
      final recorder = RecorderTelemetry(log: log);
      recorder.started(sampleRate: 16000, channels: 1);
      recorder.stopped(elapsed: const Duration(minutes: 1), bytes: 1920000);
      await log.flush();

      expect(sink.entries, isEmpty);
    });
  });
}
