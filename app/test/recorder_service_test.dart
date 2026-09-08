import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:echo_codex_app/src/recording/recorder_service.dart';
import 'package:transcript_core/transcript_core.dart';

void main() {
  group('resolveRecordingsDirectory', () {
    late Directory defaultDir;
    late Directory customDir;

    setUp(() {
      defaultDir = Directory.systemTemp.createTempSync('transcript_default_');
      customDir = Directory.systemTemp.createTempSync('transcript_custom_');
    });

    tearDown(() {
      for (final dir in [defaultDir, customDir]) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    test('with nothing configured, uses the default and creates it if missing', () async {
      defaultDir.deleteSync();

      final location = await resolveRecordingsDirectory(
        null,
        defaultDirectory: () async => defaultDir,
      );

      expect(location.directory.path, defaultDir.path);
      expect(defaultDir.existsSync(), isTrue);
      expect(location.fallbackWarning, isNull);
    });

    test('a configured folder that exists and is writable is used as-is', () async {
      final location = await resolveRecordingsDirectory(
        customDir.path,
        defaultDirectory: () async => defaultDir,
      );

      expect(location.directory.path, customDir.path);
      expect(location.fallbackWarning, isNull);
    });

    test('a configured folder that no longer exists falls back, with a warning',
        () async {
      final gone = p.join(customDir.path, 'sdcard-that-was-removed');

      final location = await resolveRecordingsDirectory(
        gone,
        defaultDirectory: () async => defaultDir,
      );

      expect(location.directory.path, defaultDir.path);
      expect(location.fallbackWarning, contains('not available'));
    });
  });

  group('silence detection', () {
    /// Levels sampled every 100ms, as the recorder produces them.
    List<Level> levels(List<double> db) => [
          for (var i = 0; i < db.length; i++) Level(i * 100, db[i]),
        ];

    test('finds a pause between two stretches of speech', () {
      final windows = RecorderService.detectSilences(
        levels([
          ...List.filled(10, -12.0), // 0.0-1.0s speech
          ...List.filled(8, -50.0), // 1.0-1.8s quiet
          ...List.filled(10, -14.0), // 1.8-2.8s speech
        ]),
        2800,
      );

      expect(windows, hasLength(1));
      expect(windows.single.startMs, 1000);
      expect(windows.single.endMs, 1800);
      expect(windows.single.midpointMs, 1400,
          reason: 'the planner cuts mid-pause, not at its edge');
    });

    test('ignores a gap too short to be a sentence boundary', () {
      final windows = RecorderService.detectSilences(
        levels([
          ...List.filled(10, -12.0),
          ...List.filled(2, -50.0), // 200ms — a breath
          ...List.filled(10, -12.0),
        ]),
        2200,
      );
      expect(windows, isEmpty);
    });

    test('a recording that ends on a pause still yields a trailing window', () {
      final windows = RecorderService.detectSilences(
        levels([...List.filled(10, -12.0), ...List.filled(8, -52.0)]),
        1800,
      );
      expect(windows, hasLength(1));
      expect(windows.single.endMs, 1800);
    });

    test('continuous speech yields nothing to cut on', () {
      expect(
        RecorderService.detectSilences(levels(List.filled(40, -15.0)), 4000),
        isEmpty,
      );
    });

    test('a silent recording is one long window, not many', () {
      final windows =
          RecorderService.detectSilences(levels(List.filled(40, -60.0)), 4000);
      expect(windows, hasLength(1));
      expect(windows.single.startMs, 0);
    });

    test('output feeds the chunk planner directly', () {
      // The contract that matters: whatever comes out here is what the planner cuts on.
      final windows = RecorderService.detectSilences(
        levels([
          for (var i = 0; i < 900; i++) (i ~/ 100).isEven ? -12.0 : -50.0,
        ]),
        90000,
      );

      final chunks = const ChunkPlanner()
          .plan(totalDurationMs: 90000, silences: windows);

      expect(chunks, isNotEmpty);
      expect(chunks.every((c) => c.boundary != ChunkBoundary.forced), isTrue,
          reason: 'with pauses this regular, every cut should land in one');
    });
  });

  group('chunk size estimate', () {
    test('matches 16 kHz mono PCM16 at 32 kB per second', () {
      const chunk = PlannedChunk(
        index: 0,
        startMs: 0,
        endMs: 45000,
        contentStartMs: 0,
        boundary: ChunkBoundary.silence,
      );
      expect(WavChunkReader.estimateBytes(chunk), 44 + 45 * 32000);
    });
  });
}
