import 'dart:async';

import 'package:flutter/services.dart';

/// Files handed to the app from outside: a share sheet, or "Open with Echo Codex".
///
/// Two paths, because a share can arrive either way round: the app may already be running
/// (a live event), or it may have been launched by the share itself, in which case the
/// platform captured the file before any Dart existed to hear about it. [take] covers the
/// second case and [files] the first, and both hand back a path in the app's own cache
/// rather than a URI whose read permission expires.
class SharedFiles {
  SharedFiles([this._channel = const MethodChannel('com.echocodex/shared_file')]) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedFile' && call.arguments is String) {
        _controller.add(call.arguments as String);
      }
    });
  }

  final MethodChannel _channel;
  final _controller = StreamController<String>.broadcast();

  /// Files shared while the app is running.
  Stream<String> get files => _controller.stream;

  /// The file the app was launched with, if it was launched by a share.
  ///
  /// Read-and-clear on the platform side: importing the same file again on every resume
  /// would be worse than missing one.
  Future<String?> take() async {
    try {
      return await _channel.invokeMethod<String>('takeSharedFile');
    } on MissingPluginException {
      return null; // a platform with no share integration
    } on PlatformException {
      return null;
    }
  }

  Future<void> dispose() => _controller.close();
}
