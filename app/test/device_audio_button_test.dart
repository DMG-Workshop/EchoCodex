import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echo_codex_app/src/recording/recording_controller.dart';
import 'package:echo_codex_app/src/screens/record_screen.dart';
import 'package:echo_codex_app/src/settings/provider_config.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required bool supported,
    Map<String, Object> settings = const {},
  }) async {
    SharedPreferences.setMockInitialValues(settings);
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
          deviceAudioSupportedProvider.overrideWith((ref) async => supported),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: DeviceAudioButton())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offered on a device that can do it', (tester) async {
    await pumpButton(tester, supported: true);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('absent where the platform cannot do it at all', (tester) async {
    // iOS has no equivalent API, and Android below 10 has no playback capture. A
    // permanently dead control is worse than no control.
    await pumpButton(tester, supported: false);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('absent when the feature is turned off in Settings', (tester) async {
    await pumpButton(
      tester,
      supported: true,
      settings: {'workflow.deviceAudioCapture': false},
    );
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
