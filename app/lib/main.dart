import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'src/desktop/desktop_shell.dart';
import 'src/onboarding/onboarding_screen.dart';
import 'src/privacy/crash_log.dart';
import 'src/recording/recording_controller.dart';
import 'src/recording/reminder_service.dart';
import 'src/screens/record_screen.dart';
import 'src/settings/provider_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Diagnostics first, so a failure anywhere in the rest of startup is itself recorded
  // rather than lost. Installing the handlers is also what makes the redactor exist,
  // and the key store depends on it.
  final diagnostics = await installCrashReporting();

  // Settings are needed before the first frame — which provider to use is not something
  // to discover halfway through a recording.
  final prefs = await SharedPreferences.getInstance();
  final reminders = ReminderService();
  await reminders.initialize();
  if (DesktopShell.isSupported) {
    await windowManager.ensureInitialized();
  }

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
        diagnosticsProvider.overrideWithValue(diagnostics),
        reminderServiceProvider.overrideWithValue(reminders),
      ],
      child: const EchoCodexApp(),
    ),
  );
}

class EchoCodexApp extends ConsumerStatefulWidget {
  const EchoCodexApp({super.key});

  static const Color _seed = Color(0xFF0B6A6A);

  @override
  ConsumerState<EchoCodexApp> createState() => _EchoCodexAppState();
}

class _EchoCodexAppState extends ConsumerState<EchoCodexApp> {
  late bool _needsOnboarding = !ref.read(settingsStoreProvider).hasOnboarded;

  Future<void> _finishOnboarding() async {
    await ref.read(settingsStoreProvider).setOnboarded();
    if (mounted) setState(() => _needsOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStoreProvider);
    ref.watch(settingsRevisionProvider);
    final lightTheme = ThemeData(
      colorSchemeSeed: EchoCodexApp._seed,
      brightness: Brightness.light,
      useMaterial3: true,
    );
    final darkTheme = ThemeData(
      colorSchemeSeed: EchoCodexApp._seed,
      brightness: Brightness.dThemeData(
      colorScheme: ColorScheme.highContrastLight(primary: Colors.black),
      brightness: Brightness.light,
      useMaterial3: true,
    );
    final highContrastDark = ThemeData(
      colorScheme: ColorScheme.highContrastDark(primary: Colors.white),
      brightness: Brightness.dark,
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'Echo Codex',
      debugShowCheckedModeBanner: false,
      theme: settings.highContrast ? highContrastLight : lightTheme,
      darkTheme: settings.highContrast ? highContrastDark : darkTheme,
      builder: (context, child) => DesktopShell(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(settings.textScale),
            highContrast: settings.highContrast,
            boldText: settings.highContrast,
          ),
          child: child!,
        )ery.of(context).copyWith(
          textScaler: TextScaler.linear(settings.textScale),
        ),
        child: child!,
      ),
      home: _needsOnboarding
          ? OnboardingScreen(onDone: _finishOnboarding)
          : const RecordScreen(),
    );
  }
}
