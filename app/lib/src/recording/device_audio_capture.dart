import 'package:flutter/services.dart';

/// Records what the device is playing, rather than what the microphone hears.
///
/// For a webinar, a lecture recording or a podcast the user is listening to. **Not** for
/// calls, and it cannot be made to work for them: Android's playback capture only yields
/// streams whose usage is media, game or unknown, and every conferencing app — Zoom,
/// Teams, Meet — marks call audio as voice communication, which the platform withholds.
/// An app can also opt out of being captured entirely. Android only; iOS has no
/// equivalent API at all.
class DeviceAudioCapture {
  const DeviceAudioCapture(
      [this._channel = const MethodChannel('com.echocodex/device_audio')]);

  final MethodChannel _channel;

  /// Whether this device can do it at all — Android 10 or newer.
  Future<bool> get isSupported async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false; // iOS, desktop, web
    } on PlatformException {
      return false;
    }
  }

  /// Asks for consent and begins capturing into [targetPath].
  ///
  /// The path comes from Dart so a device recording lands in the same folder the user
  /// chose in Settings, alongside everything else.
  ///
  /// The consent dialog is the system's own screen-capture prompt, and it is shown fresh
  /// every time: the grant is single-use from Android 14, so there is no token to keep.
  Future<void> start({required String targetPath}) async {
    try {
      await _channel.invokeMethod<void>('start', {'targetPath': targetPath});
    } on PlatformException catch (e) {
      throw DeviceAudioCaptureException(_messageFor(e), _remedyFor(e));
    } on MissingPluginException {
      throw const DeviceAudioCaptureException(
        'This device cannot record its own audio.',
        'Android 10 or newer is needed. On iOS there is no equivalent at all.',
      );
    }
  }

  /// Stops, and returns the WAV that was written.
  Future<String> stop() async {
    try {
      final path = await _channel.invokeMethod<String>('stop');
      if (path == null) {
        throw const DeviceAudioCaptureException(
          'The recording did not finish cleanly.',
        );
      }
      return path;
    } on PlatformException catch (e) {
      throw DeviceAudioCaptureException(_messageFor(e), _remedyFor(e));
    }
  }

  static String _messageFor(PlatformException e) => switch (e.code) {
        'denied' => 'Recording device audio needs your permission.',
        'silent' => 'Nothing that can be captured was playing.',
        'unsupported' => 'This device cannot record its own audio.',
        _ => 'Recording device audio failed.',
      };

  static String? _remedyFor(PlatformException e) => switch (e.code) {
        'denied' => 'Android shows its own screen-capture prompt; recording cannot '
            'start until it is allowed.',
        // The single most common surprise, and the one worth explaining every time.
        'silent' => 'Calls cannot be captured — Android reserves call audio, so Zoom, '
            'Teams, Meet and phone calls come through silent. Media playback, like a '
            'recorded webinar, does work. Some apps also opt out of being recorded.',
        'unsupported' => 'Android 10 or newer is needed.',
        _ => e.message,
      };
}

class DeviceAudioCaptureException implements Exception {
  const DeviceAudioCaptureException(this.message, [this.remedy]);

  final String message;
  final String? remedy;

  @override
  String toString() => message;
}
