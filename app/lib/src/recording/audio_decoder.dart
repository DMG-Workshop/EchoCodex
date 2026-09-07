import 'package:flutter/services.dart';

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
    try {
      await _channel.invokeMethod<void>('decodeToWav', {
        'sourcePath': sourcePath,
        'targetPath': targetPath,
      });
    } on MissingPluginException {
      // A desktop or web build, where this channel has no implementation. Say which
      // formats still work rather than failing with a plugin error the user cannot act on.
      throw const AudioDecodeException(
        'This platform cannot open compressed audio.',
        'Convert the file to WAV and import that instead.',
      );
    } on PlatformException catch (e) {
      throw AudioDecodeException(
        'The file could not be decoded.',
        e.message ?? 'It may be corrupt, or use a codec this device lacks.',
      );
    }
  }
}
