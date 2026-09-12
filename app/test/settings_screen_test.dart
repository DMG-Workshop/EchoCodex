import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echo_codex_app/src/settings/connection_test_controller.dart';
import 'package:echo_codex_app/src/settings/provider_config.dart';
import 'package:echo_codex_app/src/settings/secure_key_store.dart';
import 'package:echo_codex_app/src/recording/recording_controller.dart';
import 'package:echo_codex_app/src/settings/settings_screen.dart';
import 'package:transcript_core/transcript_core.dart';

void main() {
  // The screen is two full provider sections tall. The default 800x600 test viewport
  // leaves the second one unbuilt, so these tests run on a surface that fits both.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1200, 2600);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<InMemoryKeyStore> pumpSettings(
    WidgetTester tester,
    List<Object> replies, {
    InMemoryKeyStore? keys,
  }) async {
    final store = keys ?? InMemoryKeyStore();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(RecordingTransport(replies)),
          keyStoreProvider.overrideWithValue(store),
          settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('the two stages are offered separately', (tester) async {
    await pumpSettings(tester, []);

    expect(find.text('SPEECH TO TEXT'), findsOneWidget);
    expect(find.text('NOTES AND TASKS'), findsOneWidget);
  });

  testWidgets('Claude is offered for notes but never for transcription',
      (tester) async {
    await pumpSettings(tester, []);

    // The whole architecture in one assertion: the Messages API takes no audio, so
    // Claude must not appear as something the user can transcribe with.
    expect(
      ProviderKind.forStage(ProviderStage.transcription),
      isNot(contains(ProviderKind.anthropic)),
    );
    expect(
      ProviderKind.forStage(ProviderStage.structuring),
      contains(ProviderKind.anthropic),
    );
    expect(find.text('Claude'), findsOneWidget);
  });

  testWidgets('the default transcription option needs no key at all',
      (tester) async {
    await pumpSettings(tester, []);

    expect(ProviderKind.forStage(ProviderStage.transcription).first.needsKey,
        isFalse);
    expect(find.textContaining('Free, offline, no key'), findsOneWidget);
  });

  testWidgets('testing without a key says so instead of calling out',
      (tester) async {
    final transport = RecordingTransport(const []);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(transport),
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Structuring defaults to Claude, which needs a key none has been entered for.
    await tester.tap(find.text('Test connection').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('No API key saved'), findsOneWidget);
    expect(transport.calls, isEmpty,
        reason: 'no point spending a request to discover there is no key');
  });

  testWidgets('a successful test reports the models the key can reach',
      (tester) async {
    final store = InMemoryKeyStore();
    await store.write('anthropic', 'sk-test-key');

    await pumpSettings(
      tester,
      [
        HttpReply(
          200,
          jsonEncode({
            'data': [
              {'id': 'claude-opus-5'},
              {'id': 'claude-sonnet-5'},
            ],
          }),
        ),
      ],
      keys: store,
    );

    await tester.tap(find.text('Test connection').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Connected'), findsOneWidget);
    expect(find.textContaining('claude-sonnet-5'), findsOneWidget);

    final modelPicker = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(modelPicker);
    await tester.tap(modelPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('claude-sonnet-5').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('provider.model.anthropic'), 'claude-sonnet-5');
  });

  testWidgets('a rejected key gets an explanation and a remedy',
      (tester) async {
    final store = InMemoryKeyStore();
    await store.write('anthropic', 'sk-wrong');

    await pumpSettings(
      tester,
      [
        HttpReply(
            401,
            jsonEncode({
              'error': {'message': 'invalid x-api-key'},
            })),
      ],
      keys: store,
    );

    await tester.tap(find.text('Test connection').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('rejected the credentials'), findsOneWidget);
    expect(find.textContaining('invalid x-api-key'), findsOneWidget);
    expect(find.textContaining('revoked'), findsOneWidget);
  });

  testWidgets('a local endpoint gets an address field, not a key field',
      (tester) async {
    await pumpSettings(tester, []);

    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Address'), findsOneWidget);
    expect(find.textContaining('192.168'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'API key'), findsNothing);
  });

  testWidgets('an unreachable local server explains the usual causes',
      (tester) async {
    await pumpSettings(tester, [
      const TransportException(TransportFailure.refused, 'Connection refused'),
    ]);

    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Address'), 'http://192.168.1.50:11434');
    await tester.tap(find.text('Test connection').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing is listening'), findsOneWidget);
    expect(find.textContaining('OLLAMA_HOST'), findsOneWidget);
    expect(find.textContaining('Local Network'), findsOneWidget,
        reason: 'on iOS a blocked request looks identical to a dead server');
  });

  testWidgets('a long failure summary wraps instead of being cut off',
      (tester) async {
    await pumpSettings(tester, [
      const TransportException(TransportFailure.refused, 'Connection refused'),
    ]);

    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Address'), 'http://192.168.1.50:11434');
    await tester.tap(find.text('Test connection').last);
    await tester.pumpAndSettle();

    final summary = tester.widget<Text>(
      find.textContaining('Nothing is listening'),
    );
    expect(summary.overflow, isNot(TextOverflow.ellipsis),
        reason:
            'truncating the summary hides the half that says what went wrong');
  });

  testWidgets('the failure panel opens the whole message, copyable',
      (tester) async {
    await pumpSettings(tester, [
      const TransportException(TransportFailure.refused, 'Connection refused'),
    ]);

    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Address'), 'http://192.168.1.50:11434');
    await tester.tap(find.text('Test connection').last);
    await tester.pumpAndSettle();

    // Tapping the panel itself, not its icon — the whole thing is the target, and
    // Icons.info_outline appears elsewhere on this screen.
    await tester.tap(find.textContaining('OLLAMA_HOST'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    final shown = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SelectableText),
      ),
    );
    expect(shown.data, contains('Nothing is listening'),
        reason: 'the dialog carries the summary, not just the remedy below it');
    expect(shown.data, contains('OLLAMA_HOST'));
    expect(find.text('Copy'), findsOneWidget);
  });

  test('the copyable report gathers every part the provider reported', () {
    final report = connectionReport(ConnectionResult.failure(
      summary: 'Server is running but has no models loaded',
      remedy: 'Pull or load a model first, then test again.',
      detail: 'GET /v1/models returned 200 with no data array',
    ));

    expect(report, contains('Server is running but has no models loaded'));
    expect(report, contains('Pull or load a model first'));
    expect(report, contains('GET /v1/models'));
  });

  testWidgets('entering a key stores it and clears the field', (tester) async {
    final store = InMemoryKeyStore();

    await pumpSettings(
      tester,
      [
        HttpReply(200, jsonEncode({'data': <Object>[]}))
      ],
      keys: store,
    );

    await tester.enterText(
        find.widgetWithText(TextField, 'API key'), 'sk-brand-new');
    await tester.tap(find.text('Test connection').last);
    await tester.pumpAndSettle();

    expect(await store.read('anthropic'), 'sk-brand-new');
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller?.text, isEmpty,
        reason: 'the key is never left sitting in a visible field');
  });

  testWidgets('Save persists a typed key without needing a connection test',
      (tester) async {
    final store = InMemoryKeyStore();
    await pumpSettings(tester, [], keys: store);

    await tester.enterText(
        find.widgetWithText(TextField, 'API key'), 'sk-not-yet-tested');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await store.read('anthropic'), 'sk-not-yet-tested',
        reason: 'the key field only autosaves via Test connection otherwise');
    expect(find.text('Settings saved'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller?.text, isEmpty,
        reason: 'the key is never left sitting in a visible field');
  });

  testWidgets('Save does not disturb a choice already made', (tester) async {
    final store = InMemoryKeyStore();
    await pumpSettings(tester, [], keys: store);

    await tester.ensureVisible(find.text('Ollama'));
    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Settings saved'), findsOneWidget);
    expect(find.text('Ollama'), findsOneWidget,
        reason: 'an explicit save must not revert an autosaved choice');
  });

  testWidgets('the header states what happens to a recording', (tester) async {
    // Default is on-device recognition; nothing is chosen for structuring yet, so the
    // app must not claim to be private before it has earned it.
    await pumpSettings(tester, []);
    expect(find.textContaining('sent to a service'), findsOneWidget,
        reason: 'an unconfigured app has not earned a privacy claim');
  });

  testWidgets('choosing a local model earns the on-network claim',
      (tester) async {
    await pumpSettings(tester, []);

    await tester.ensureVisible(find.text('Ollama'));
    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing leaves your network'), findsOneWidget);
    expect(
        find.textContaining('does not work in airplane mode'), findsOneWidget,
        reason: 'the phone still has to reach the machine running the model');
  });

  testWidgets('a local provider offers Find and a model field, not a key field',
      (tester) async {
    await pumpSettings(tester, []);

    await tester.ensureVisible(find.text('LM Studio'));
    await tester.tap(find.text('LM Studio'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Find'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Model'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Address'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'API key'), findsNothing);
  });

  testWidgets('a chosen provider is persisted, not lost on the next visit',
      (tester) async {
    // The Phase 0 gap: the settings UI never wrote the selection, so a configured app
    // recorded with nothing set. Selecting a provider must reach the store.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SettingsStore(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportProvider.overrideWithValue(RecordingTransport(const [])),
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          settingsStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Ollama'));
    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();

    expect(store.kindFor(ProviderStage.structuring), ProviderKind.ollama,
        reason: 'a selection the recorder never sees is the bug this closes');
  });

  test('a stored key is masked rather than displayed', () {
    expect(SecureKeyStore.mask('sk-ant-api03-abcdefghijklmnop'),
        'sk-••••••••mnop');
    expect(SecureKeyStore.mask('short'), '•••••');
  });

  group('testing a keyless provider', () {
    Future<ProviderFactory> factoryWith(LiveTranscriptionSource source) async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderFactory(
        RecordingTransport(const []),
        InMemoryKeyStore(),
        SettingsStore(prefs),
        whisperEngine: _UnusedWhisperEngine(),
        liveSource: () => source,
      );
    }

    test('on-device recognition is tested, not told to paste a key', () async {
      // On a real device this reported "Paste a key above, then test again" for a
      // provider that takes no key — the factory has no TranscriptionProvider for it
      // (it listens to the mic, so it is a LiveTranscriptionSource) and the null
      // branch assumed a missing key was the only way to get there.
      final controller = ConnectionTestController(
        await factoryWith(_FakeLiveSource(
          ConnectionResult.success(summary: 'Ready · on-device · 3 languages'),
        )),
      );

      await controller.run(
        const ProviderSelection(kind: ProviderKind.onDeviceStt),
        ProviderStage.transcription,
      );

      final state = controller.state as ConnectionTestDone;
      expect(state.result.ok, isTrue);
      expect(state.result.summary, contains('on-device'));
    });

    test('an unavailable recognizer reports why, without mentioning keys',
        () async {
      final controller = ConnectionTestController(
        await factoryWith(_FakeLiveSource(
          ConnectionResult.failure(
            summary: 'Speech recognition is unavailable on this device',
            remedy: 'Check that dictation is enabled in system settings.',
          ),
        )),
      );

      await controller.run(
        const ProviderSelection(kind: ProviderKind.onDeviceStt),
        ProviderStage.transcription,
      );

      final state = controller.state as ConnectionTestDone;
      expect(state.result.ok, isFalse);
      expect(state.result.summary, contains('unavailable'));
      expect(state.result.remedy, isNot(contains('key')),
          reason: 'nothing here takes a key');
    });
  });

  group('recordings location', () {
    tearDown(() {
      FilePicker.platform = _RejectingFilePicker();
    });

    testWidgets('defaults to on-device storage, with nothing to reset',
        (tester) async {
      await pumpSettings(tester, []);

      await tester.ensureVisible(find.text('Recordings location'));
      expect(find.text('On this device (default)'), findsOneWidget);
      expect(find.byIcon(Icons.restore), findsNothing);
    });

    testWidgets('picking a folder persists it and explains what changes',
        (tester) async {
      FilePicker.platform = _FakeFilePicker('/sdcard/Meetings');
      await pumpSettings(tester, []);

      await tester.ensureVisible(find.text('Recordings location'));
      await tester.tap(find.text('Recordings location'));
      await tester.pumpAndSettle();

      expect(find.text('/sdcard/Meetings'), findsOneWidget);
      expect(
        find.textContaining("won't be moved"),
        findsOneWidget,
        reason: 'existing recordings must not appear to have moved',
      );
    });

    testWidgets('resetting returns to the default location', (tester) async {
      FilePicker.platform = _FakeFilePicker('/sdcard/Meetings');
      await pumpSettings(tester, []);
      await tester.ensureVisible(find.text('Recordings location'));
      await tester.tap(find.text('Recordings location'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.restore));
      await tester.pumpAndSettle();

      expect(find.text('On this device (default)'), findsOneWidget);
    });
  });
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.directoryPath);
  final String? directoryPath;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async =>
      directoryPath;
}

/// The default for every test that never means to touch the picker — a call reaching
/// this is a bug in the test, not a real pick.
class _RejectingFilePicker extends FilePicker {
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async =>
      throw StateError('This test did not expect a directory picker.');
}

/// Returns a fixed test result, standing in for the platform recognizer.
class _FakeLiveSource extends LiveTranscriptionSource {
  _FakeLiveSource(this._result);

  final ConnectionResult _result;

  @override
  ProviderId get id => const ProviderId('fake-on-device');

  @override
  String get displayName => 'Fake on-device';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        acceptsAudio: true,
        acceptsText: false,
        nativeJsonSchema: false,
        streaming: true,
        requiresApiKey: false,
        runsOnDevice: true,
      );

  @override
  Stream<TranscriptSegment> get segments => const Stream.empty();

  @override
  Future<ConnectionResult> test() async => _result;

  @override
  Future<void> start({String? languageHint}) async {}

  @override
  Future<void> stop() async {}
}

/// Never called: these tests only exercise the on-device path, and constructing the
/// real engine would reach for a plugin channel the test binding does not have.
class _UnusedWhisperEngine implements WhisperEngine {
  @override
  Future<bool> isModelReady(String modelId) async => throw UnimplementedError();

  @override
  Future<String?> modelPath(String modelId) async => throw UnimplementedError();

  @override
  Future<List<TranscriptSegment>> transcribe({
    required String modelPath,
    required List<int> pcm16,
    String? languageHint,
  }) async =>
      throw UnimplementedError();
}
