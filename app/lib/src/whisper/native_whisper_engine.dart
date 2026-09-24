import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:transcript_core/transcript_core.dart';
import 'package:transcript_whisper_native/transcript_whisper_native.dart'
    as native;

import 'file_model_store.dart';

/// The real [WhisperEngine]: decodes with the vendored ggml/whisper.cpp
/// library via `dart:ffi` (see `packages/transcript_whisper_native`).
///
/// [WhisperTranscriptionProvider] only ever hands this raw 16 kHz mono PCM16
/// bytes — the native decoder reads a WAV file, so each call writes a
/// throwaway WAV into the app's cache directory (reusing
/// `transcript_core`'s own WAV builder, the same format its recorder
/// produces) and deletes it once decoding finishes, win or lose.
class NativeWhisperEngine implements WhisperEngine {
  NativeWhisperEngine({FileModelStore? modelStore, int threads = 0})
      : _modelStore = modelStore ?? FileModelStore(),
        _threads = threads;

  final FileModelStore _modelStore;

  /// 0 means work it out from the machine.
  final int _threads;

  /// How many threads to decode with.
  ///
  /// The native default is 4 whatever the device is, which leaves half an eight-core
  /// phone and most of a desktop idle during the slowest thing this app does locally.
  ///
  /// One core is left free so the UI still draws and the recorder still writes — a
  /// transcription that finishes fractionally sooner having frozen the app is not
  /// faster from where the user sits. The cap is because whisper.cpp stops scaling
  /// somewhere around eight threads on the model sizes this ships, and past that the
  /// extra threads mostly generate heat.
  int get threads {
    if (_threads > 0) return _threads;
    return (Platform.numberOfProcessors - 1).clamp(2, 8);
  }

  @override
  Future<bool> isModelReady(String modelId) => _modelStore.isComplete(modelId);

  @override
  Future<String?> modelPath(String modelId) =>
      _modelStore.completedPath(modelId);

  @override
  Future<List<TranscriptSegment>> transcribe({
    required String modelPath,
    required List<int> pcm16,
    String? languageHint,
  }) async {
    final wavFile = await _writeTempWav(pcm16);
    try {
      final segments = await native.transcribeWav(
        modelPath: modelPath,
        wavPath: wavFile.path,
        languageHint: languageHint,
        threads: threads,
      );
      return segments
          .map(
            (s) => TranscriptSegment(
              startMs: s.startMs,
              endMs: s.endMs,
              text: s.text,
            ),
          )
          .toList(growable: false);
    } on native.WhisperNativeException catch (e) {
      throw StateError('Offline transcription failed: ${e.message}');
    } finally {
      if (wavFile.existsSync()) {
        await wavFile.delete();
      }
    }
  }

  Future<File> _writeTempWav(List<int> pcm16) async {
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'whisper-chunk-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final wav = buildWav(
      pcm: pcm16,
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
    );
    final file = File(path);
    await file.writeAsBytes(wav, flush: true);
    return file;
  }
}
