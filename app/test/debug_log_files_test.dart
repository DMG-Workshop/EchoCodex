import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/diagnostics/debug_log_files.dart';
import 'package:transcript_core/transcript_core.dart';

void main() {
  late Directory root;
  late DayFileDebugSink sink;

  setUp(() {
    root = Directory.systemTemp.createTempSync('debug-log-test');
    sink = DayFileDebugSink(root: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  DebugEntry entry(DateTime at, {String message = 'something happened'}) =>
      DebugEntry(
        at: at,
        level: DebugLevel.info,
        tag: 'queue',
        message: message,
        fields: const {'chunk': 1},
      );

  List<String> dayFiles() => root
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.startsWith('debug-2'))
      .toList()
    ..sort();

  test('a batch lands in the file for its own UTC day', () async {
    await sink.append([entry(DateTime.utc(2026, 9, 12, 10))]);

    expect(dayFiles(), ['debug-2026-09-12.jsonl']);
    expect((await sink.read()).single.message, 'something happened');
  });

  test('a batch spanning midnight is split, one write per file', () async {
    await sink.append([
      entry(DateTime.utc(2026, 9, 11, 23, 59), message: 'before'),
      entry(DateTime.utc(2026, 9, 12, 0, 1), message: 'after'),
    ]);

    expect(dayFiles(), ['debug-2026-09-11.jsonl', 'debug-2026-09-12.jsonl']);
    expect((await sink.read()).map((e) => e.message), ['before', 'after']);
  });

  test('entries read back oldest first, across files', () async {
    await sink.append([entry(DateTime.utc(2026, 9, 12, 8), message: 'second')]);
    await sink.append([entry(DateTime.utc(2026, 9, 11, 8), message: 'first')]);

    expect((await sink.read()).map((e) => e.message), ['first', 'second']);
  });

  test('appending twice adds to the same file rather than replacing it',
      () async {
    await sink.append([entry(DateTime.utc(2026, 9, 12, 8), message: 'one')]);
    await sink.append([entry(DateTime.utc(2026, 9, 12, 9), message: 'two')]);

    expect(dayFiles(), hasLength(1));
    expect((await sink.read()).map((e) => e.message), ['one', 'two']);
  });

  group('the 48 hour window', () {
    test('a whole day outside the window is deleted, not rewritten', () async {
      await sink.append([entry(DateTime.utc(2026, 9, 9, 8))]);
      await sink.append([entry(DateTime.utc(2026, 9, 12, 8))]);

      await sink.purgeBefore(DateTime.utc(2026, 9, 11, 10));

      expect(dayFiles(), ['debug-2026-09-12.jsonl'],
          reason: 'whole days falling out at once is the point of day files');
    });

    test('the file straddling the cutoff keeps only what is inside it',
        () async {
      await sink.append([
        entry(DateTime.utc(2026, 9, 11, 6), message: 'too old'),
        entry(DateTime.utc(2026, 9, 11, 18), message: 'still inside'),
      ]);

      await sink.purgeBefore(DateTime.utc(2026, 9, 11, 12));

      expect((await sink.read()).map((e) => e.message), ['still inside'],
          reason: '48 hours has to mean 48 hours, not "about two days"');
    });

    test('a purge with nothing to drop leaves the file alone', () async {
      await sink.append([entry(DateTime.utc(2026, 9, 12, 18))]);
      final before = File('${root.path}/debug-2026-09-12.jsonl').lastModifiedSync();

      await sink.purgeBefore(DateTime.utc(2026, 9, 12, 6));

      expect(File('${root.path}/debug-2026-09-12.jsonl').lastModifiedSync(),
          before,
          reason: 'rewriting an untouched file on every hourly purge is waste');
    });

    test('purging an empty directory is a no-op, not a crash', () async {
      await expectLater(
          sink.purgeBefore(DateTime.utc(2026, 9, 12)), completes);
    });
  });

  group('surviving a bad file', () {
    test('a line torn in half costs one entry, not the log', () async {
      await sink.append([entry(DateTime.utc(2026, 9, 12, 8), message: 'good')]);
      final file = File('${root.path}/debug-2026-09-12.jsonl');
      await file.writeAsString('{"at":"2026-09-12T09:00:00Z","lev\n',
          mode: FileMode.append);
      await sink.append([entry(DateTime.utc(2026, 9, 12, 10), message: 'after')]);

      expect((await sink.read()).map((e) => e.message), ['good', 'after'],
          reason: 'a process killed mid-write must not make the log unreadable');
    });

    test('a JSON value that is not an object is skipped', () async {
      final file = File('${root.path}/debug-2026-09-12.jsonl');
      await file.create(recursive: true);
      await file.writeAsString('"just a string"\n[1,2,3]\n');

      expect(await sink.read(), isEmpty);
    });

    test('files that are not day files are left entirely alone', () async {
      await root.create(recursive: true);
      final crash = File('${root.path}/crash-reports.jsonl')
        ..writeAsStringSync('{"not":"ours"}\n');

      await sink.append([entry(DateTime.utc(2026, 9, 12, 8))]);
      await sink.purgeBefore(DateTime.utc(2026, 9, 20));
      await sink.clear();

      expect(crash.existsSync(), isTrue,
          reason: 'the crash reports live in the same directory');
    });
  });

  test('a runaway log is capped, and says that it was', () async {
    final small = DayFileDebugSink(root: root, maxBytesPerDay: 2000);
    for (var i = 0; i < 60; i++) {
      await small.append([
        entry(DateTime.utc(2026, 9, 12, 8), message: 'line $i padded out a bit')
      ]);
    }

    final kept = await small.read();
    expect(File('${root.path}/debug-2026-09-12.jsonl').lengthSync(),
        lessThan(8000),
        reason: 'a diagnostic tool must not fill the device it is diagnosing');
    expect(
      kept.where((e) => e.message.contains('reached its ceiling')),
      isNotEmpty,
      reason: 'dropping lines silently is worse than dropping them loudly',
    );
    expect(kept.last.message, contains('line 59'),
        reason: 'the newest lines are the ones kept');
  });

  test('clear removes every day file', () async {
    await sink.append([entry(DateTime.utc(2026, 9, 11, 8))]);
    await sink.append([entry(DateTime.utc(2026, 9, 12, 8))]);

    await sink.clear();

    expect(dayFiles(), isEmpty);
    expect(await sink.read(), isEmpty);
  });

  group('export', () {
    test('writes a readable file with the header and every entry', () async {
      await sink.append([
        entry(DateTime.utc(2026, 9, 12, 8), message: 'first thing'),
        entry(DateTime.utc(2026, 9, 12, 9), message: 'second thing'),
      ]);

      final file = await sink.export(header: 'Echo Codex 1.2.3 · linux');
      final text = await file.readAsString();

      expect(text, contains('Echo Codex 1.2.3 · linux'));
      expect(text, contains('2 entries'));
      expect(text, contains('first thing'));
      expect(text, contains('second thing'));
      expect(text, isNot(contains('"message"')),
          reason: 'nobody wants to read JSON-lines in a bug report');
    });

    test('an export of nothing is still a valid file', () async {
      final file = await sink.export();
      expect(file.existsSync(), isTrue);
      expect(await file.readAsString(), contains('0 entries'));
    });
  });

  test('bytesOnDisk counts the day files and nothing else', () async {
    expect(sink.bytesOnDisk, 0);
    await sink.append([entry(DateTime.utc(2026, 9, 12, 8))]);
    expect(sink.bytesOnDisk, greaterThan(0));
  });

  test('what is written is the JSON the reader expects', () async {
    await sink.append([entry(DateTime.utc(2026, 9, 12, 8))]);
    final line =
        File('${root.path}/debug-2026-09-12.jsonl').readAsLinesSync().single;
    final decoded = jsonDecode(line) as Map<String, Object?>;

    expect(decoded['at'], '2026-09-12T08:00:00.000Z');
    expect(decoded['level'], 'info');
    expect(decoded['tag'], 'queue');
    expect((decoded['fields']! as Map)['chunk'], 1);
  });
}
