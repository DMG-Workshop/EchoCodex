import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:transcript_core/transcript_core.dart';

import '../privacy/crash_log.dart';
import '../recording/recording_controller.dart';
import '../settings/provider_config.dart';
import 'debug_log_files.dart';

/// Debug Mode: the log, its file, and the one switch that turns it on.
///
/// Built once at startup next to the crash reporter and handed the *same* [Redactor],
/// which is the point: verbose logging of a transcription pipeline moves transcript
/// text and provider keys through memory, and a second logger with its own weaker
/// scrubbing would quietly undo the app's only real privacy claim.
class DebugMode {
  const DebugMode({required this.log, required this.sink});

  final DebugLog log;

  /// The concrete sink, for the screen that shows size, exports and clears. The log
  /// itself only ever sees the [DebugSink] interface.
  final DayFileDebugSink sink;
}

/// Builds the logger and applies the persisted flag.
///
/// Called after [installCrashReporting] so the redactor already exists and already
/// knows about any secrets registered during startup.
Future<DebugMode> installDebugMode({
  required Diagnostics diagnostics,
  required SettingsStore settings,
}) async {
  final root = Directory(
    p.join((await getApplicationSupportDirectory()).path, 'diagnostics', 'debug'),
  );
  final sink = DayFileDebugSink(root: root);
  final log = DebugLog(sink: sink, redactor: diagnostics.redactor);

  // Pushed in once, here. Nothing downstream reads SharedPreferences to decide whether
  // to log.
  await log.setEnabled(settings.debugMode);
  if (log.isOn) {
    final info = await PackageInfo.fromPlatform();
    log.info('app', () => 'debug mode is recording',
        fields: () => {
              'version': '${info.version}+${info.buildNumber}',
              'platform': Platform.operatingSystem,
              'osVersion': Platform.operatingSystemVersion,
              'retentionHours': log.retention.inHours,
            });
  }

  return DebugMode(log: log, sink: sink);
}

/// Overridden in `main` once [installDebugMode] has run, for the same reason
/// [diagnosticsProvider] is: a screen logging into a null logger would look like it
/// worked.
final debugModeProvider = Provider<DebugMode>(
  (ref) => throw UnimplementedError('debugModeProvider must be overridden'),
);

/// The logger itself — what every telemetry call site depends on.
///
/// Unlike [debugModeProvider] this has a real default rather than throwing, and the
/// default is a logger that is simply off. That asymmetry is deliberate: a crash
/// reporter nobody wired up is a bug, because it would silently swallow reports, but a
/// *logger* nobody wired up is the ordinary state of a widget test — and a test that
/// has to override diagnostics before it can build a recorder is a test nobody writes.
/// `main` overrides this with the real one.
final debugLogProvider = Provider<DebugLog>((ref) => DebugLog());

/// Whether Debug Mode is on, as the settings screen sees it.
///
/// A notifier rather than a `FutureProvider` over SharedPreferences: flipping the
/// switch has to take effect on the next log call, not on the next rebuild.
class DebugModeSwitch extends StateNotifier<bool> {
  DebugModeSwitch({required this.settings, required this.log})
      : super(settings.debugMode);

  final SettingsStore settings;
  final DebugLog log;

  Future<void> set(bool enabled) async {
    if (enabled == state) return;
    await settings.setDebugMode(enabled);
    await log.setEnabled(enabled);
    state = enabled;
  }
}

final debugModeSwitchProvider =
    StateNotifierProvider<DebugModeSwitch, bool>((ref) => DebugModeSwitch(
          settings: ref.watch(settingsStoreProvider),
          log: ref.watch(debugLogProvider),
        ));

/// Flushes the buffer when the app leaves the foreground.
///
/// Without this, the last few seconds before the app is backgrounded — which on Android
/// is very often the last few seconds before the OS kills it — are still sitting in
/// memory when the process goes away. Those are precisely the lines worth having.
class DebugLogLifecycle with WidgetsBindingObserver {
  DebugLogLifecycle(this.log);

  final DebugLog log;

  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    unawaited(log.flush());
  }
}
