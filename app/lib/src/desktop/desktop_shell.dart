import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../recording/recording_controller.dart';

/// Linux/Windows/macOS tray controls for record, show, and quit.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key, required this.child});

  final Widget child;

  static bool get isSupported =>
      !kIsWeb &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell>
    with TrayListener, WindowListener {
  @override
  void initState() {
    super.initState();
    if (!DesktopShell.isSupported) return;
    trayManager.addListener(this);
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_install());
    });
  }

  Future<void> _install() async {
    try {
      await windowManager.ensureInitialized();
      await trayManager.setIcon('icons/android-chrome-512x512.png');
      await trayManager.setToolTip('Echo Codex');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Show Echo Codex'),
        MenuItem(key: 'record', label: 'Start recording'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit'),
      ]));
    } on Object {
      // Tray plugins are absent in tests and some live-reload desktop sessions.
    }
  }

  @override
  void dispose() {
    if (DesktopShell.isSupported) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onTrayIconMouseDown() => windowManager.show();

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'show':
        windowManager.show();
      case 'record':
        windowManager.show();
        unawaited(
          ref.read(recordingControllerProvider.notifier).startRecording(),
        );
      case 'quit':
        windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
