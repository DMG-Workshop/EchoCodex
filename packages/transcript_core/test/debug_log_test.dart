import 'dart:async';

import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

/// Collects batches instead of writing them, so the buffering and purge policy are
/// testable with no filesystem and no clock of their own.
class RecordingSink implements DebugSink {
  final List<List<DebugEntry>> batches = [];
  final List<DebugEntry> entries = [];
  DateTime? purgedBefore;
  int clears = 0;
  Object? throwOnAppend;
  Completer<void>? _gate;

  /// Stalls every write until [release], so the buffer's overflow path — which only
  /// happens when the writer cannot keep up — can actually be exercised.
  void block() => _gate ??= Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void> append(List<DebugEntry> batch) async {
    final gate = _gate;
    if (gate != null) await gate.future;
    if (throwOnAppend != null) throw throwOnAppend!;
    batches.add(batch);
    entries.addAll(batch);
  }

  @override
  Future<void> purgeBefore(DateTime cutoff) async {
    purgedBefore = cutoff;
    entries.removeWhere((e) => e.at.isBefore(cutoff));
  }

  @override
  Future<List<DebugEntry>> read() async => List.of(entries);

  @override
  Future<void> clear() async {
    clears++;
    entries.clear();
  }
}

void main() {
  late RecordingSink sink;
  late DateTime now;
  late DebugLog log;

  setUp(() {
    sink = RecordingSink();
    now = DateTime.utc(2026, 9, 12, 10);
    log = DebugLog(
      sink: sink,
      redactor: Redactor(),
      bufferLimit: 5,
      clock: () => now,
    );
  });

  tearDown(() => log.dispose());

  group('the gate', () {
    test('records nothing at all while off', () async {
      var built = 0;
      log.info('audio', () {
        built++;
        return 'expensive';
      });
      await log.flush();

      expect(built, 0,
          reason: 'the argument is the expensive part — it must not be built');
      expect(sink.batches, isEmpty);
    });

    test('isOn lets a hot path skip even the closure allocation', () {
      expect(log.isOn, isFalse);
    });

    test('records once switched on', () async {
      await log.setEnabled(true);
      log.info('audio', () => 'started');
      await log.flush();

      expect(sink.entries.single.message, 'started');
      expect(sink.entries.single.level, DebugLevel.info);
      expect(sink.entries.single.tag, 'audio');
    });

    test('switching off flushes rather than discarding', () async {
      await log.setEnabled(true);
      log.info('audio', () => 'the last thing before they gave up');

      await log.setEnabled(false);

      expect(sink.entries, hasLength(1),
          reason:
              'the lines before the user switched off are the ones that matter');
    });

    test('an error carries its type and stack', () async {
      await log.setEnabled(true);
      log.error('queue', () => 'chunk failed',
          error: StateError('boom'), stack: StackTrace.current);
      await log.flush();

      final entry = sink.entries.single;
      expect(entry.level, DebugLevel.error);
      expect(entry.fields['error'], contains('boom'));
      expect(entry.fields['stack'], isNotNull);
    });
  });

  group('buffering', () {
    test('many lines become one batch, not one write each', () async {
      await log.setEnabled(true);
      for (var i = 0; i < 4; i++) {
        log.info('queue', () => 'line $i');
      }
      await log.flush();

      expect(sink.batches, hasLength(1),
          reason: 'one append per line would be an I/O storm');
      expect(sink.batches.single, hasLength(4));
    });

    test('lines reach the sink in the order they happened', () async {
      final roomy = DebugLog(
        sink: sink,
        redactor: Redactor(),
        bufferLimit: 100,
        clock: () => now,
      );
      addTearDown(roomy.dispose);

      await roomy.setEnabled(true);
      for (var i = 0; i < 12; i++) {
        roomy.info('queue', () => 'line $i');
      }
      await roomy.flush();

      expect(
          sink.entries.map((e) => e.message),
          [
            for (var i = 0; i < 12; i++) 'line $i',
          ],
          reason: 'a log out of order is a log nobody can reason from');
    });

    test('a stalled writer drops the middle, never the newest', () async {
      sink.block();
      await log.setEnabled(true);
      for (var i = 0; i < 12; i++) {
        log.info('queue', () => 'line $i');
      }
      sink.release();
      await log.flush();

      final messages = sink.entries.map((e) => e.message).toList();
      expect(messages, contains('line 11'),
          reason: 'when a log outruns its buffer, recent lines explain why');
      expect(messages, isNot(contains('line 5')),
          reason: 'the oldest still buffered are the ones that go');
    });

    test('an overflow is reported rather than silently absorbed', () async {
      sink.block();
      await log.setEnabled(true);
      for (var i = 0; i < 12; i++) {
        log.info('queue', () => 'line $i');
      }
      sink.release();
      await log.flush();

      final warning =
          sink.entries.where((e) => e.message.contains('overflowed')).single;
      expect(warning.level, DebugLevel.warning);
      expect(warning.fields['dropped'], 2,
          reason: 'silently losing lines is worse than losing them loudly');
    });

    test('a sink that cannot write never fails the caller', () async {
      sink.throwOnAppend = StateError('disk full');
      await log.setEnabled(true);
      log.info('audio', () => 'still recording');

      await expectLater(log.flush(), completes,
          reason: 'a broken log must not break the recording it was watching');
    });

    test('a message that throws while building is logged, not propagated',
        () async {
      await log.setEnabled(true);
      log.info('audio', () => throw StateError('bad toString'));
      await log.flush();

      expect(sink.entries.single.level, DebugLevel.warning);
      expect(sink.entries.single.message, contains('could not be built'));
    });
  });

  group('retention', () {
    test('switching on purges anything past the window', () async {
      await log.setEnabled(true);

      expect(sink.purgedBefore, DateTime.utc(2026, 9, 10, 10),
          reason: '48 hours before the clock');
    });

    test('purge drops old entries and keeps recent ones', () async {
      await log.setEnabled(true);
      sink.entries.addAll([
        DebugEntry(
          at: now.subtract(const Duration(hours: 49)),
          level: DebugLevel.info,
          tag: 'old',
          message: 'three days ago',
        ),
        DebugEntry(
          at: now.subtract(const Duration(hours: 2)),
          level: DebugLevel.info,
          tag: 'new',
          message: 'this morning',
        ),
      ]);

      await log.purge();

      expect(sink.entries.map((e) => e.tag), ['new']);
    });
  });

  group('redaction', () {
    test('a secret in a message never reaches the sink', () async {
      final redactor = Redactor(secrets: const ['sk-live-abcdef123456']);
      final guarded = DebugLog(
        sink: sink,
        redactor: redactor,
        clock: () => now,
      );
      addTearDown(guarded.dispose);

      await guarded.setEnabled(true);
      guarded.info('net', () => 'calling with key sk-live-abcdef123456');
      await guarded.flush();

      expect(
          sink.entries.single.message, isNot(contains('sk-live-abcdef123456')),
          reason: 'verbose logging is the easiest way to leak what the app '
              'promises never to collect');
    });

    test('a secret in a field value is scrubbed too, field by field', () async {
      final redactor = Redactor(secrets: const ['sk-live-abcdef123456']);
      final guarded = DebugLog(
        sink: sink,
        redactor: redactor,
        clock: () => now,
      );
      addTearDown(guarded.dispose);

      await guarded.setEnabled(true);
      guarded.info('net', () => 'request',
          fields: () => {'auth': 'Bearer sk-live-abcdef123456', 'attempt': 2});
      await guarded.flush();

      expect(sink.entries.single.fields['auth'],
          isNot(contains('sk-live-abcdef123456')));
      expect(sink.entries.single.fields['attempt'], 2,
          reason: 'a number is not a string and must survive intact');
    });
  });

  group('entries on the wire', () {
    test('an entry round-trips through JSON', () {
      final entry = DebugEntry(
        at: DateTime.utc(2026, 9, 12, 10, 30),
        level: DebugLevel.warning,
        tag: 'audio',
        message: 'level at the floor',
        fields: const {'db': -160.0, 'run': 31},
      );

      final back = DebugEntry.fromJson(entry.toJson())!;

      expect(back.at, entry.at);
      expect(back.level, DebugLevel.warning);
      expect(back.tag, 'audio');
      expect(back.message, entry.message);
      expect(back.fields['run'], 31);
    });

    test('a half-written line is skipped rather than throwing', () {
      expect(DebugEntry.fromJson(const {'level': 'info'}), isNull);
      expect(DebugEntry.fromJson(const {'at': 'not a date'}), isNull);
      expect(
        DebugEntry.fromJson(
            const {'at': '2026-09-12T10:00:00Z', 'level': 'shout'}),
        isNull,
        reason: 'a process killed mid-flush must not make the log unreadable',
      );
    });

    test('the human-readable form leads with time, level and subsystem', () {
      final line = DebugEntry(
        at: DateTime.utc(2026, 9, 12, 10),
        level: DebugLevel.error,
        tag: 'queue',
        message: 'gave up',
        fields: const {'chunk': 3},
      ).format();

      expect(line, startsWith('2026-09-12T10:00:00.000Z'));
      expect(line, contains('ERROR'));
      expect(line, contains('queue'));
      expect(line, endsWith('chunk=3'));
    });
  });
}
