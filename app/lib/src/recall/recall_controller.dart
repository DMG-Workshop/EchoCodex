import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transcript_core/transcript_core.dart';

import '../data/database.dart' as db;
import '../data/repository.dart';
import '../recording/recording_controller.dart';
import '../settings/provider_config.dart';
import 'recall_providers.dart';

/// Builds the embedding provider from the endpoint already configured for notes.
///
/// Null when there is nothing to build on: no endpoint, or no embedding model named.
/// Recall is the one stage with no sensible default — a chat model cannot embed — so
/// "not set up" is a normal state the UI has to be able to describe, not an error.
final embeddingProviderProvider = Provider<EndpointEmbeddingProvider?>((ref) {
  final settings = ref.watch(settingsStoreProvider);
  final model = settings.embeddingModel;
  if (model.isEmpty) return null;

  final kind = settings.kindFor(ProviderStage.structuring);
  if (kind == null || !kind.needsEndpoint) return null;
  final endpoint = (settings.endpointFor(kind) ?? '').trim();
  if (endpoint.isEmpty) return null;

  final base = Uri.tryParse(endpoint);
  if (base == null || !base.hasScheme) return null;

  return EndpointEmbeddingProvider(
    transport: ref.watch(transportProvider),
    baseUrl: base,
    model: model,
    native: kind == ProviderKind.ollama,
  );
});

/// What the ask screen is doing.
sealed class RecallState {
  const RecallState();
}

class RecallIdle extends RecallState {
  const RecallIdle();
}

class RecallIndexing extends RecallState {
  const RecallIndexing(this.done, this.total);
  final int done;
  final int total;
}

class RecallThinking extends RecallState {
  const RecallThinking();
}

class RecallAnswered extends RecallState {
  const RecallAnswered(this.question, this.answer);
  final String question;
  final RecallAnswer answer;
}

class RecallFailed extends RecallState {
  const RecallFailed(this.message, {this.remedy});
  final String message;
  final String? remedy;
}

/// Indexes recordings and answers questions over them.
class RecallController extends StateNotifier<RecallState> {
  RecallController({
    required RecordingRepository repository,
    required EndpointEmbeddingProvider? embeddings,
    required Future<StructuringProvider?> Function() answering,
    this.chunker = const RecallChunker(),
    this.index = const RecallIndex(),
  })  : _repository = repository,
        _embeddings = embeddings,
        _answering = answering,
        super(const RecallIdle());

  final RecordingRepository _repository;
  final EndpointEmbeddingProvider? _embeddings;

  /// Resolved when a question is asked rather than held: building a structuring
  /// provider reads the key store, which is async, and a screen should not be blocked
  /// on that before anyone has typed anything.
  final Future<StructuringProvider?> Function() _answering;
  final RecallChunker chunker;
  final RecallIndex index;

  bool get hasEmbeddings => _embeddings != null;

  /// Indexes every recording that has a transcript.
  ///
  /// Explicit rather than automatic: embedding a back catalogue is minutes of work on
  /// someone's own hardware, and starting it unasked the first time this screen opens
  /// would be a surprise on a laptop and a rude one on a phone.
  Future<void> indexAll({bool force = false}) async {
    final embeddings = _embeddings;
    if (embeddings == null) {
      state = const RecallFailed(
        'Recall is not set up yet.',
        remedy: 'Name an embedding model in Settings → Workflow features.',
      );
      return;
    }

    try {
      if (force) await _repository.clearRecallIndex();
      final recordings = (await _repository.all())
          .where((r) => r.transcriptText != null)
          .toList();

      state = RecallIndexing(0, recordings.length);
      for (var i = 0; i < recordings.length; i++) {
        await _indexOne(recordings[i], embeddings);
        state = RecallIndexing(i + 1, recordings.length);
      }
      state = const RecallIdle();
    } on ProviderException catch (e) {
      state = RecallFailed('Indexing stopped: ${e.message}');
    } catch (e) {
      state = RecallFailed('Indexing stopped: $e');
    }
  }

  Future<void> _indexOne(
    db.Recording recording,
    EndpointEmbeddingProvider embeddings,
  ) async {
    final source = RecallSource(
      recordingId: recording.id,
      recordingTitle:
          recording.title.isEmpty ? 'Untitled recording' : recording.title,
      recordedOn: _isoDay(recording.startedAt),
    );

    final chunks = <RecallChunk>[
      ...chunker.fromTranscript(
        _transcriptOf(recording),
        source,
      ),
      if (decodeNote(recording) case final note?)
        ...chunker.fromNote(note, source),
    ];
    if (chunks.isEmpty) return;

    final vectors = await embeddings.embed([for (final c in chunks) c.text]);
    await _repository.saveRecallChunks(
      recording.id,
      [
        for (var i = 0; i < chunks.length; i++)
          EmbeddedChunk(chunk: chunks[i], vector: vectors[i]),
      ],
      embeddingModel: embeddings.model,
    );
  }

  /// Answers [question] from what is indexed.
  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    final embeddings = _embeddings;
    if (embeddings == null) {
      state = const RecallFailed(
        'Recall is not set up yet.',
        remedy: 'Name an embedding model in Settings → Workflow features.',
      );
      return;
    }

    state = const RecallThinking();
    try {
      final answering = await _answering();
      if (answering == null) {
        state = const RecallFailed(
          'No service is set up to write the answer.',
          remedy: 'Choose a notes service in Settings first.',
        );
        return;
      }

      final queryVector = (await embeddings.embed([trimmed])).single;
      final corpus = await _repository.recallCorpus(
        dimensions: queryVector.length,
        embeddingModel: embeddings.model,
      );

      if (corpus.isEmpty) {
        state = const RecallFailed(
          'Nothing is indexed yet for this embedding model.',
          remedy: 'Index your recordings, then ask again.',
        );
        return;
      }

      final hits = index.search(queryVector, corpus);
      if (hits.isEmpty) {
        // Not a failure: the corpus genuinely has nothing close. Saying so beats
        // sending the model the nearest unrelated paragraph and letting it improvise.
        state = RecallAnswered(
          trimmed,
          const RecallAnswer(
            text: 'Nothing in your recordings comes close to that.',
            citations: [],
            hadEvidence: false,
          ),
        );
        return;
      }

      const prompts = RecallPrompts();
      final response = await answering.structure(StructureRequest(
        systemPrompt: RecallPrompts.system,
        userContent: prompts.user(trimmed, hits),
        // Recall wants prose with citations, not a NoteDocument. An empty schema keeps
        // the adapters from constraining the reply to JSON.
        schema: const {},
        maxOutputTokens: 1200,
      ));

      state = RecallAnswered(trimmed, prompts.verify(response.rawText, hits));
    } on ProviderException catch (e) {
      state = RecallFailed('That question could not be answered: ${e.message}');
    } catch (e) {
      state = RecallFailed('That question could not be answered: $e');
    }
  }

  void reset() => state = const RecallIdle();

  static Transcript _transcriptOf(db.Recording recording) {
    final raw = recording.transcriptSegmentsJson;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return Transcript([
            for (final item in decoded)
              if (item is Map<String, dynamic>)
                TranscriptSegment(
                  startMs: (item['startMs'] as num?)?.toInt() ?? 0,
                  endMs: (item['endMs'] as num?)?.toInt() ?? 0,
                  text: '${item['text'] ?? ''}',
                  speaker: item['speaker'] as String?,
                ),
          ]);
        }
      } on FormatException {
        // Fall through to the plain text below rather than losing the recording.
      }
    }
    // No segments: one segment covering the whole thing. It loses the offsets, so the
    // chunks cite a recording rather than a moment — still checkable, just coarser.
    final text = recording.transcriptText ?? '';
    return text.isEmpty
        ? const Transcript([])
        : Transcript([
            TranscriptSegment(
                startMs: 0, endMs: recording.durationMs, text: text),
          ]);
  }

  static String _isoDay(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';
}

final recallControllerProvider =
    StateNotifierProvider<RecallController, RecallState>((ref) {
  return RecallController(
    repository: ref.watch(repositoryProvider),
    embeddings: ref.watch(embeddingProviderProvider),
    answering: () => resolveAnsweringProvider(ref),
  );
});

/// The model that writes the answer — the same one that writes the notes.
///
/// Recall does not get its own provider choice. A user who has configured one service
/// to read their meetings has not asked to configure a second to talk about them.
Future<StructuringProvider?> resolveAnsweringProvider(Ref ref) async {
  final settings = ref.read(settingsStoreProvider);
  final kind = settings.kindFor(ProviderStage.structuring);
  if (kind == null) return null;
  return ref.read(providerFactoryProvider).structuring(
        ProviderSelection(
          kind: kind,
          model: settings.modelFor(kind),
          endpoint: settings.endpointFor(kind),
        ),
      );
}

/// How much of the library is indexed.
final recallCoverageProvider = FutureProvider<(int, int)>(
  (ref) => ref.watch(repositoryProvider).recallCoverage(),
);
