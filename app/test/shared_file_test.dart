import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/recording/shared_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.echocodex/shared_file');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers `takeSharedFile` with [pending], or throws when [missing] is set — the two
  /// shapes the platform side can produce.
  void mockPlatform({String? pending, bool missing = false}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (missing) throw MissingPluginException('no implementation');
      if (call.method == 'takeSharedFile') return pending;
      return null;
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('a file the app was launched with is handed over once', () async {
    mockPlatform(pending: '/cache/shared/zoom_call.m4a');

    expect(await SharedFiles().take(), '/cache/shared/zoom_call.m4a');
  });

  test('nothing pending is null rather than an error', () async {
    mockPlatform();
    expect(await SharedFiles().take(), isNull);
  });

  test('a platform with no share integration is not an error either', () async {
    // Desktop and web have no handler for this channel; the app still has to start.
    mockPlatform(missing: true);
    expect(await SharedFiles().take(), isNull);
  });

  test('a file shared while the app is open arrives on the stream', () async {
    mockPlatform();
    final shared = SharedFiles();
    final received = shared.files.first;

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec
          .encodeMethodCall(const MethodCall('onSharedFile', '/cache/a.mp3')),
      (_) {},
    );

    expect(await received, '/cache/a.mp3');
    await shared.dispose();
  });

  test('a malformed push is ignored rather than crashing the app', () async {
    mockPlatform();
    final shared = SharedFiles();
    var seen = 0;
    shared.files.listen((_) => seen++);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('onSharedFile', 42)),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(seen, 0);
    await shared.dispose();
  });
}
