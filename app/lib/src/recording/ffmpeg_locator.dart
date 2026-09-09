import 'dart:io';

/// Finds an FFmpeg binary desktop imports can actually execute.
///
/// GUI launches, AppImages, and Flatpaks often have a stripped `PATH`, so calling
/// `ffmpeg` by name is not enough. Known host and sandbox locations are checked first.
class FfmpegLocator {
  const FfmpegLocator({bool Function(String path)? exists})
      : _exists = exists ?? _fileExists;

  static const candidates = [
    '/usr/bin/ffmpeg',
    '/usr/local/bin/ffmpeg',
    '/run/host/usr/bin/ffmpeg',
    '/var/run/host/usr/bin/ffmpeg',
    '/snap/bin/ffmpeg',
  ];

  final bool Function(String path) _exists;

  static bool _fileExists(String path) => File(path).existsSync();

  /// An absolute path, or `ffmpeg` so PATH is still tried last.
  String locate({String? pathOverride}) {
    final override = pathOverride ?? Platform.environment['FFMPEG'];
    if (override != null && override.isNotEmpty && _exists(override)) {
      return override;
    }
    for (final candidate in candidates) {
      if (_exists(candidate)) return candidate;
    }
    return 'ffmpeg';
  }
}
