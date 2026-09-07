import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transcript_app/src/recording/recording_controller.dart';
import 'package:transcript_app/src/settings/provider_config.dart';
import 'package:transcript_app/src/settings/secure_key_store.dart';

void main() {
  group('structuringReadyProvider', () {
    // Recording never depends on this — only the note-writing stage does, and it is
    // the one stage with no default, so this is the one thing worth nagging about.
    late SettingsStore settings;
    late InMemoryKeyStore keys;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settings = SettingsStore(prefs);
      keys = InMemoryKeyStore();
      container = ProviderContainer(overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        keyStoreProvider.overrideWithValue(keys),
      ]);
    });

    tearDown(() => container.dispose());

    // SharedPreferences and the key store have no change stream, so every case below
    // invalidates the provider itself after mutating state — exactly what RecordScreen
    // does after a trip to Settings.
    Future<bool> refreshedReady() {
      container.invalidate(structuringReadyProvider);
      return container.read(structuringReadyProvider.future);
    }

    test('nothing chosen yet is not ready', () async {
      expect(await container.read(structuringReadyProvider.future), isFalse);
    });

    test('a key-based provider with no key saved is not ready', () async {
      await settings.setKind(ProviderStage.structuring, ProviderKind.anthropic);
      expect(await refreshedReady(), isFalse);
    });

    test('a key-based provider with a saved key is ready', () async {
      await settings.setKind(ProviderStage.structuring, ProviderKind.anthropic);
      await keys.write(ProviderKind.anthropic.id, 'sk-test');
      expect(await refreshedReady(), isTrue);
    });

    test('clearing a saved key is treated the same as never having chosen one',
        () async {
      await settings.setKind(ProviderStage.structuring, ProviderKind.anthropic);
      await keys.write(ProviderKind.anthropic.id, 'sk-test');
      expect(await refreshedReady(), isTrue);

      await keys.delete(ProviderKind.anthropic.id);
      expect(await refreshedReady(), isFalse);
    });

    test('a local endpoint provider with no address is not ready', () async {
      await settings.setKind(ProviderStage.structuring, ProviderKind.ollama);
      expect(await refreshedReady(), isFalse);
    });

    test('a local endpoint provider with an address is ready', () async {
      await settings.setKind(ProviderStage.structuring, ProviderKind.ollama);
      await settings.setEndpoint(ProviderKind.ollama, 'http://192.168.1.50:11434');
      expect(await refreshedReady(), isTrue);
    });
  });
}
