import 'dart:async';
import 'dart:convert';

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
  group('structuring', structuringTests);

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

/// A local server small enough to break on, and honest about it: a prompt past the
/// context comes back as nothing usable, which is exactly what one does.
class _SmallServer extends StructuringProvider {
  _SmallServer({
    this.contextWindowTokens = 8192,
    this.maxOutputTokens = 2048,
    this.reports,
  });

  final int contextWindowTokens;
  final int maxOutputTokens;

  /// What it admits to, when that differs from what it has. Null means it tells the
  /// truth; 0 is the server that will not say, which is most of them.
  final int? reports;
  var _sections = 0;

  @override
  ProviderId get id => const ProviderId('small');
  @override
  String get displayName => 'Small';
  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
        acceptsAudio: false,
        acceptsText: true,
        nativeJsonSchema: true,
        contextWindowTokens: reports ?? contextWindowTokens,
        maxOutputTokens: maxOutputTokens,
      );
  @override
  Future<ConnectionResult> test() async =>
      ConnectionResult.success(summary: 'ok');

  @override
  Future<StructureResponse> structure(StructureRequest request) async {
    var characters = request.systemPrompt.length + request.userContent.length;
    for (final turn in request.priorTurns) {
      characters += turn.content.length;
    }
    final tokens = (characters / 3.5).ceil() +
        (jsonEncode(request.schema).length / 3.5).ceil();
    if (tokens + maxOutputTokens > contextWindowTokens) {
      return const StructureResponse(rawText: '');
    }
    if (request.userContent.contains('<section_summaries>')) {
      return StructureResponse(
          rawText: jsonEncode({
        'title': 'One long meeting',
        'summary': 'What happened, in a sentence.',
        'recordingType': 'meeting',
        'language': 'en-US',
        'extractionConfidence': 'high',
      }));
    }
    return StructureResponse(rawText: jsonEncode(_note(++_sections)));
  }

  Map<String, dynamic> _note(int n) => {
        'meta': {
          'title': 'Section $n',
          'summary': 'Section $n covered ground of its own.',
          'recordingType': 'meeting',
          'language': 'en-US',
          'extractionConfidence': 'high',
        },
        'participants': const <Map<String, dynamic>>[],
        'sections': [
          {
            'heading': 'Topic $n',
            'bullets': [
              for (var i = 0; i < 40; i++)
                'Point $i made during section $n, written out at the length a '
                    'real bullet runs to so this note is a realistic size.',
            ],
            'sourceRef': {'startMs': 0, 'endMs': 1, 'quote': 'turn number $n'},
          }
        ],
        'decisions': const <Map<String, dynamic>>[],
        'openQuestions': const <Map<String, dynamic>>[],
        'tasks': const <Map<String, dynamic>>[],
        'risks': const <Map<String, dynamic>>[],
        'timelineAnchors': const <Map<String, dynamic>>[],
        'keyConcepts': null,
        'flashcards': null,
        'quiz': null,
      };
}

/// An hour of speech, in turns long enough to consume a window budget.
Transcript _longTranscript({int segments = 900}) => Transcript([
      for (var i = 0; i < segments; i++)
        TranscriptSegment(
          startMs: i * 4000,
          endMs: (i + 1) * 4000,
          text: 'This is turn number $i and it carries a reasonable amount of '
              'speech so the window budget is actually consumed.',
          speaker: 'SPEAKER_0${i % 3}',
        ),
    ]);

void structuringTests() {
  late _Sink sink;
  late DebugLog log;

  setUp(() {
    sink = _Sink();
    log = DebugLog(sink: sink);
  });

  tearDown(() => log.dispose());

  Future<void> writeNote({
    int context = 8192,
    void Function(StructureEvent)? listener,
  }) async {
    await StructuringPipeline(
      provider: _SmallServer(contextWindowTokens: context),
      onEvent: listener ?? StructuringTelemetry(log: log).listener,
    ).run(
      transcript: _longTranscript(),
      referenceDate: '2026-09-05',
      timeZone: 'UTC',
      sttProviderName: 'Whisper',
    );
    await log.flush();
  }

  Iterable<DebugEntry> structuring() =>
      sink.entries.where((e) => e.tag == 'structuring');

  DebugEntry withField(String key) =>
      structuring().firstWhere((e) => e.fields.containsKey(key));

  test('nothing is recorded while debug mode is off', () async {
    await writeNote();
    expect(sink.entries, isEmpty,
        reason: 'writing a note must cost nothing extra when nobody is '
            'watching, which is the whole design of the flag');
  });

  test('the pipeline is not even handed a listener when the log is off', () {
    expect(StructuringTelemetry(log: log).listener, isNull,
        reason: 'null means the pipeline does not build the events either');
  });

  test('the numbers that decide how a long recording is written are recorded',
      () async {
    await log.setEnabled(true);
    await writeNote();

    final planned = withField('budgetTokens');
    expect(planned.fields['windows'], greaterThan(4));
    expect(planned.fields['contextWindowTokens'], 8192);
    expect(planned.fields['budgetTokens'], isA<int>());
    expect(planned.fields['transcriptTokens'], isA<int>());
  });

  test('a merge done here rather than by the model says so, with why',
      () async {
    await log.setEnabled(true);
    await writeNote();

    final merge = withField('largestPartialTokens');
    expect(merge.fields['stitched'], isTrue);
    expect(merge.fields['partials'], merge.fields['batches'],
        reason: 'a batch per partial is what "nothing can be grouped" means');
    expect(
      merge.fields['largestPartialTokens'] as int,
      greaterThan((merge.fields['budgetTokens'] as int) ~/ 2),
      reason: 'the arithmetic that made the old merge impossible, written down',
    );
  });

  test('an assumed context window is a warning, not a silent default',
      () async {
    await log.setEnabled(true);
    await StructuringPipeline(
      // 32k of real capacity, and not a word about it — which is what forces the
      // pipeline onto its assumption.
      provider: _SmallServer(contextWindowTokens: 32768, reports: 0),
      onEvent: StructuringTelemetry(log: log).listener,
    ).run(
      transcript: _longTranscript(segments: 200),
      referenceDate: '2026-09-05',
      timeZone: 'UTC',
      sttProviderName: 'Whisper',
    );
    await log.flush();

    final warning =
        structuring().firstWhere((e) => e.level == DebugLevel.warning);
    expect(warning.message, contains('did not say how much it can read'));
  });

  test('a reply of nothing at all is recorded as nothing at all', () async {
    await log.setEnabled(true);
    // A context too small for even one section: every call overflows, which is what the
    // server answers with silence.
    await expectLater(
      StructuringPipeline(
        provider: _SmallServer(contextWindowTokens: 3000, maxOutputTokens: 900),
        onEvent: StructuringTelemetry(log: log).listener,
      ).run(
        transcript: _longTranscript(segments: 60),
        referenceDate: '2026-09-05',
        timeZone: 'UTC',
        sttProviderName: 'Whisper',
      ),
      throwsA(isA<StructuringException>()),
    );
    await log.flush();

    final failure = structuring().firstWhere((e) => e.level == DebugLevel.error);
    expect(failure.fields['replyLength'], 0,
        reason: 'a length of zero is the signature of a prompt past the '
            'context window, and it is the fact that was missing');
    final sent = structuring().lastWhere((e) => e.message.contains('sent'));
    expect(sent.fields['promptTokens'], isA<int>(),
        reason: 'the size of the prompt that overflowed sits beside it');
  });

  test('every call is timed and priced', () async {
    await log.setEnabled(true);
    await writeNote();

    final finished = structuring().where((e) => e.message.contains('came back'));
    expect(finished, isNotEmpty);
    expect(finished.every((e) => e.fields.containsKey('tookMs')), isTrue);

    final done = structuring().last;
    expect(done.message, contains('the note is written'));
    expect(done.fields['calls'], greaterThan(1));
  });

  test('a handler that throws does not take the note down with it', () async {
    await log.setEnabled(true);
    var seen = 0;
    await writeNote(listener: (event) {
      seen++;
      throw StateError('telemetry is broken');
    });

    expect(seen, greaterThan(1),
        reason: 'the pipeline kept going, and kept reporting');
  });
}
