import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transcript_core/transcript_core.dart';

import '../net/dio_transport.dart';
import '../privacy/crash_log.dart';
import '../recording/on_device_stt.dart';
import '../whisper/native_whisper_engine.dart';
import 'secure_key_store.dart';

/// Which providers exist to choose from, and which stage each can fill.
///
/// The two-slot split is enforced here rather than in the UI: an entry declares the
/// stages it supports, and the settings screen can only offer it where it fits. Claude
/// and the local servers simply never appear in the transcription list.
enum ProviderKind {
  onDeviceStt(
    id: 'on-device',
    label: 'On-device recognition',
    subtitle: 'Free, offline, no key. Audio never leaves the phone.',
    stages: {ProviderStage.transcription},
    needsKey: false,
    runsOnDevice: true,
  ),
  whisperOffline(
    id: 'whisper-offline',
    label: 'Whisper (offline)',
    subtitle: 'A downloaded model decodes on this device. No key, no network.',
    stages: {ProviderStage.transcription},
    needsKey: false,
    runsOnDevice: true,
  ),
  openAiWhisper(
    id: 'openai-transcribe',
    label: 'OpenAI Whisper',
    subtitle: 'Accurate, with word timestamps. 25 MB per request.',
    stages: {ProviderStage.transcription},
  ),
  geminiAudio(
    id: 'gemini-transcribe',
    label: 'Gemini (audio)',
    subtitle: 'Takes audio natively.',
    stages: {ProviderStage.transcription},
  ),
  anthropic(
    id: 'anthropic',
    label: 'Claude',
    subtitle: 'Structuring only — the API takes no audio.',
    stages: {ProviderStage.structuring},
  ),
  openAi(
    id: 'openai',
    label: 'OpenAI',
    subtitle: 'Structuring with strict JSON schema.',
    stages: {ProviderStage.structuring},
  ),
  gemini(
    id: 'gemini',
    label: 'Gemini',
    subtitle: 'Structuring with a response schema.',
    stages: {ProviderStage.structuring},
  ),
  ollama(
    id: 'ollama',
    label: 'Ollama',
    subtitle: 'A model on your own machine. No key, no cloud.',
    stages: {ProviderStage.structuring},
    needsKey: false,
    needsEndpoint: true,
    isLocalNetwork: true,
  ),
  lmStudio(
    id: 'lmstudio',
    label: 'LM Studio',
    subtitle: 'A model on your own machine. No key, no cloud.',
    stages: {ProviderStage.structuring},
    needsKey: false,
    needsEndpoint: true,
    isLocalNetwork: true,
  );

  const ProviderKind({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.stages,
    this.needsKey = true,
    this.needsEndpoint = false,
    this.runsOnDevice = false,
    this.isLocalNetwork = false,
  });

  final String id;
  final String label;
  final String subtitle;
  final Set<ProviderStage> stages;
  final bool needsKey;

  /// True for the local servers, which are configured by address rather than by key.
  final bool needsEndpoint;

  /// Runs on the phone itself. Nothing leaves the device.
  final bool runsOnDevice;

  /// Runs on a machine the user owns. Nothing leaves their network.
  final bool isLocalNetwork;

  static List<ProviderKind> forStage(ProviderStage stage) => switch (stage) {
        // Whisper (offline), OpenAI Whisper and Gemini audio are still real adapters
        // underneath, but on-device recognition is the only one offered here: it needs
        // no key, no download and no network, so it is the one choice a fresh install
        // can just use.
        ProviderStage.transcription => const [onDeviceStt],
        ProviderStage.structuring =>
          values.where((k) => k.stages.contains(stage)).toList(),
      };
}

enum ProviderStage {
  transcription('Speech to text'),
  structuring('Notes and tasks');

  const ProviderStage(this.label);
  final String label;
}

/// What the user has chosen and typed. Secrets are not in here — only the fact that a
/// key exists. The key itself lives in [SecureKeyStore].
class ProviderSelection {
  const ProviderSelection({
    required this.kind,
    this.model,
    this.endpoint,
    this.hasKey = false,
  });

  final ProviderKind kind;
  final String? model;
  final String? endpoint;
  final bool hasKey;

  bool get isConfigured =>
      (!kind.needsKey || hasKey) && (!kind.needsEndpoint || endpoint != null);

  ProviderSelection copyWith({
    ProviderKind? kind,
    String? model,
    String? endpoint,
    bool? hasKey,
  }) =>
      ProviderSelection(
        kind: kind ?? this.kind,
        model: model ?? this.model,
        endpoint: endpoint ?? this.endpoint,
        hasKey: hasKey ?? this.hasKey,
      );
}

/// Builds a live provider from a selection. The one place that knows how to turn stored
/// settings into an adapter — the rest of the app talks to the interfaces.
class ProviderFactory {
  ProviderFactory(
    this._transport,
    this._keys, {
    WhisperEngine? whisperEngine,
    LiveTranscriptionSource Function()? liveSource,
  })  : _whisperEngine = whisperEngine ?? NativeWhisperEngine(),
        _liveSource = liveSource ?? OnDeviceSpeechSource.new;

  final HttpTransport _transport;
  final KeyStore _keys;
  final WhisperEngine _whisperEngine;

  /// Built lazily: constructing the platform recognizer touches a plugin channel, which
  /// a widget test has no binding for.
  final LiveTranscriptionSource Function() _liveSource;

  /// The provider a connection test should exercise.
  ///
  /// Usually the same object the app would use for real, with one exception:
  /// on-device recognition listens to the microphone directly and so is a
  /// [LiveTranscriptionSource], never a [TranscriptionProvider] — it cannot appear in
  /// [transcription]. It still has a meaningful test: whether the platform's dictation
  /// component is present and which languages it has. Without this the settings screen
  /// fell through to the generic "no provider" branch and told a user who needs no key
  /// to go and paste one.
  Future<AiProvider?> testable(
    ProviderSelection selection,
    ProviderStage stage,
  ) async {
    if (stage == ProviderStage.transcription &&
        selection.kind == ProviderKind.onDeviceStt) {
      return _liveSource();
    }
    return stage == ProviderStage.structuring
        ? await structuring(selection)
        : await transcription(selection);
  }

  Future<StructuringProvider?> structuring(ProviderSelection selection) async {
    final key =
        selection.kind.needsKey ? await _keys.read(selection.kind.id) : null;
    if (selection.kind.needsKey && (key == null || key.isEmpty)) return null;

    return switch (selection.kind) {
      ProviderKind.anthropic => AnthropicStructuringProvider(
          transport: _transport,
          apiKey: key!,
          model: selection.model ?? AnthropicStructuringProvider.defaultModel,
        ),
      ProviderKind.openAi => OpenAiStructuringProvider(
          transport: _transport,
          apiKey: key!,
          model: selection.model ?? 'gpt-4o',
        ),
      ProviderKind.gemini => GeminiStructuringProvider(
          transport: _transport,
          apiKey: key!,
          model: selection.model ?? GeminiStructuringProvider.defaultModel,
        ),
      ProviderKind.ollama || ProviderKind.lmStudio => LocalStructuringProvider(
          transport: _transport,
          baseUrl: Uri.parse(selection.endpoint!),
          model: selection.model ?? '',
          flavor: selection.kind == ProviderKind.ollama
              ? LocalFlavor.ollama
              : LocalFlavor.lmStudio,
          apiKey: key,
        ),
      _ => null,
    };
  }

  Future<TranscriptionProvider?> transcription(
      ProviderSelection selection) async {
    final key =
        selection.kind.needsKey ? await _keys.read(selection.kind.id) : null;
    if (selection.kind.needsKey && (key == null || key.isEmpty)) return null;

    return switch (selection.kind) {
      ProviderKind.openAiWhisper => OpenAiTranscriptionProvider(
          transport: _transport,
          apiKey: key!,
          model: selection.model ?? 'whisper-1',
        ),
      ProviderKind.geminiAudio => GeminiTranscriptionProvider(
          transport: _transport,
          apiKey: key!,
          model: selection.model ?? GeminiStructuringProvider.defaultModel,
        ),
      ProviderKind.whisperOffline => WhisperTranscriptionProvider(
          engine: _whisperEngine,
          model: WhisperCatalog.byId(selection.model ?? '') ??
              WhisperCatalog.recommended,
        ),
      // On-device recognition is a platform channel, not an HTTP adapter — it arrives
      // in Phase 1 alongside the recorder.
      _ => null,
    };
  }
}

final transportProvider = Provider<HttpTransport>((ref) => DioTransport());

/// The real key store, wrapped so every key it hands out is registered with the
/// redactor that scrubs crash reports.
///
/// Wired here rather than at the call sites, or as an override in `main`, because those
/// can be forgotten — and a forgotten registration is invisible until the day a key
/// turns up in a diagnostic file. Wrapping the provider means there is no way to obtain
/// a key store that does not do this.
final keyStoreProvider = Provider<KeyStore>(
  (ref) => RedactingKeyStore(
    const SecureKeyStore(),
    ref.watch(diagnosticsProvider).redactor,
  ),
);

final providerFactoryProvider = Provider<ProviderFactory>(
  (ref) => ProviderFactory(
      ref.watch(transportProvider), ref.watch(keyStoreProvider)),
);

/// Persisted, non-secret settings.
class SettingsStore {
  const SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kStructuring = 'provider.structuring';
  static const _kTranscription = 'provider.transcription';
  static const _kModelPrefix = 'provider.model.';
  static const _kEndpointPrefix = 'provider.endpoint.';
  static const _kOnboarded = 'onboarding.completed';
  static const _kRecordingsDir = 'recordings.dirPath';

  /// A folder the user picked instead of the app's own storage, or null for the
  /// default. New recordings go here; recordings already saved elsewhere are not moved.
  String? get recordingsDirPath => _prefs.getString(_kRecordingsDir);

  Future<void> setRecordingsDirPath(String? path) => path == null
      ? _prefs.remove(_kRecordingsDir)
      : _prefs.setString(_kRecordingsDir, path);

  /// Whether the user has been through the first-run explanation.
  ///
  /// Recorded rather than inferred from "is a provider configured": the app ships with
  /// a working default pairing, so a configured app is not evidence that anyone was
  /// ever told where their audio goes — and being told is the point.
  bool get hasOnboarded => _prefs.getBool(_kOnboarded) ?? false;

  Future<void> setOnboarded() => _prefs.setBool(_kOnboarded, true);

  ProviderKind? kindFor(ProviderStage stage) {
    final id = _prefs.getString(
        stage == ProviderStage.structuring ? _kStructuring : _kTranscription);
    if (id == null) return null;
    for (final kind in ProviderKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }

  Future<void> setKind(ProviderStage stage, ProviderKind kind) =>
      _prefs.setString(
          stage == ProviderStage.structuring ? _kStructuring : _kTranscription,
          kind.id);

  String? modelFor(ProviderKind kind) =>
      _prefs.getString('$_kModelPrefix${kind.id}');
  Future<void> setModel(ProviderKind kind, String model) =>
      _prefs.setString('$_kModelPrefix${kind.id}', model);

  String? endpointFor(ProviderKind kind) =>
      _prefs.getString('$_kEndpointPrefix${kind.id}');
  Future<void> setEndpoint(ProviderKind kind, String endpoint) =>
      _prefs.setString('$_kEndpointPrefix${kind.id}', endpoint);

  /// The default pairing: nothing configured, nothing to pay for. On-device recognition
  /// needs no key, and a local model needs no key — so the app has something to do
  /// before the user has pasted anything.
  static const ProviderKind defaultTranscription = ProviderKind.onDeviceStt;

  /// What the current selection does with a recording.
  ///
  /// Computed from the same rules the running app uses, so settings and reality cannot
  /// disagree about where the audio goes.
  ConfigurationPosture get posture {
    final transcription =
        kindFor(ProviderStage.transcription) ?? defaultTranscription;
    final structuring = kindFor(ProviderStage.structuring);

    return ConfigurationPosture.from(
      transcriptionOnDevice: transcription.runsOnDevice,
      transcriptionLocalNetwork: transcription.isLocalNetwork,
      // Nothing chosen yet is treated as cloud rather than assumed private: an
      // unconfigured app must not display a privacy claim it has not earned.
      structuringOnDevice: structuring?.runsOnDevice ?? false,
      structuringLocalNetwork: structuring?.isLocalNetwork ?? false,
      needsApiKey: transcription.needsKey || (structuring?.needsKey ?? true),
    );
  }
}
