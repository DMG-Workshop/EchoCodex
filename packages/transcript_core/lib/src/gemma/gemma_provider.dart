import 'dart:convert';

import '../providers/capabilities.dart';
import '../providers/connection.dart';
import '../providers/provider.dart';
import '../schema/dialects.dart';

/// What the app knows about the on-device model currently loaded, without knowing
/// anything about how it was loaded — that part is native and lives behind
/// [GemmaEngine].
class GemmaModelInfo {
  const GemmaModelInfo({required this.label, this.contextWindowTokens = 0});

  /// Shown in settings and connection results — usually the model's file name.
  final String label;

  /// Zero means unknown, same convention as the rest of the capability model: the
  /// pipeline falls back to conservative map/reduce chunking rather than guessing.
  final int contextWindowTokens;
}

/// The native side of an on-device LLM (Gemma, or anything else the engine can load).
///
/// The actual work — loading a `.litertlm`/`.task` bundle and running inference —
/// happens through a native runtime reached over FFI or a platform channel, which
/// cannot run in a pure-Dart environment. Keeping it behind this seam means the
/// provider, its capability reporting and its error handling are all testable with a
/// fake, exactly as [WhisperEngine] does for the transcription side.
abstract class GemmaEngine {
  /// Info about the model currently installed and selected, or null if none is ready.
  Future<GemmaModelInfo?> currentModel();

  /// The configured model's context window, read synchronously so
  /// [GemmaStructuringProvider.capabilities] can report it without an async round trip
  /// — the pipeline reads capabilities before the first [generate] call, to decide
  /// single-pass vs. map/reduce chunking. Zero means unknown, same convention as
  /// [GemmaModelInfo.contextWindowTokens]: the pipeline then falls back to a
  /// conservative assumed window rather than guessing too high and truncating.
  int get contextWindowTokens => 0;

  /// Runs one structuring turn against the currently loaded model. Callers must not
  /// call this without first confirming [currentModel] is non-null.
  ///
  /// [priorTurns] replays earlier user/assistant messages onto the (otherwise fresh)
  /// chat before [userContent] — the repair loop's follow-up turns, most often. Without
  /// this a "retry" would just re-ask the original question with no memory of what was
  /// wrong with the last answer, since each call starts a new chat.
  Future<String> generate({
    required String systemPrompt,
    required String userContent,
    List<StructureTurn> priorTurns = const [],
    int maxOutputTokens = 2048,
  });
}

/// A fully offline structuring provider backed by a model file the user supplied
/// themselves (Gemma or another chat model in `.litertlm`/`.task` form).
///
/// Unlike the cloud adapters, this model has no first-class structured-output mode —
/// `flutter_gemma` has nothing equivalent to an API's `response_format`/`responseSchema`
/// parameter, so [ProviderCapabilities.nativeJsonSchema] is false and [structure] embeds
/// the schema as text in the prompt itself, then leans on the pipeline's tolerant parse
/// + repair loop to recover from whatever the model gets wrong.
class GemmaStructuringProvider extends StructuringProvider {
  GemmaStructuringProvider({required GemmaEngine engine}) : _engine = engine;

  final GemmaEngine _engine;

  @override
  ProviderId get id => const ProviderId('gemma-on-device');

  @override
  String get displayName => 'Gemma (on-device)';

  @override
  bool get isLocalEndpoint => true;

  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
        acceptsAudio: false,
        acceptsText: true,
        nativeJsonSchema: false,
        requiresApiKey: false,
        runsOnDevice: true,
        maxOutputTokens: 2048,
        contextWindowTokens: _engine.contextWindowTokens,
      );

  @override
  Future<ConnectionResult> test() async {
    final model = await _engine.currentModel();
    if (model == null) {
      return ConnectionResult.failure(
        summary: 'No on-device model is loaded yet',
        remedy:
            'Pick a downloaded .litertlm file in settings — Gemma models are '
            'available from Hugging Face (litert-community) or Kaggle.',
      );
    }
    return ConnectionResult.success(
      summary: 'Ready · ${model.label} · fully offline',
    );
  }

  @override
  Future<StructureResponse> structure(StructureRequest request) async {
    final model = await _engine.currentModel();
    if (model == null) {
      throw StateError(
        'No on-device Gemma model is loaded. This should have been caught before '
        'structuring started.',
      );
    }
    // Unlike the HTTP adapters, there is no API-level schema parameter to attach this
    // to — flutter_gemma has nothing equivalent to `response_format`/`responseSchema`.
    // The system prompt says "the schema you have been given"; without this, it never
    // actually was.
    final systemPrompt = '${request.systemPrompt}\n\n'
        'SCHEMA — the NoteDocument JSON Schema referenced above. Conform to it exactly: '
        'every property it requires must be present, and no other properties may be '
        'added.\n'
        '${jsonEncode(renderSchema(request.schema, SchemaDialect.plain))}';
    final text = await _engine.generate(
      systemPrompt: systemPrompt,
      userContent: request.userContent,
      priorTurns: request.priorTurns,
      maxOutputTokens: request.maxOutputTokens,
    );
    return StructureResponse(rawText: text, model: model.label);
  }
}
