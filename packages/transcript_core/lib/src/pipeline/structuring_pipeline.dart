import 'dart:convert';

import '../models/note_document.dart';
import '../prompts/structuring_prompts.dart';
import '../providers/provider.dart';
import '../schema/note_schema.dart';
import '../schema/validator.dart';
import 'document_merge.dart';
import 'json_extract.dart';
import 'section_planner.dart';
import 'structure_events.dart';
import 'quote_verifier.dart';
import 'transcript.dart';

/// Turns a transcript into a validated [NoteDocument].
///
/// Every provider gets identical treatment here — tolerant parse, schema validation,
/// bounded repair, offline quote verification — so reliability does not depend on which
/// model the user happened to configure.
class StructuringPipeline {
  StructuringPipeline({
    required this.provider,
    this.maxRepairAttempts = 2,
    Map<String, dynamic>? schema,
    this.onEvent,
  })  : schema = schema ?? noteDocumentSchema,
        _validator = SchemaValidator(schema ?? noteDocumentSchema);

  final StructuringProvider provider;

  /// Two attempts, then degrade. A model that cannot satisfy the schema in three tries
  /// will not satisfy it in five, and the user is waiting.
  final int maxRepairAttempts;

  final Map<String, dynamic> schema;
  final SchemaValidator _validator;

  /// Told what the pipeline is doing, for Debug Mode. Null costs one null check per event,
  /// which is the point: nothing here may make a note slower to write when nobody is
  /// watching. See [StructureEvent] for why this exists at all.
  final void Function(StructureEvent)? onEvent;

  /// Wall-clock from the start of [run], for the finished event.
  Stopwatch? _elapsed;
  int _calls = 0;

  /// Structures a transcript, choosing single-pass or map/reduce by token budget.
  ///
  /// The choice is made here rather than by the caller because getting it wrong is
  /// silent: a transcript that overflows the context is truncated by the provider, and
  /// the note that comes back looks perfectly reasonable while missing the second half
  /// of the meeting.
  Future<StructureOutcome> run({
    required Transcript transcript,
    required String referenceDate,
    required String timeZone,
    required String sttProviderName,
    bool diarizationAvailable = false,
    String? userContext,
    String? templateInstructions,
    bool keyConceptsEnabled = false,
    int flashcardLimit = 0,
    int quizLimit = 0,
    void Function(StructureProgress)? onProgress,
  }) async {
    if (transcript.isEmpty) {
      throw const StructuringException(
        'The transcript is empty. Nothing was said, or transcription failed for every '
        'chunk.',
      );
    }

    final systemPrompt = StructuringPrompts.system(
      referenceDate: referenceDate,
      timeZone: timeZone,
      durationHuman: _humanDuration(transcript.durationMs),
      sttProviderName: sttProviderName,
      diarizationAvailable: diarizationAvailable,
      userContext: [
        if (userContext?.trim().isNotEmpty == true) userContext!.trim(),
        if (templateInstructions?.trim().isNotEmpty == true)
          'Note template instructions:\n${templateInstructions!.trim()}',
      ].join('\n\n').trim().isEmpty
          ? null
          : [
              if (userContext?.trim().isNotEmpty == true) userContext!.trim(),
              if (templateInstructions?.trim().isNotEmpty == true)
                'Note template instructions:\n${templateInstructions!.trim()}',
            ].join('\n\n'),
      keyConceptsEnabled: keyConceptsEnabled,
      flashcardLimit: flashcardLimit,
      quizLimit: quizLimit,
    );

    _elapsed = Stopwatch()..start();
    _calls = 0;

    if (!fitsSinglePass(transcript)) {
      return _mapReduce(transcript, systemPrompt, onProgress);
    }
    _emit(() => StructurePlanned(
          transcriptTokens: transcript.estimatedTokens,
          contextWindowTokens: provider.capabilities.contextWindowTokens,
          budgetTokens: _windowBudget(),
          windows: 1,
        ));
    return _singlePass(transcript, systemPrompt, onProgress);
  }

  void _emit(StructureEvent Function() event) {
    final listener = onEvent;
    if (listener == null) return;
    try {
      listener(event());
    } catch (_) {
      // A diagnostic that throws must not cost the user their note. There is nowhere to
      // report this — a logger here is exactly the dependency these events exist to
      // avoid — and the listener is the one thing already broken, so it is dropped.
    }
  }

  Future<StructureOutcome> _singlePass(
    Transcript transcript,
    String systemPrompt,
    void Function(StructureProgress)? onProgress,
  ) async {
    onProgress?.call(const StructureProgress(completed: 0, total: 1));
    final result = await _structureValidated(
      systemPrompt,
      '<transcript>\n${transcript.toPromptFormat()}\n</transcript>',
      phase: StructurePhase.single,
    );
    onProgress?.call(const StructureProgress(completed: 1, total: 1));

    return _finish(
      result.raw,
      transcript,
      result.repairAttempts,
      result.inputTokens,
      result.outputTokens,
      result.model,
    );
  }

  /// Extract each window on its own, then merge.
  ///
  /// Windows are processed in order rather than in parallel, so each carries forward the
  /// participant roster established so far. Speaker identity that resets every window
  /// produces four "Sarah"s in one note, and no merge pass can reliably undo that.
  Future<StructureOutcome> _mapReduce(
    Transcript transcript,
    String systemPrompt,
    void Function(StructureProgress)? onProgress,
  ) async {
    final windows =
        const SectionPlanner().split(transcript, budgetTokens: _windowBudget());
    _emit(() => StructurePlanned(
          transcriptTokens: transcript.estimatedTokens,
          contextWindowTokens: provider.capabilities.contextWindowTokens,
          budgetTokens: _windowBudget(),
          windows: windows.length,
        ));
    if (windows.length < 2) {
      // The budget is too small to split usefully — a tiny local context, most likely.
      // One oversized attempt beats refusing to produce anything.
      return _singlePass(transcript, systemPrompt, onProgress);
    }

    final partials = <Map<String, dynamic>>[];
    final roster = <String, Map<String, dynamic>>{};
    var repairs = 0;
    int? inputTokens;
    int? outputTokens;

    for (final window in windows) {
      onProgress?.call(
        StructureProgress(
            completed: window.index - 1, total: windows.length + 1),
      );

      final prompt = StructuringPrompts.mapSection(
        systemPrompt: systemPrompt,
        index: window.index,
        total: window.total,
        windowStartHuman: _clock(window.startMs),
        windowEndHuman: _clock(window.endMs),
        participantRosterJson: jsonEncode(roster.values.toList()),
      );

      final result = await _structureValidated(
        prompt,
        '<transcript>\n${window.transcript.toPromptFormat()}\n</transcript>',
        phase: StructurePhase.map,
        index: window.index,
        total: window.total,
      );

      partials.add(result.raw);
      repairs += result.repairAttempts;
      inputTokens = _add(inputTokens, result.inputTokens);
      outputTokens = _add(outputTokens, result.outputTokens);

      for (final participant
          in (result.raw['participants'] as List?) ?? const []) {
        if (participant is Map<String, dynamic>) {
          roster['${participant['id']}'] = participant;
        }
      }
    }

    onProgress?.call(
      StructureProgress(completed: windows.length, total: windows.length + 1),
    );

    final merged = await _reduce(partials);

    onProgress?.call(
      StructureProgress(
          completed: windows.length + 1, total: windows.length + 1),
    );

    return _finish(
      merged.raw,
      transcript,
      repairs + merged.repairAttempts,
      _add(inputTokens, merged.inputTokens),
      _add(outputTokens, merged.outputTokens),
      merged.model,
    );
  }

  /// Merges the per-window documents into one.
  ///
  /// The map phase is budgeted against the provider's context; the reduce phase was not,
  /// and that asymmetry is what makes long recordings fail. Every partial is a whole
  /// NoteDocument — summary, sections, tasks, decisions, and a verbatim quote behind each
  /// item — so the merge prompt grows with the length of the recording while the context
  /// does not.
  ///
  /// So this merges in rounds: partials are grouped into batches that fit the same budget a
  /// window gets, each batch is merged, and the merged documents go round again. That alone
  /// was not enough. When the server will not say how big its context is the budget falls
  /// back to an assumed 8k window, which leaves about 2,500 tokens for the merge — less
  /// than two real partials. Grouping then puts every partial in a batch of its own, makes
  /// no progress, and the rounds never start: an hour of audio ended as "the model could not
  /// produce a valid note", and the note was never coming, at any number of retries.
  ///
  /// Past that point the merge stops being a thing to ask a model for. Everything it has to
  /// do is mechanical — union the roster, keep the sections in order, drop the repeats, hold
  /// the ids unique — so [stitchNoteDocuments] does it here, for free, with no upper bound
  /// on length. The one request left is for the prose, over the section summaries alone.
  Future<_ValidatedStructure> _reduce(
      List<Map<String, dynamic>> partials) async {
    var level = partials;
    var repairs = 0;
    int? inputTokens;
    int? outputTokens;
    String? model;

    // Merge with the model for as long as grouping makes the set smaller. This is the pass
    // that folds one commitment, made twice half an hour apart, into a single task.
    var round = 0;
    while (level.length > 1) {
      final budget = _windowBudget();
      final batches = _batched(level, budget);
      final stitching = batches.length >= level.length;
      final largest = level.map(_jsonTokens).reduce((a, b) => a > b ? a : b);
      round++;
      _emit(() => StructureMergePlanned(
            round: round,
            partials: level.length,
            batches: batches.length,
            budgetTokens: budget,
            largestPartialTokens: largest,
            stitched: stitching,
          ));

      // Grouping made no progress: no two of these fit one prompt. Sending all of them
      // anyway is the call that fails, so stop here and stitch instead.
      if (stitching) break;

      final next = <Map<String, dynamic>>[];
      var batchIndex = 0;
      for (final batch in batches) {
        batchIndex++;
        // A batch of one has nothing to merge with; a reduce round on it would spend a
        // request rewriting a document that is already valid.
        if (batch.length == 1) {
          next.add(batch.single);
          continue;
        }
        final merged = await _structureValidated(
          StructuringPrompts.reduce,
          _partialsPrompt(batch),
          phase: StructurePhase.reduce,
          index: batchIndex,
          total: batches.length,
        );
        repairs += merged.repairAttempts;
        inputTokens = _add(inputTokens, merged.inputTokens);
        outputTokens = _add(outputTokens, merged.outputTokens);
        model = merged.model ?? model;
        next.add(merged.raw);
      }

      // Guaranteed progress: batches.length < level.length above, and every batch collapses
      // to exactly one document, so this terminates.
      level = next;
    }

    if (level.length == 1) {
      return _ValidatedStructure(
          level.single, repairs, inputTokens, outputTokens, model);
    }

    final stitched = stitchNoteDocuments(level);
    final meta = await _reduceMeta(level);
    if (meta != null) {
      stitched['meta'] = {
        ...(stitched['meta'] as Map<String, dynamic>),
        ...meta.raw,
      };
      repairs += meta.repairAttempts;
      inputTokens = _add(inputTokens, meta.inputTokens);
      outputTokens = _add(outputTokens, meta.outputTokens);
      model = meta.model ?? model;
    }
    return _ValidatedStructure(
        stitched, repairs, inputTokens, outputTokens, model);
  }

  /// One small request for the whole-recording title and summary.
  ///
  /// Null when it could not be had, which is not a failure: the stitched document already
  /// carries the section summaries joined together, and plain prose on an hour of audio is
  /// worth more than an error the user cannot do anything about.
  Future<_ValidatedStructure?> _reduceMeta(
      List<Map<String, dynamic>> partials) async {
    final properties = schema['properties'];
    final metaSchema = properties is Map ? properties['meta'] : null;
    if (metaSchema is! Map) return null;

    final sections = [
      for (var i = 0; i < partials.length; i++)
        {
          'section': i + 1,
          'of': partials.length,
          if (partials[i]['meta'] is Map) ...partials[i]['meta'] as Map,
        },
    ];

    try {
      return await _structureValidated(
        StructuringPrompts.reduceMeta,
        '<section_summaries>\n${jsonEncode(sections)}\n</section_summaries>',
        schema: metaSchema.cast<String, dynamic>(),
        phase: StructurePhase.meta,
      );
    } on StructuringException {
      return null;
    } on Exception {
      // A transport failure here is the same story: the document is already complete.
      return null;
    }
  }

  static String _partialsPrompt(List<Map<String, dynamic>> partials) =>
      '<partial_documents>\n${jsonEncode(partials)}\n</partial_documents>';

  /// Groups [partials] into consecutive batches that each fit [budgetTokens].
  ///
  /// Consecutive rather than best-fit: the documents are in recording order, and merging
  /// neighbours keeps a conversation that spans a window boundary together. A partial
  /// larger than the whole budget still gets a batch of its own rather than being
  /// dropped — losing a window of the meeting to make the arithmetic work is not a
  /// trade this pipeline makes.
  static List<List<Map<String, dynamic>>> _batched(
    List<Map<String, dynamic>> partials,
    int budgetTokens,
  ) {
    final batches = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];
    var currentTokens = 0;

    for (final partial in partials) {
      final tokens = _jsonTokens(partial);
      if (current.isNotEmpty && currentTokens + tokens > budgetTokens) {
        batches.add(current);
        current = <Map<String, dynamic>>[];
        currentTokens = 0;
      }
      current.add(partial);
      currentTokens += tokens;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  static int _jsonTokens(Object? value) =>
      (jsonEncode(value).length / 3.5).ceil();

  /// Everything the provider is being asked to read, by the same arithmetic the budget
  /// uses — so the log's estimate and the pipeline's decision cannot disagree.
  static int _requestTokens(StructureRequest request) {
    var characters = request.systemPrompt.length + request.userContent.length;
    for (final turn in request.priorTurns) {
      characters += turn.content.length;
    }
    return (characters / 3.5).ceil() + _jsonTokens(request.schema);
  }

  /// Enough of a reply to tell silence from prose from malformed JSON. Never the whole
  /// thing: this goes in an exportable log, and the reply is the note.
  static String? _excerpt(String reply) {
    final trimmed = reply.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= 200 ? trimmed : '${trimmed.substring(0, 200)}…';
  }

  /// One provider round trip, with tolerant parsing, validation and bounded repair.
  ///
  /// [schema] overrides the note schema for a call that asks for something smaller — the
  /// merge's title-and-summary pass — so that reply is validated and repaired the same way
  /// everything else is, rather than trusted because it was short.
  Future<_ValidatedStructure> _structureValidated(
    String systemPrompt,
    String userContent, {
    Map<String, dynamic>? schema,
    StructurePhase phase = StructurePhase.single,
    int index = 1,
    int total = 1,
  }) async {
    final requestSchema = schema ?? this.schema;
    final validator = schema == null ? _validator : SchemaValidator(schema);
    final turns = <StructureTurn>[];
    var attempts = 0;
    int? inputTokens;
    int? outputTokens;

    while (true) {
      final request = StructureRequest(
        systemPrompt: systemPrompt,
        userContent: userContent,
        schema: requestSchema,
        priorTurns: turns,
      );
      _calls++;
      _emit(() => StructureCallStarted(
            phase: phase,
            index: index,
            total: total,
            promptTokens: _requestTokens(request),
            attempt: attempts,
          ));

      final started = Stopwatch()..start();
      final response = await provider.structure(request);
      started.stop();

      inputTokens = _add(inputTokens, response.inputTokens);
      outputTokens = _add(outputTokens, response.outputTokens);

      final parsed = extractJsonObject(response.rawText);
      final violations = parsed == null
          ? [
              const SchemaViolation(
                  '', 'response did not contain a JSON object')
            ]
          : validator.validate(parsed);

      if (violations.isEmpty && parsed != null) {
        _emit(() => StructureCallFinished(
              phase: phase,
              index: index,
              took: started.elapsed,
              attempts: attempts,
              inputTokens: response.inputTokens,
              outputTokens: response.outputTokens,
            ));
        return _ValidatedStructure(
          parsed,
          attempts,
          inputTokens,
          outputTokens,
          response.model,
        );
      }

      _emit(() => StructureCallFailed(
            phase: phase,
            index: index,
            attempt: attempts,
            willRetry: attempts < maxRepairAttempts,
            violations: violations.map((v) => v.toString()).toList(),
            replyLength: response.rawText.length,
            replyExcerpt: _excerpt(response.rawText),
          ));

      if (attempts >= maxRepairAttempts) {
        throw StructuringException(
          'The model could not produce a valid note after ${attempts + 1} attempts.',
          violations: violations.map((v) => v.toString()).toList(),
          lastResponse: response.rawText,
        );
      }

      // The repair turn carries only the errors — the transcript is already in the
      // conversation and re-sending it would cost the whole prompt again.
      turns
        ..add(StructureTurn('user', userContent))
        ..add(StructureTurn('assistant', response.rawText))
        ..add(StructureTurn(
          'user',
          StructuringPrompts.repair(
              violations.map((v) => v.toString()).toList()),
        ));
      attempts++;
    }
  }

  /// How much transcript fits in one window, leaving room for the prompt, the schema and
  /// the model's own output.
  int _windowBudget() {
    final window = provider.capabilities.contextWindowTokens;
    final schemaTokens = _jsonTokens(schema);
    final reserve = provider.capabilities.maxOutputTokens.clamp(2000, 16000);
    // Unknown context: assume something small enough to be safe on a local model.
    final usable = window == 0 ? 8192 : window;
    final budget = usable - _promptOverhead - schemaTokens - reserve;
    return budget < 500 ? 500 : budget;
  }

  static const int _promptOverhead = 1200;

  static String _clock(int ms) {
    final total = ms ~/ 1000;
    final m = (total % 3600) ~/ 60;
    final h = total ~/ 3600;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  StructureOutcome _finish(
    Map<String, dynamic> parsed,
    Transcript transcript,
    int attempts,
    int? inputTokens,
    int? outputTokens, [
    String? model,
  ]) {
    final document = NoteDocument.fromJson(parsed);
    final unverified = verifyQuotes(document, transcript);
    _emit(() => StructureFinished(
          took: _elapsed?.elapsed ?? Duration.zero,
          calls: _calls,
          repairAttempts: attempts,
          unverifiedQuotes: unverified.length,
        ));
    return StructureOutcome(
      document: document,
      raw: parsed,
      repairAttempts: attempts,
      unverifiedQuotes: unverified,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      model: model,
    );
  }

  /// Checks every cited quote against the transcript and returns the ids that failed.
  ///
  /// Deterministic, offline and free — the one hallucination check that costs nothing per
  /// run. Failures are surfaced in the UI as unverified rather than dropped: the item may
  /// still be real, and silently deleting a task is its own failure mode.
  static List<String> verifyQuotes(NoteDocument doc, Transcript transcript) {
    final verifier = QuoteVerifier(transcript.plainText);
    final flagged = <String>[];

    void check(String id, String quote) {
      if (verifier.verify(quote).shouldFlag) flagged.add(id);
    }

    for (final t in doc.tasks) {
      check(t.id, t.sourceRef.quote);
    }
    for (final d in doc.decisions) {
      check(d.id, d.sourceRef.quote);
    }
    for (final q in doc.openQuestions) {
      check(q.id, q.sourceRef.quote);
    }
    for (final r in doc.risks) {
      check(r.id, r.sourceRef.quote);
    }
    for (final a in doc.timelineAnchors) {
      check(a.label, a.sourceRef.quote);
    }
    return flagged;
  }

  /// Whether this transcript fits the provider's context in one pass.
  ///
  /// Under-estimating here means a silently truncated transcript, so the reserve is
  /// deliberately generous. A context window of zero means unknown — a local server that
  /// would not tell us — and unknown always takes the map/reduce path.
  bool fitsSinglePass(Transcript transcript) {
    final window = provider.capabilities.contextWindowTokens;
    if (window == 0) return false;
    const promptOverhead = 1200;
    final schemaTokens = _jsonTokens(schema);
    final reserve = provider.capabilities.maxOutputTokens.clamp(2000, 16000);
    return transcript.estimatedTokens +
            promptOverhead +
            schemaTokens +
            reserve <
        window;
  }

  static int? _add(int? a, int? b) =>
      a == null && b == null ? null : (a ?? 0) + (b ?? 0);

  static String _humanDuration(int ms) {
    final minutes = (ms / 60000).round();
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return '$minutes minute${minutes == 1 ? '' : 's'}';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0
        ? '$hours hour${hours == 1 ? '' : 's'}'
        : '$hours h $rest min';
  }
}

/// Structuring failed in a way the user needs to know about. The raw transcript is
/// already saved by this point, so nothing is lost — the note can be retried, or retried
/// against a different provider.
class StructuringException implements Exception {
  const StructuringException(
    this.message, {
    this.violations = const [],
    this.lastResponse,
  });

  final String message;
  final List<String> violations;
  final String? lastResponse;

  /// Enough of the reply to tell silence from prose from malformed JSON, without pasting
  /// a whole note into an error message.
  static const int _excerpt = 300;

  @override
  String toString() {
    final out = StringBuffer('StructuringException: $message');
    if (violations.isNotEmpty) out.write('\n${violations.join('\n')}');

    // What the model actually said is the one thing that distinguishes a model ignoring
    // the schema from one that answered nothing at all, and it was being thrown away
    // here — leaving "response did not contain a JSON object" with nothing to act on.
    // Safe to show: this exception is caught and rendered in-app, never handed to the
    // crash reporter, which is what feeds the shareable diagnostics bundle.
    final reply = lastResponse?.trim();
    if (reply != null) {
      out.write('\n\nThe model replied: ');
      out.write(reply.isEmpty
          ? '(nothing at all)'
          : '"${reply.length > _excerpt ? '${reply.substring(0, _excerpt)}…' : reply}"');
    }
    return out.toString();
  }
}

/// One validated provider response, with what it cost to get there.
class _ValidatedStructure {
  const _ValidatedStructure(
    this.raw,
    this.repairAttempts,
    this.inputTokens,
    this.outputTokens,
    this.model,
  );

  final Map<String, dynamic> raw;
  final int repairAttempts;
  final int? inputTokens;
  final int? outputTokens;
  final String? model;
}

/// Structuring progress, for the UI. On a long recording the reduce pass is the last
/// step, which is why [total] is one more than the number of windows.
class StructureProgress {
  const StructureProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  double get fraction => total == 0 ? 0 : completed / total;
  bool get isMerging => total > 1 && completed == total - 1;
}
