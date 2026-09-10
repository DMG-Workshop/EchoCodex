import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:transcript_core/transcript_core.dart';

import '../settings/provider_config.dart';

/// Which chat template a model file expects. `.litertlm` bundles carry their own
/// template metadata for most families, but `flutter_gemma` still needs to know the
/// family up front to route tool-call tokens and thinking blocks correctly.
enum GemmaFamily {
  gemma4('Gemma 4 (E2B / E4B)'),
  gemma3('Gemma 3 / Gemma3n'),
  qwen3('Qwen 3'),
  general('Other on-device model');

  const GemmaFamily(this.label);
  final String label;

  ModelType get modelType => switch (this) {
        GemmaFamily.gemma4 => ModelType.gemma4,
        GemmaFamily.gemma3 => ModelType.gemmaIt,
        GemmaFamily.qwen3 => ModelType.qwen3,
        GemmaFamily.general => ModelType.general,
      };
}

/// The real [GemmaEngine]: runs a `.litertlm` file the user already has on disk
/// through Google's LiteRT-LM runtime via `package:flutter_gemma`.
///
/// Whisper's offline path downloads its own model because the files are small and
/// unauthenticated. Usable Gemma bundles are hundreds of megabytes to several
/// gigabytes and the good ones are gated behind a Hugging Face login, so this engine
/// does not attempt its own download — it registers a file the user already fetched
/// themselves, the same "off-grid AI" pattern apps like it use.
class OnDeviceGemmaEngine implements GemmaEngine {
  OnDeviceGemmaEngine(this._settings);

  final SettingsStore _settings;

  /// Registers [path] as the active on-device model. The file is referenced in place,
  /// not copied — LiteRT-LM bundles are too large to duplicate into app storage.
  ///
  /// Also loads the model once to confirm it actually runs on this device before
  /// committing to it: `install()` alone only registers the file, it doesn't try to
  /// build an inference engine from it, so a backend-restricted or corrupt bundle
  /// would otherwise look "installed" here and only fail the next time a recording
  /// gets structured. Failing loudly now, with the file rolled back, means the error
  /// shows up next to the file picker instead of after a recording.
  Future<void> install({
    required String path,
    required GemmaFamily family,
    int contextWindowTokens = 2048,
  }) async {
    final fileName = path.split('/').last;
    await FlutterGemma.installModel(
      modelType: family.modelType,
      fileType: ModelFileType.litertlm,
    ).fromFile(path).install();
    _model = null;
    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: contextWindowTokens,
      );
    } catch (error) {
      await FlutterGemma.uninstallModel(fileName);
      await FlutterGemma.clearActiveInferenceIdentity();
      throw _friendlierLoadError(error, fileName: fileName);
    }
    await _settings.setGemmaModel(
      fileName: fileName,
      family: family.name,
      contextWindowTokens: contextWindowTokens,
    );
  }

  Future<void> uninstall() async {
    final fileName = _settings.gemmaModelFileName;
    if (fileName != null) {
      await FlutterGemma.uninstallModel(fileName);
      await FlutterGemma.clearActiveInferenceIdentity();
    }
    _model = null;
    await _settings.clearGemmaModel();
  }

  @override
  Future<GemmaModelInfo?> currentModel() async {
    final fileName = _settings.gemmaModelFileName;
    if (fileName == null) return null;
    if (!await FlutterGemma.isModelInstalled(fileName)) return null;
    return GemmaModelInfo(
      label: fileName,
      contextWindowTokens: _settings.gemmaContextWindowTokens,
    );
  }

  @override
  int get contextWindowTokens => _settings.gemmaContextWindowTokens;

  InferenceModel? _model;

  Future<InferenceModel> _activeModel() async {
    if (_model != null) return _model!;
    try {
      return _model = await FlutterGemma.getActiveModel(
        maxTokens: _settings.gemmaContextWindowTokens,
      );
    } catch (error) {
      throw _friendlierLoadError(error, fileName: _settings.gemmaModelFileName);
    }
  }

  @override
  Future<String> generate({
    required String systemPrompt,
    required String userContent,
    int maxOutputTokens = 2048,
  }) async {
    final model = await _activeModel();
    // A fresh chat per call: a recording's transcript is a one-shot structuring job,
    // not a conversation, and reusing a chat would leak one note's transcript into the
    // next note's context.
    final chat = await model.createChat(
      systemInstruction: systemPrompt,
      maxOutputTokens: maxOutputTokens,
    );
    await chat.addQueryChunk(Message.text(text: userContent, isUser: true));
    final response = await chat.generateChatResponse();
    return switch (response) {
      TextResponse(:final token) => token,
      ThinkingResponse(:final content) => content,
      FunctionCallResponse() || ParallelFunctionCallResponse() =>
        throw StateError(
          'The on-device model returned a function call instead of text.',
        ),
    };
  }
}

/// Turns `flutter_gemma_litertlm`'s native engine-load failure into something a user
/// can act on. That package doesn't export `BackendInitException` — it's an FFI
/// implementation detail — so this matches its `toString()` shape rather than the
/// type; anything else passes through unchanged.
Exception _friendlierLoadError(Object error, {String? fileName}) {
  final detail = error.toString();
  if (!detail.contains('BackendInitException')) {
    return error is Exception ? error : Exception(detail);
  }
  final model = fileName == null ? 'This model' : '"$fileName"';
  return Exception(
    '$model failed to load on this device — both the GPU and CPU backends were '
    'tried and neither could start. This usually means the download was '
    "incomplete or corrupted, or the file is a GPU-only build this device's "
    'driver cannot run. Re-download the .litertlm file, or try a CPU/base '
    'variant if the source publishes one.\n\n$detail',
  );
}
