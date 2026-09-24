import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transcript_core/transcript_core.dart';

import '../recording/recording_controller.dart' show settingsStoreProvider;
import 'provider_config.dart';

/// Drives the connection tester.
///
/// Phase 0's whole point: before a single feature exists, a user (or a developer on a
/// physical device) can prove that a key works, that a laptop on the LAN is reachable,
/// and that the platform is not silently blocking the request.
class ConnectionTestController extends StateNotifier<ConnectionTestState> {
  ConnectionTestController(this._factory, this._settings)
      : super(const ConnectionTestState.idle());

  final ProviderFactory _factory;
  final SettingsStore _settings;

  Future<void> run(ProviderSelection selection, ProviderStage stage) async {
    state = const ConnectionTestState.running();

    final provider = await _factory.testable(selection, stage);

    if (provider == null) {
      state = ConnectionTestState.done(
        ConnectionResult.failure(
          summary: selection.kind.needsKey
              ? 'No API key saved for ${selection.kind.label}'
              : '${selection.kind.label} is not configured yet',
          // Only tell someone to paste a key when the provider actually takes one.
          // A keyless provider reaching this branch is a bug in the factory, and
          // "paste a key" sends the user hunting for something that does not exist.
          remedy: switch (selection.kind) {
            _ when selection.kind.needsEndpoint =>
              'Enter the address of the machine running it, for example '
                  'http://192.168.1.50:11434',
            _ when selection.kind.needsKey =>
              'Paste a key above, then test again.',
            _ =>
              'This provider needs no key. Reopening settings usually clears '
                  'this; if it persists it is a bug worth reporting.',
          },
        ),
      );
      return;
    }

    // Adapters promise never to throw from test(); this guard exists so a bug in one
    // adapter cannot take down the settings screen.
    try {
      final result = await provider.test();

      // Testing the connection is the one moment the app asks a local server about
      // anything other than a note, so it is where the context window gets learned. Saved
      // rather than kept on the adapter, because the adapter is rebuilt for every
      // recording and would otherwise go back to assuming something small — which is what
      // turns an hour of audio into a dozen sections and a merge that has to work around
      // its own budget. Never overwrites a number the user set themselves.
      if (result.ok &&
          result.contextWindowTokens > 0 &&
          _settings.localContextWindowTokens == 0) {
        await _settings
            .setLocalContextWindowTokens(result.contextWindowTokens);
      }

      state = ConnectionTestState.done(result);
    } catch (e) {
      state = ConnectionTestState.done(
        ConnectionResult.failure(
          summary: 'The connection test failed unexpectedly',
          detail: e.toString(),
        ),
      );
    }
  }

  void reset() => state = const ConnectionTestState.idle();
}

sealed class ConnectionTestState {
  const ConnectionTestState();
  const factory ConnectionTestState.idle() = ConnectionTestIdle;
  const factory ConnectionTestState.running() = ConnectionTestRunning;
  const factory ConnectionTestState.done(ConnectionResult result) =
      ConnectionTestDone;
}

class ConnectionTestIdle extends ConnectionTestState {
  const ConnectionTestIdle();
}

class ConnectionTestRunning extends ConnectionTestState {
  const ConnectionTestRunning();
}

class ConnectionTestDone extends ConnectionTestState {
  const ConnectionTestDone(this.result);
  final ConnectionResult result;
}

final connectionTestProvider = StateNotifierProvider.family<
    ConnectionTestController, ConnectionTestState, ProviderStage>(
  (ref, stage) => ConnectionTestController(
    ref.watch(providerFactoryProvider),
    ref.watch(settingsStoreProvider),
  ),
);
