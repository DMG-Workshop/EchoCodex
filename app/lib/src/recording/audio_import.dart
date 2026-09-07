import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:transcript_core/transcript_core.dart';

import 'audio_decoder.dart';
import 'recorder_service.dart';

/// A file brought in from outside, converted into exactly what a recording made in the
/// app looks like.
class ImportedAudio {
  const ImportedAudio({
    required this.path,
    required this.duration,
    required this.sourceName,
  });

  /// The normalized WAV, in the recordings folder alongside everything else.
  final String path;
  final Duration duration;

  /// What the file was called, used as the note's provisional title.
  final String sourceName;
}

class AudioImportException implements Exception {
  const AudioImportException(this.message, [this.remedy]);

  final String message;
  final String? remedy;

  @override
  String toString() => message;
}

/// Brings an existing recording into the app: a meeting exported from Zoom or Teams, a
/// lecture recorded by another app, a voice memo.
///
/// Everything lands in the same shape a recording made here does — 16 kHz mono WAV in the
/// recordings folder — so the durable queue, the chunk planner and the offline decoder
/// need no notion of where the audio came from.
class AudioImportService {
  const AudioImportService({
    AudioDecoder decoder = const PlatformAudioDecoder(),
  }) : _decoder = decoder;

  final AudioDecoder _decoder;

  /// The largest file worth accepting.
  ///
  /// Four hours of 16 kHz mono is ~460 MB of working PCM, and the decode holds a copy;
  /// past this the device runs out of room mid-import, which is a worse failure than a
  /// refusal up front.
  static const int maxSourceBytes = 2 * 1024 * 1024 * 1024;

  /// Converts [sourcePath] and returns where it landed.
  ///
  /// [recordingsDirPath] is the folder chosen in Settings, or null for the app's own
  /// storage — the same resolution a new recording goes through, including its fallback.
  Future<ImportedAudio> import({
    required String sourcePath,
    String? recordingsDirPath,
  }) async {
    final format = ImportFormat.forPath(sourcePath);
    if (format == null) {
      throw AudioImportException(
        'That file type cannot be imported.',
        'Supported: ${ImportFormat.values.map((f) => f.label).join(', ')}.',
      );
    }

    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const AudioImportException('That file could not be opened.');
    }
    if (await source.length() > maxSourceBytes) {
      throw const AudioImportException(
        'That file is too large to import.',
        'Split it into shorter recordings and import them separately.',
      );
    }

    final location = await resolveRecordingsDirectory(recordingsDirPath);
    final target = File(p.join(
      location.directory.path,
      'import_${DateTime.now().millisecondsSinceEpoch}.wav',
    ));

    try {
      if (format.needsDecoding) {
        await _decoder.decodeToWav(
          sourcePath: sourcePath,
          targetPath: target.path,
        );
      } else {
        // A WAV still goes through normalization: imported files arrive at whatever rate
        // and channel count they were recorded at, and the chunk planner sizes requests
        // assuming 16 kHz mono.
        await target.writeAsBytes(
          normalizeWavForPipeline(await source.readAsBytes()),
          flush: true,
        );
      }
    } on AudioDecodeException catch (e) {
      await _discard(target);
      throw AudioImportException(e.message, e.remedy);
    } on WavException catch (e) {
      await _discard(target);
      throw AudioImportException(
        'That WAV file could not be read.',
        e.message,
      );
    } on FileSystemException catch (e) {
      await _discard(target);
      throw AudioImportException(
        'The file could not be saved to this device.',
        e.osError?.message,
      );
    }

    if (!target.existsSync()) {
      throw const AudioImportException('The file produced no audio.');
    }

    final durationMs = durationMsForPipelineBytes(await target.length());
    if (durationMs <= 0) {
      await _discard(target);
      throw const AudioImportException(
        'That file contains no audio to transcribe.',
        'A video with no audio track, or a recording of silence.',
      );
    }

    return ImportedAudio(
      path: target.path,
      duration: Duration(milliseconds: durationMs),
      sourceName: p.basenameWithoutExtension(sourcePath),
    );
  }

  /// A half-written file is worse than none: the library would list a recording that
  /// cannot be transcribed.
  Future<void> _discard(File target) async {
    if (target.existsSync()) {
      try {
        await target.delete();
      } on FileSystemException {
        // Nothing more to do — the import is already failing for another reason.
      }
    }
  }
}
