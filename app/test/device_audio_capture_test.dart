import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/recording/device_audio_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kallanotes/device_audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];

  /// Stands in for the platform: records what was asked, answers with [replies] per
  /// method, or throws the [PlatformException] given for one.
  void mockPlatform({
    Map<String, Object?> replies = const {},
    Map<String, PlatformException> errors = const {},
    bool missing = false,
  }) {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (missing) throw MissingPluginException('no implementation');
      calls.add(call);
      final error = errors[call.method];
      if (error != null) throw error;
      return replies[call.method];
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('support', () {
    test('Android 10 and newer is supported', () async {
      mockPlatform(replies: {'isSupported': true});
      expect(await const DeviceAudioCapture().isSupported, isTrue);
    });

    test('a platform without the channel is simply unsupported', () async {
      // iOS has no equivalent API at all; this must not surface as an error.
      mockPlatform(missing: true);
      expect(await const DeviceAudioCapture().isSupported, isFalse);
    });
  });

  group('capture', () {
    test('start passes the target path so Settings\' folder is honoured', () async {
      mockPlatform(replies: {'start': null});

      await const DeviceAudioCapture().start(targetPath: '/recordings/d.wav');

      expect(calls.single.method, 'start');
      expect(calls.single.arguments, {'targetPath': '/recordings/d.wav'});
    });

    test('stop returns the written WAV', () async {
      mockPlatform(replies: {'stop': '/recordings/d.wav'});
      expect(await const DeviceAudioCapture().stop(), '/recordings/d.wav');
    });

    test('a refused consent dialog explains that it is the system prompt', () async {
      mockPlatform(errors: {
        'start': PlatformException(code: 'denied', message: 'no'),
      });

      await expectLater(
        const DeviceAudioCapture().start(targetPath: '/tmp/d.wav'),
        throwsA(isA<DeviceAudioCaptureException>()
            .having((e) => e.message, 'message', contains('permission'))),
      );
    });

    test('a silent capture blames calls specifically, not the recording', () async {
      // The single most likely surprise: the user pointed this at a Zoom call.
      mockPlatform(errors: {
        'stop': PlatformException(code: 'silent', message: 'nothing'),
      });

      await expectLater(
        const DeviceAudioCapture().stop(),
        throwsA(isA<DeviceAudioCaptureException>()
            .having((e) => e.message, 'message', contains('Nothing'))
            .having((e) => e.remedy, 'remedy', contains('Calls cannot be captured'))),
      );
    });

    test('an old Android says which version it needs', () async {
      mockPlatform(errors: {
        'start': PlatformException(code: 'unsupported', message: 'too old'),
      });

      await expectLater(
        const DeviceAudioCapture().start(targetPath: '/tmp/d.wav'),
        throwsA(isA<DeviceAudioCaptureException>()
            .having((e) => e.remedy, 'remedy', contains('Android 10'))),
      );
    });

    test('an unknown platform failure still carries its detail through', () async {
      mockPlatform(errors: {
        'stop': PlatformException(code: 'capture_failed', message: 'mic busy'),
      });

      await expectLater(
        const DeviceAudioCapture().stop(),
        throwsA(isA<DeviceAudioCaptureException>()
            .having((e) => e.remedy, 'remedy', 'mic busy')),
      );
    });

    test('a null path from stop is an error, not an empty recording', () async {
      mockPlatform(replies: {'stop': null});

      await expectLater(
        const DeviceAudioCapture().stop(),
        throwsA(isA<DeviceAudioCaptureException>()),
      );
    });
  });
}
