import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transcript_core/transcript_core.dart';

import '../gemma/on_device_gemma_engine.dart';
import '../net/dio_transport.dart';
import '../privacy/crash_log.dart';
import '../recording/on_device_stt.dart';
import '../recording/recording_controller.dart' show settingsStoreProvider;
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
  gemmaOnDevice(
    id: 'gemma-on-device',
    label: 'Gemma (on-device)',
    subtitle: 'A .litertlm file you already downloaded runs on this device. No key, no network.',
    stages: {ProviderStage.structuring},
    needsKey: false,
    runsOnDevice: true,
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
        // underneath. On-device recognition remains first so a fresh install can work
        // without a key, a download, or a network connection.
        ProviderStage.transcription =>
          values.where((k) => k.stages.contains(stage)).toList(),
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
    this._keys,
    SettingsStore settings, {
    WhisperEngine? whisperEngine,
    GemmaEngine? gemmaEngine,
    LiveTranscriptionSource Function()? liveSource,
  })  : _whisperEngine = whisperEngine ?? NativeWhisperEngine(),
        _gemmaEngine = gemmaEngine ?? OnDeviceGemmaEngine(settings),
        _liveSource = liveSource ?? OnDeviceSpeechSource.new;

  final HttpTransport _transport;
  final KeyStore _keys;
  final WhisperEngine _whisperEngine;
  final GemmaEngine _gemmaEngine;

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
      ProviderKind.gemmaOnDevice =>
        GemmaStructuringProvider(engine: _gemmaEngine),
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

final gemmaEngineProvider = Provider<OnDeviceGemmaEngine>(
  (ref) => OnDeviceGemmaEngine(ref.watch(settingsStoreProvider)),
);

final providerFactoryProvider = Provider<ProviderFactory>(
  (ref) => ProviderFactory(
    ref.watch(transportProvider),
    ref.watch(keyStoreProvider),
    ref.watch(settingsStoreProvider),
    gemmaEngine: ref.watch(gemmaEngineProvider),
  ),
);

enum ReleaseChannel {
  stable('Stable', 'Conservative releases'),
  beta('Beta', 'Early features and model updates');

  const ReleaseChannel(this.label, this.description);
  final String label;
  final String description;
}

final settingsRevisionProvider = StateProvider<int>((ref) => 0);

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
  static const _kWorkflowPrefix = 'workflow.';
  static const _kTemplateId = 'workflow.templateId';
  static const _kHighContrast = 'accessibility.highContrast';
  static const _kLargeText = 'accessibility.largeText';
  static const _kTextScale = 'accessibility.textScale';
  static const _kReleaseChannel = 'updates.releaseChannel';
  static const _kAutoDeleteAudio = 'privacy.autoDeleteSourceAudio';
  static const _kMaxRecordingMinutes = 'capture.maxRecordingMinutes';
  static const _kAutoPauseSilenceSeconds = 'capture.autoPauseSilenceSeconds';
  static const _kAutoDetectLanguage = 'transcription.autoDetectLanguage';
  static const _kPreRecordingChecklist = 'capture.preRecordingChecklist';
  static const _kScheduledRecording = 'capture.scheduledRecording';
  static const _kWatchFolder = 'desktop.watchFolder';
  static const _kWebhookUrl = 'export.webhookUrl';
  static const _kNotionDatabaseId = 'export.notionDatabaseId';

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

  bool workflowEnabled(String key, {bool defaultValue = true}) =>
      _prefs.getBool('$_kWorkflowPrefix$key') ?? defaultValue;

  Future<void> setWorkflowEnabled(String key, bool enabled) =>
      _prefs.setBool('$_kWorkflowPrefix$key', enabled);

  String? get activeTemplateId => _prefs.getString(_kTemplateId);

  Future<void> setActiveTemplateId(String? id) => id == null
      ? _prefs.remove(_kTemplateId)
      : _prefs.setString(_kTemplateId, id);

  bool get highContrast => _prefs.getBool(_kHighContrast) ?? false;
  Future<void> setHighContrast(bool value) =>
      _prefs.setBool(_kHighContrast, value);

  bool get largeText => _prefs.getBool(_kLargeText) ?? false;
  Future<void> setLargeText(bool value) => _prefs.setBool(_kLargeText, value);

  double get textScale => _prefs.getDouble(_kTextScale) ?? 1.0;
  Future<void> setTextScale(double value) =>
      _prefs.setDouble(_kTextScale, value.clamp(0.85, 1.6));

  ReleaseChannel get releaseChannel => ReleaseChannel.values.firstWhere(
        (channel) => channel.name == _prefs.getString(_kReleaseChannel),
        orElse: () => ReleaseChannel.stable,
      );

  Future<void> setReleaseChannel(ReleaseChannel value) =>
      _prefs.setString(_kReleaseChannel, value.name);

  bool get autoDeleteSourceAudio => _prefs.getBool(_kAutoDeleteAudio) ?? false;

  Future<void> setAutoDeleteSourceAudio(bool enabled) =>
      _prefs.setBool(_kAutoDeleteAudio, enabled);

  int get maxRecordingMinutes => _prefs.getInt(_kMaxRecordingMinutes) ?? 0;

  Future<void> setMaxRecordingMinutes(int minutes) =>
      _prefs.setInt(_kMaxRecordingMinutes, minutes.clamp(0, 480));

  int get autoPauseSilenceSeconds =>
      _prefs.getInt(_kAutoPauseSilenceSeconds) ?? 0;

  Future<void> setAutoPauseSilenceSeconds(int seconds) =>
      _prefs.setInt(_kAutoPauseSilenceSeconds, seconds.clamp(0, 300));

  bool get preRecordingChecklist =>
      _prefs.getBool(_kPreRecordingChecklist) ?? true;

  Future<void> setPreRecordingChecklist(bool enabled) =>
      _prefs.setBool(_kPreRecordingChecklist, enabled);

  DateTime? get scheduledRecording => DateTime.tryParse(
        _prefs.getString(_kScheduledRecording) ?? '',
      );

  Future<void> setScheduledRecording(DateTime? value) => value == null
      ? _prefs.remove(_kScheduledRecording)
      : _prefs.setString(_kScheduledRecording, value.toIso8601String());

  String? get watchFolderPath => _prefs.getString(_kWatchFolder);

  Future<void> setWatchFolderPath(String? path) => path == null
      ? _prefs.remove(_kWatchFolder)
      : _prefs.setString(_kWatchFolder, path);

  String get webhookUrl => _prefs.getString(_kWebhookUrl) ?? '';

  Future<void> setWebhookUrl(String url) =>
      _prefs.setString(_kWebhookUrl, url.trim());

  String get notionDatabaseId => _prefs.getString(_kNotionDatabaseId) ?? '';

  Future<void> setNotionDatabaseId(String id) =>
      _prefs.setString(_kNotionDatabaseId, id.trim());

  static const _kGemmaFileName = 'gemma.modelFileName';
  static const _kGemmaFamily = 'gemma.modelFamily';
  static const _kGemmaContextWindow = 'gemma.contextWindowTokens';

  /// The file name `flutter_gemma` tracks the installed model under, or null if none
  /// has been picked yet.
  String? get gemmaModelFileName => _prefs.getString(_kGemmaFileName);

  /// The `GemmaFamily` name the file was installed with — needed again on every app
  /// launch, since the chat template routing is chosen at install time, not read back
  /// from the file.
  String? get gemmaModelFamily => _prefs.getString(_kGemmaFamily);

  int get gemmaContextWindowTokens =>
      _prefs.getInt(_kGemmaContextWindow) ?? 2048;

  Future<void> setGemmaModel({
    required String fileName,
    required String family,
    required int contextWindowTokens,
  }) async {
    await _prefs.setString(_kGemmaFileName, fileName);
    await _prefs.setString(_kGemmaFamily, family);
    await _prefs.setInt(_kGemmaContextWindow, contextWindowTokens);
  }

  Future<void> clearGemmaModel() async {
    await _prefs.remove(_kGemmaFileName);
    await _prefs.remove(_kGemmaFamily);
    await _prefs.remove(_kGemmaContextWindow);
  }

  static const _kSavedBoardViews = 'workflow.savedBoardViews';

  Map<String, Map<String, dynamic>> get savedBoardViews {
    final raw = _prefs.getString(_kSavedBoardViews);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          '${entry.key}': Map<String, dynamic>.from(entry.value as Map),
      };
    } on Object {
      return const {};
    }
  }

  Future<void> saveBoardView(String name, Map<String, dynamic> filter) async {
    final views = {
      ...savedBoardViews,
      name: filter,
    };
    await _prefs.setString(_kSavedBoardViews, jsonEncode(views));
  }

  String get transcriptionLanguage =>
      _prefs.getString('${_kWorkflowPrefix}language') ?? 'en-US';

  Future<void> setTranscriptionLanguage(String language) =>
      _prefs.setString('${_kWorkflowPrefix}language', language.trim());

  bool get autoDetectLanguage => _prefs.getBool(_kAutoDetectLanguage) ?? true;

  Future<void> setAutoDetectLanguage(bool enabled) =>
      _prefs.setBool(_kAutoDetectLanguage, enabled);

  String get customVocabulary =>
      _prefs.getString('${_kWorkflowPrefix}vocabulary') ?? '';

  Future<void> setCustomVocabulary(String vocabulary) =>
      _prefs.setString('${_kWorkflowPrefix}vocabulary', vocabulary.trim());

  int get flashcardLimit =>
      _prefs.getInt('${_kWorkflowPrefix}flashcardLimit') ?? 20;

  Future<void> setFlashcardLimit(int limit) =>
      _prefs.setInt('${_kWorkflowPrefix}flashcardLimit', limit.clamp(0, 20));

  int get quizLimit => _prefs.getInt('${_kWorkflowPrefix}quizLimit') ?? 20;

  Future<void> setQuizLimit(int limit) =>
      _prefs.setInt('${_kWorkflowPrefix}quizLimit', limit.clamp(0, 20));

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
