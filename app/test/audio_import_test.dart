import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:transcript_app/src/recording/audio_decoder.dart';
import 'package:transcript_app/src/recording/audio_import.dart';
import 'package:transcript_core/transcript_core.dart';

/// Stands in for the platform codecs: records what it was asked to decode and writes
/// whatever the test wants to find at the other end.
class FakeDecoder implements AudioDecoder {
  FakeDecoder({this.output, this.failure});

  /// Bytes to write at the target path, or null to write nothing at all.
  final Uint8List? output;
  final AudioDecodeException? failure;

  final List<String> decoded = [];

  @override
  Future<void> decodeToWav({
    required String sourcePath,
    required String targetPath,
  }) async {
    decoded.add(sourcePath);
    if (failure != null) throw failure!;
    if (output != null) {
      await File(targetPath).writeAsBytes(output!, flush: true);
    }
  }
}

void main() {
  late Directory workspace;

  setUp(() => workspace = Directory.systemTemp.createTempSync('import_test'));
  tearDown(() => workspace.deleteSync(recursive: true));

  /// A WAV of [seconds] of silence in whatever shape a source file might arrive in.
  Uint8List wavOf({
    required double seconds,
    int sampleRate = 44100,
    int channels = 2,
  }) =>
      buildWav(
        pcm: Uint8List((sampleRate * seconds).round() * channels * 2),
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: 16,
      );

  File sourceFile(String name, [Uint8List? bytes]) {
    final file = File(p.join(workspace.path, name));
    file.writeAsBytesSync(bytes ?? Uint8List(0));
    return file;
  }

  test('a WAV is normalized into the recordings folder', () async {
    final source = sourceFile('meeting.wav', wavOf(seconds: 2));

    final imported = await const AudioImportService().import(
      sourcePath: source.path,
      recordingsDirPath: workspace.path,
    );

    final format = readWavHeader(File(imported.path).readAsBytesSync());
    expect(format.sampleRate, 16000, reason: '44.1 kHz stereo must not reach the planner');
    expect(format.channels, 1);
    expect(imported.duration.inMilliseconds, closeTo(2000, 20));
    expect(imported.sourceName, 'meeting');
    expect(p.dirname(imported.path), workspace.path);
  });

  test('the original file is left where it was', () async {
    final source = sourceFile('keep-me.wav', wavOf(seconds: 1));
    await const AudioImportService()
        .import(sourcePath: source.path, recordingsDirPath: workspace.path);

    expect(source.existsSync(), isTrue,
        reason: 'importing must not consume the user\'s own file');
  });

  test('a compressed file is handed to the platform decoder', () async {
    final decoder = FakeDecoder(output: wavOf(seconds: 3, sampleRate: 16000, channels: 1));
    final source = sourceFile('zoom_call.m4a', Uint8List.fromList([1, 2, 3]));

    final imported = await AudioImportService(decoder: decoder).import(
      sourcePath: source.path,
      recordingsDirPath: workspace.path,
    );

    expect(decoder.decoded, [source.path]);
    expect(imported.duration.inMilliseconds, closeTo(3000, 20));
  });

  test('a video file is accepted — the audio track is what matters', () async {
    final decoder = FakeDecoder(output: wavOf(seconds: 1, sampleRate: 16000, channels: 1));
    final source = sourceFile('lecture.mp4', Uint8List.fromList([1]));

    final imported = await AudioImportService(decoder: decoder).import(
      sourcePath: source.path,
      recordingsDirPath: workspace.path,
    );
    expect(imported.sourceName, 'lecture');
  });

  test('an unsupported extension is refused by name, not by failing later', () async {
    final source = sourceFile('notes.txt', Uint8List.fromList([1]));

    await expectLater(
      const AudioImportService()
          .import(sourcePath: source.path, recordingsDirPath: workspace.path),
      throwsA(isA<AudioImportException>()
          .having((e) => e.message, 'message', contains('cannot be imported'))),
    );
  });

  test('a file that is not there says so', () async {
    await expectLater(
      const AudioImportService().import(
        sourcePath: p.join(workspace.path, 'gone.wav'),
        recordingsDirPath: workspace.path,
      ),
      throwsA(isA<AudioImportException>()),
    );
  });

  test('a decode failure carries the platform remedy through', () async {
    final decoder = FakeDecoder(
      failure: const AudioDecodeException('nope', 'try converting it'),
    );
    final source = sourceFile('broken.mp3', Uint8List.fromList([1]));

    await expectLater(
      AudioImportService(decoder: decoder)
          .import(sourcePath: source.path, recordingsDirPath: workspace.path),
      throwsA(isA<AudioImportException>()
          .having((e) => e.remedy, 'remedy', 'try converting it')),
    );
  });

  test('a failed decode leaves no half-written recording behind', () async {
    final decoder = FakeDecoder(failure: const AudioDecodeException('nope'));
    final source = sourceFile('broken.mp3', Uint8List.fromList([1]));

    await expectLater(
      AudioImportService(decoder: decoder)
          .import(sourcePath: source.path, recordingsDirPath: workspace.path),
      throwsA(isA<AudioImportException>()),
    );

    final leftovers = workspace
        .listSync()
        .where((f) => p.basename(f.path).startsWith('import_'))
        .toList();
    expect(leftovers, isEmpty,
        reason: 'the library must not list a recording that cannot be transcribed');
  });

  test('a video with no audio track is refused rather than imported empty', () async {
    // The decoder succeeded but produced an empty WAV: a silent or audio-less file.
    final decoder =
        FakeDecoder(output: wavOf(seconds: 0, sampleRate: 16000, channels: 1));
    final source = sourceFile('silent.mp4', Uint8List.fromList([1]));

    await expectLater(
      AudioImportService(decoder: decoder)
          .import(sourcePath: source.path, recordingsDirPath: workspace.path),
      throwsA(isA<AudioImportException>()
          .having((e) => e.message, 'message', contains('no audio'))),
    );
  });

  test('a corrupt WAV is reported as such, not passed on to the pipeline', () async {
    final source = sourceFile('bad.wav', Uint8List.fromList([0, 1, 2, 3, 4]));

    await expectLater(
      const AudioImportService()
          .import(sourcePath: source.path, recordingsDirPath: workspace.path),
      throwsA(isA<AudioImportException>()
          .having((e) => e.message, 'message', contains('could not be read'))),
    );
  });
}
