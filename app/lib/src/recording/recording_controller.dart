import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transcript_core/transcript_core.dart';

import '../data/chunk_store.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../settings/provider_config.dart';
import 'audio_import.dart';
import 'background_audio.dart';
import 'interruption_policy.dart';
import 'on_device_stt.dart';
import 'recorder_service.dart';

/// What the record screen is showing.
sealed class RecordState {
  const RecordState();
}

class RecordIdle extends RecordState {
  const RecordIdle();
}

class RecordActive extends RecordState {
  const RecordActive({
    required this.elapsed,
    this.liveText = '',
    this.interrupted = false,
    this.interruptionReason,
  });

  final Duration elapsed;
  final String liveText;

  /// The OS took the microphone. Recording is still open and will resume.
  final bool interrupted;
  final String? interruptionReason;
}

class RecordProcessing extends RecordState {
  const RecordProcessing({required this.label, this.fraction});
  final String label;
  final double? fraction;
}

class RecordDone extends RecordState {
  const RecordDone(this.recordingId, {this.warning});
  final String recordingId;
  final String? warning;
}

class RecordError extends RecordState {
  const RecordError(this.message, {this.remedy, this.recordingId});
  final String message;
  final String? remedy;
  final String? recordingId;
}

/// Drives one recording from tapping record to a stored note, and picks up anything the
/// OS interrupted along the way.
class RecordingController extends StateNotifier<RecordState> {
  RecordingController({
    required RecorderService recorder,
    required RecordingRepository repository,
    required ProviderFactory factory,
    required SettingsStore settings,
    required TranscriptDatabase database,
    required BackgroundAudio background,
    AudioImportService importer = const AudioImportService(),
    this.interruptions = const InterruptionPolicy(),
  })  : _recorder = recorder,
        _repository = repository,
        _factory = factory,
        _settings = settings,
        _db = database,
        _background = background,
        _importer = importer,
        super(const RecordIdle());

  final RecorderService _recorder;
  final RecordingRepository _repository;
  final ProviderFactory _factory;
  final SettingsStore _settings;
  final TranscriptDatabase _db;
  final BackgroundAudio _background;
  final AudioImportService _importer;
  final InterruptionPolicy interruptions;

  LiveTranscriptionAdapter? _live;
  StreamSubscription<AudioInterruption>? _interruptionSub;
  Timer? _ticker;
  String _liveText = '';
  bool _paused = false;

  final List<InterruptionWindow> _windows = [];

  /// Set when a recording just started fell back from the configured folder to the
  /// device's own storage, so [stopAndProcess] can tell the user once it is done.
  String? _storageWarning;

  /// Gaps the recorder knows about but the queue never will: stretches where the
  /// microphone belonged to another app.
  List<TranscriptGap> get interruptionGaps => [
        for (final w in _windows)
          if (!w.isOpen) TranscriptGap(w.startMs, w.endMs!, w.label),
      ];

  Future<void> startRecording() async {
    try {
      await _background.prepare();
      await _recorder.start(recordingsDirPath: _settings.recordingsDirPath);
      await _background.startForeground(title: 'Recording');
    } on RecorderException catch (e) {
      state = RecordError(e.message, remedy: e.remedy);
      return;
    }

    _storageWarning = _recorder.takeFallbackWarning();
    _liveText = '';
    _paused = false;
    _windows.clear();
    _interruptionSub = _background.interruptions.listen(_onInterruption);

    final transcriptionKind = _settings.kindFor(ProviderStage.transcription) ??
        SettingsStore.defaultTranscription;

    if (transcriptionKind == ProviderKind.onDeviceStt) {
      final adapter = LiveTranscriptionAdapter(OnDeviceSpeechSource());
      _live = adapter;
      adapter.source.segments.listen((segment) {
        _liveText = '$_liveText ${segment.text}'.trim();
      });
      try {
        await adapter.startListening(languageHint: _languageHint);
      } catch (e) {
        _live = null;
        await _teardown();
        await _recorder.cancel();
        state = RecordError(
          'On-device speech recognition could not start.',
          remedy: e.toString(),
        );
        return;
      }
    }

    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (state is RecordActive || state is RecordIdle) {
        final open = _windows.where((w) => w.isOpen).firstOrNull;
        state = RecordActive(
          elapsed: _recorder.elapsed,
          liveText: _liveText,
          interrupted: open != null,
          interruptionReason: open?.label,
        );
      }
    });
    state = RecordActive(elapsed: Duration.zero);
  }

  /// Translates an OS event into an action, then performs it.
  ///
  /// The decision lives in [InterruptionPolicy] rather than here, so the awkward orders
  /// platform callbacks arrive in are settled once and tested.
  Future<void> _onInterruption(AudioInterruption event) async {
    final action = interruptions.decide(
      event,
      isRecording: _recorder.isRecording && !_paused,
      isPaused: _paused,
    );

    switch (action) {
      case InterruptionAction.pause:
        _paused = true;
        _windows.add(InterruptionWindow(
          startMs: _recorder.elapsed.inMilliseconds,
          cause: event,
        ));
        await _recorder.pause();
      case InterruptionAction.resume:
        _paused = false;
        final open = _windows.lastIndexWhere((w) => w.isOpen);
        if (open >= 0) {
          _windows[open] =
              _windows[open].closedAt(_recorder.elapsed.inMilliseconds);
        }
        await _recorder.resume();
      case InterruptionAction.finalize:
        _closeOpenWindow();
        await stopAndProcess();
      case InterruptionAction.ignore:
        break;
    }
  }

  void _closeOpenWindow() {
    final open = _windows.lastIndexWhere((w) => w.isOpen);
    if (open >= 0) {
      _windows[open] =
          _windows[open].closedAt(_recorder.elapsed.inMilliseconds);
    }
  }

  Future<void> cancelRecording() async {
    await _teardown();
    await _recorder.cancel();
    state = const RecordIdle();
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    await _background.stopForeground();
  }

  /// Stops, persists, then runs the durable pipeline.
  Future<void> stopAndProcess() async {
    await _teardown();
    _closeOpenWindow();

    final captured = await _recorder.stop();
    final liveTranscript = await _live?.stopListening();
    final live = _live;
    _live = null;

    if (captured == null) {
      state = const RecordError('Nothing was recorded.');
      return;
    }

    state = const RecordProcessing(label: 'Preparing');

    final providers = await _resolveProviders(live);
    if (providers == null) return; // state already set to an error

    final recordingId = await _repository.createRecording(
      path: captured.path,
      duration: captured.duration,
      transcriptionProviderId: providers.transcription.id.value,
      structuringProviderId: providers.structuring.id.value,
    );

    if (liveTranscript != null) {
      await _repository.saveTranscript(
        recordingId,
        liveTranscript,
        cleaned: _cleanedTranscript(liveTranscript),
      );
    }

    await _consume(
      _pipelineFor(providers, captured.path).start(
        recordingId: recordingId,
        totalDurationMs: captured.duration.inMilliseconds,
        silences: captured.silences,
        referenceDate: _isoDate(DateTime.now()),
        timeZone: DateTime.now().timeZoneName,
        userContext: _settings.customVocabulary.isEmpty
            ? null
            : 'Custom vocabulary: ${_settings.customVocabulary}',
        additionalGaps: interruptionGaps,
        keyConceptsEnabled: _settings.workflowEnabled('smartSummaries'),
        flashcardLimit: _flashcardLimit,
        quizLimit: _quizLimit,
      ),
      recordingId,
    );
  }

  /// Brings in a file recorded somewhere else — a Zoom or Teams export, a lecture, a
  /// voice memo — and runs it through the same pipeline a live recording uses.
  ///
  /// This is also the honest answer to "record my meetings": no app on either platform
  /// can capture another app's call audio, but every conferencing tool can export the
  /// recording afterwards, and that file lands here.
  Future<void> importRecording(String sourcePath) async {
    final format = ImportFormat.forPath(sourcePath);
    if (format == null) {
      state = RecordError(
        'That file type cannot be imported.',
        remedy: 'Supported: ${ImportFormat.values.map((f) => f.label).join(', ')}.',
      );
      return;
    }

    final enabled = format.isVideo
        ? _settings.workflowEnabled('videoImport')
        : _settings.workflowEnabled('audioImport');
    if (!enabled) {
      state = RecordError(
        '${format.isVideo ? 'Video' : 'Audio'} import is turned off.',
        remedy: 'Turn it back on in Settings, under Workflow features.',
      );
      return;
    }

    // On-device recognition listens to the microphone; it cannot be handed a file. Say
    // so specifically rather than through the generic "nothing configured" branch — the
    // fix is one setting away, and Whisper offline needs no key either.
    final transcriptionKind = _settings.kindFor(ProviderStage.transcription) ??
        SettingsStore.defaultTranscription;
    if (transcriptionKind == ProviderKind.onDeviceStt) {
      state = const RecordError(
        'On-device recognition cannot transcribe a file.',
        remedy: 'It listens to the microphone as you speak. For imports, choose '
            'Whisper (offline) in Settings — it also needs no key.',
      );
      return;
    }

    state = const RecordProcessing(label: 'Importing');

    final providers = await _resolveProviders(null);
    if (providers == null) return; // state already set to an error

    final ImportedAudio imported;
    try {
      imported = await _importer.import(
        sourcePath: sourcePath,
        recordingsDirPath: _settings.recordingsDirPath,
      );
    } on AudioImportException catch (e) {
      state = RecordError(e.message, remedy: e.remedy);
      return;
    }

    final recordingId = await _repository.createRecording(
      path: imported.path,
      duration: imported.duration,
      transcriptionProviderId: providers.transcription.id.value,
      structuringProviderId: providers.structuring.id.value,
      title: imported.sourceName,
    );

    await _consume(
      _pipelineFor(providers, imported.path).start(
        recordingId: recordingId,
        totalDurationMs: imported.duration.inMilliseconds,
        // An imported file carries no loudness history, so the planner has no silences to
        // cut on and falls back to its fixed boundaries with overlap.
        silences: const [],
        referenceDate: _isoDate(DateTime.now()),
        timeZone: DateTime.now().timeZoneName,
        userContext: _settings.customVocabulary.isEmpty
            ? null
            : 'Custom vocabulary: ${_settings.customVocabulary}',
        keyConceptsEnabled: _settings.workflowEnabled('smartSummaries'),
        flashcardLimit: _flashcardLimit,
        quizLimit: _quizLimit,
      ),
      recordingId,
    );
  }

  /// Picks up every recording the app was killed in the middle of.
  ///
  /// Called at launch. The point of the whole phase: the user opens the app and their
  /// notes are being written, rather than discovering a dead recording.
  Future<void> resumeUnfinished() async {
    final pending = await _db.recordingsWithUnfinishedChunks();
    if (pending.isEmpty) return;

    final providers = await _resolveProviders(null);
    if (providers == null) return;

    for (final recordingId in pending) {
      final recording = await _repository.byId(recordingId);
      if (recording?.audioPath == null ||
          !File(recording!.audioPath!).existsSync()) {
        // The audio is gone, so the outstanding chunks can never be transcribed.
        // Structure whatever did complete rather than retrying forever.
        continue;
      }

      await _consume(
        _pipelineFor(providers, recording.audioPath!).resume(
          recordingId: recordingId,
          referenceDate: _isoDate(recording.startedAt),
          timeZone: DateTime.now().timeZoneName,
          keyConceptsEnabled: _settings.workflowEnabled('smartSummaries'),
          flashcardLimit: _flashcardLimit,
          quizLimit: _quizLimit,
        ),
        recordingId,
      );
    }
  }

  DurableRecordingPipeline _pipelineFor(
          _Providers providers, String audioPath) =>
      DurableRecordingPipeline(
        queue: ChunkQueue(
          store: DriftChunkStore(_db),
          transcription: providers.transcription,
          audio: WavChunkReader(File(audioPath)),
          languageHint: _languageHint,
          speakerLabels: _settings.workflowEnabled('speakerLabels'),
        ),
        structuring: StructuringPipeline(provider: providers.structuring),
      );

  String? get _languageHint => _settings.workflowEnabled('multiLanguage')
      ? _settings.transcriptionLanguage
      : null;

  int get _flashcardLimit =>
      _settings.workflowEnabled('flashcards') ? _settings.flashcardLimit : 0;

  int get _quizLimit =>
      _settings.workflowEnabled('quizzes') ? _settings.quizLimit : 0;

  /// The cleaned transcript to store alongside the raw one, or null when the
  /// punctuation and filler cleanup workflow feature is off.
  String? _cleanedTranscript(Transcript transcript) =>
      _settings.workflowEnabled('punctuationCleanup')
          ? TranscriptCleaner.clean(transcript.plainText)
          : null;

  Future<void> _consume(
      Stream<PipelineEvent> events, String recordingId) async {
    await for (final event in events) {
      switch (event) {
        case TranscribingChunk(:final completed, :final total):
          state = RecordProcessing(
            label: total <= 1
                ? 'Transcribing'
                : 'Transcribing $completed of $total',
            fraction: event.fraction,
          );
        case ChunkFailed():
          break; // reported in the warning, not as a modal interruption
        case Structuring():
          state = const RecordProcessing(label: 'Writing notes');
        case PipelineComplete(:final transcript, :final outcome):
          await _repository.saveTranscript(
            recordingId,
            transcript,
            cleaned: _cleanedTranscript(transcript),
          );
          await _repository.saveNote(recordingId, outcome);
          final structuringWarning = _warningFor(transcript, outcome);
          final warning = [
            if (_storageWarning != null) _storageWarning!,
            if (structuringWarning != null) structuringWarning,
          ];
          state = RecordDone(
            recordingId,
            warning: warning.isEmpty ? null : warning.join(' · '),
          );
        case PipelineFailed(:final transcript, :final error):
          await _repository.saveTranscript(
            recordingId,
            transcript,
            cleaned: _cleanedTranscript(transcript),
          );
          state = RecordError(
            'The notes could not be written.',
            remedy: _pipelineFailureRemedy(error),
            recordingId: recordingId,
          );
      }
    }
  }

  static String _pipelineFailureRemedy(Object error) {
    final detail = error.toString();
    return 'Your recording and transcript are saved. Try again, or switch to a '
        'different service in Settings.\n\n$detail';
  }

  Future<_Providers?> _resolveProviders(TranscriptionProvider? live) async {
    final structuringKind = _settings.kindFor(ProviderStage.structuring);
    if (structuringKind == null) {
      state = const RecordError(
        'No note-writing service is set up yet.',
        remedy:
            'Choose one in Settings — a model on your own machine works without '
            'a key.',
      );
      return null;
    }

    final structuring = await _factory.structuring(ProviderSelection(
      kind: structuringKind,
      hasKey: true,
      endpoint: _settings.endpointFor(structuringKind),
      model: _settings.modelFor(structuringKind),
    ));
    if (structuring == null) {
      state = RecordError(
        '${structuringKind.label} is not configured.',
        remedy: 'Check its key or address in Settings.',
      );
      return null;
    }

    final transcriptionKind = _settings.kindFor(ProviderStage.transcription) ??
        SettingsStore.defaultTranscription;
    final transcription = live ??
        await _factory.transcription(ProviderSelection(
          kind: transcriptionKind,
          hasKey: true,
          model: _settings.modelFor(transcriptionKind),
        ));

    if (transcription == null) {
      state = const RecordError(
        'No transcription service is set up yet.',
        remedy: 'On-device recognition needs no key — choose it in Settings.',
      );
      return null;
    }

    return _Providers(transcription, structuring);
  }

  /// An honest one-liner about what is imperfect in this note, or null if nothing is.
  static String? _warningFor(Transcript transcript, StructureOutcome outcome) {
    final parts = <String>[
      if (transcript.gaps.isNotEmpty)
        '${transcript.gaps.length} section${transcript.gaps.length == 1 ? '' : 's'} '
            'could not be transcribed',
      if (outcome.unverifiedQuotes.isNotEmpty)
        '${outcome.unverifiedQuotes.length} item'
            '${outcome.unverifiedQuotes.length == 1 ? '' : 's'} could not be traced '
            'back to the recording',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_interruptionSub?.cancel());
    super.dispose();
  }
}

class _Providers {
  const _Providers(this.transcription, this.structuring);
  final TranscriptionProvider transcription;
  final StructuringProvider structuring;
}

final databaseProvider = Provider<TranscriptDatabase>((ref) {
  final db = TranscriptDatabase();
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<RecordingRepository>(
  (ref) => RecordingRepository(ref.watch(databaseProvider)),
);

final recorderProvider = Provider<RecorderService>((ref) {
  final recorder = RecorderService();
  ref.onDispose(recorder.dispose);
  return recorder;
});

final backgroundAudioProvider = Provider<BackgroundAudio>((ref) {
  final background = BackgroundAudio();
  ref.onDispose(background.dispose);
  return background;
});

final recordingsProvider = StreamProvider<List<Recording>>(
  (ref) => ref.watch(repositoryProvider).watchAll(),
);

/// SharedPreferences is async to open, so the app awaits it once at startup and
/// overrides this provider with the resolved instance.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => throw UnimplementedError('settingsStoreProvider must be overridden'),
);

/// Whether the note-writing stage can actually run right now — a provider chosen *and*
/// its key or address actually present, not just remembered as "the last one picked".
/// A key cleared later in Settings must count as unconfigured the same as never having
/// chosen one, so this checks the key store fresh rather than trusting the saved kind.
///
/// Recording itself never depends on this: on-device transcription needs nothing, so
/// recording-only use keeps working when nothing here is set up.
final structuringReadyProvider = FutureProvider<bool>((ref) async {
  final settings = ref.watch(settingsStoreProvider);
  final kind = settings.kindFor(ProviderStage.structuring);
  if (kind == null) return false;
  if (kind.needsKey) return ref.watch(keyStoreProvider).has(kind.id);
  if (kind.needsEndpoint) {
    return (settings.endpointFor(kind) ?? '').trim().isNotEmpty;
  }
  return true;
});

final recordingControllerProvider =
    StateNotifierProvider<RecordingController, RecordState>(
  (ref) => RecordingController(
    recorder: ref.watch(recorderProvider),
    repository: ref.watch(repositoryProvider),
    factory: ref.watch(providerFactoryProvider),
    settings: ref.watch(settingsStoreProvider),
    database: ref.watch(databaseProvider),
    background: ref.watch(backgroundAudioProvider),
  ),
);
