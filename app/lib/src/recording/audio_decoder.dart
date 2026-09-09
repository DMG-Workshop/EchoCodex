import 'dart:io';

import 'package:flutter/services.dart';

import 'ffmpeg_locator.dart';

/// Turns a compressed audio or video file into the WAV the pipeline expects.
///
/// Only the platform can do this: MP3, AAC, FLAC, Vorbis and the MP4 family are decoded
/// by codecs that ship with iOS and Android, and the alternative — bundling a decoder for
/// each — would add tens of megabytes to the binary to duplicate what the OS already has.
///
/// The contract is deliberately file-to-file rather than returning bytes: an hour of audio
/// is roughly 115 MB of PCM, which is not something to move across a platform channel.
abstract class AudioDecoder {
  /// Decodes [sourcePath] and writes 16 kHz mono PCM16 WAV to [targetPath].
  ///
  /// Throws [AudioDecodeException] when the file cannot be opened, carries no audio
  /// track, or the platform has no decoder for it.
  Future<void> decodeToWav({
    required String sourcePath,
    required String targetPath,
  });
}

class AudioDecodeException implements Exception {
  const AudioDecodeException(this.message, [this.remedy]);

  final String message;
  final String? remedy;

  @override
  String toString() => message;
}

/// The real decoder, backed by `MediaExtractor`/`MediaCodec` on Android and
/// `AVAssetReader` on iOS.
class PlatformAudioDecoder implements AudioDecoder {
  const PlatformAudioDecoder(
      [this._channel = const MethodChannel('kallanotes/audio_decoder')]);

  final MethodChannel _channel;

  @override
  Future<void> decodeToWav({
    required String sourcePath,
    required String targetPath,
  }) async {
    if (_canUseFfmpeg) {
      await _decodeWithFfmpeg(sourcePath: sourcePath, targetPath: targetPath);
      return;
    }

    try {
      await _channel.invokeMethod<void>('decodeToWav', {
        'sourcePath': sourcePath,
        'targetPath': targetPath,
      });
    } on MissingPluginException {
      await _decodeWithFfmpeg(sourcePath: sourcePath, targetPath: targetPath);
      return;
    } on PlatformException catch (e) {
      throw AudioDecodeException(
        'The file could not be decoded.',
        e.message ?? 'It may be corrupt, or use a codec this device lacks.',
      );
    }
  }

  bool get _canUseFfmpeg =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  Future<void> _decodeWithFfmpeg({
    required String sourcePath,
    required String targetPath,
  }) async {
    final binary = const FfmpegLocator().locate();
    try {
      final result = await Process.run(binary, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        sourcePath,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'pcm_s16le',
        targetPath,
      ]);
      if (result.exitCode != 0) {
        throw AudioDecodeException(
          'The file could not be decoded.',
          (result.stderr as String).trim().isEmpty
              ? 'It may be corrupt, or contain no audio track.'
              : (result.stderr as String).trim(),
        );
      }
    } on ProcessException {
      throw const AudioDecodeException(
        'This computer does not have FFmpeg installed.',
        'Install FFmpeg, then try importing the file again.',
      );
    }
  }
}
