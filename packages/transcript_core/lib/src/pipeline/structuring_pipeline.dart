import 'dart:convert';

import '../models/note_document.dart';
import '../prompts/structuring_prompts.dart';
import '../providers/provider.dart';
import '../schema/note_schema.dart';
import '../schema/validator.dart';
import 'json_extract.dart';
import 'section_planner.dart';
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
  })  : schema = schema ?? noteDocumentSchema,
        _validator = SchemaValidator(schema ?? noteDocumentSchema);

  final StructuringProvider provider;

  /// Two attempts, then degrade. A model that cannot satisfy the schema in three tries
  /// will not satisfy it in five, and the user is waiting.
  final int maxRepairAttempts;

  final Map<String, dynamic> schema;
  final SchemaValidator _validator;

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

    return fitsSinglePass(transcript)
        ? _singlePass(transcript, systemPrompt, onProgress)
        : _mapReduce(transcript, systemPrompt, onProgress);
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

  /// Merges the per-window documents into one, in as many rounds as it takes.
  ///
  /// The map phase is budgeted against the provider's context; for a long time the
  /// reduce phase was not, and that asymmetry is what made long recordings fail. Every
  /// partial is a whole NoteDocument — summary, sections, tasks, decisions, and a
  /// verbatim source quote behind each one — so the reduce prompt grows with the length
  /// of the recording. An hour of audio produces enough windows to overflow any context
  /// the map phase was carefully kept inside, and the overflow surfaces as a model that
  /// returns nothing parseable: "could not produce a valid note", with nothing pointing
  /// at the real cause.
  ///
  /// So the merge is a tree, not a single call. Partials are grouped into batches that
  /// fit the same budget a window gets, each batch is merged, and the merged documents
  /// go round again until one is left. That costs more round trips on a long recording,
  /// which is the correct trade against not finishing at all.
  Future<_ValidatedStructure> _reduce(
      List<Map<String, dynamic>> partials) async {
    var level = partials;
    var repairs = 0;
    int? inputTokens;
    int? outputTokens;

    while (true) {
      final batches = _batched(level, _windowBudget());

      // Everything fits in one call, or grouping cannot make the set any smaller —
      // a single partial already over budget, most likely. Either way this is the last
      // round, and an oversized attempt beats refusing to produce anything.
      if (batches.length <= 1 || batches.length >= level.length) {
        final merged = await _structureValidated(
          StructuringPrompts.reduce,
          _partialsPrompt(level),
        );
        return _ValidatedStructure(
          merged.raw,
          repairs + merged.repairAttempts,
          _add(inputTokens, merged.inputTokens),
          _add(outputTokens, merged.outputTokens),
          merged.model,
        );
      }

      final next = <Map<String, dynamic>>[];
      for (final batch in batches) {
        // A batch of one has nothing to merge with; sending it through a reduce round
        // would spend a request to rewrite a document that is already valid.
        if (batch.length == 1) {
          next.add(batch.single);
          continue;
        }
        final merged = await _structureValidated(
          StructuringPrompts.reduce,
          _partialsPrompt(batch),
        );
        repairs += merged.repairAttempts;
        inputTokens = _add(inputTokens, merged.inputTokens);
        outputTokens = _add(outputTokens, merged.outputTokens);
        next.add(merged.raw);
      }

      // Guaranteed progress: batches.length < level.length above, and every batch
      // collapses to exactly one document, so this terminates.
      level = next;
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

  /// One provider round trip, with tolerant parsing, validation and bounded repair.
  Future<_ValidatedStructure> _structureValidated(
    String systemPrompt,
    String userContent,
  ) async {
    final turns = <StructureTurn>[];
    var attempts = 0;
    int? inputTokens;
    int? outputTokens;

    while (true) {
      final response = await provider.structure(StructureRequest(
        systemPrompt: systemPrompt,
        userContent: userContent,
        schema: schema,
        priorTurns: turns,
      ));

      inputTokens = _add(inputTokens, response.inputTokens);
      outputTokens = _add(outputTokens, response.outputTokens);

      final parsed = extractJsonObject(response.rawText);
      final violations = parsed == null
          ? [
              const SchemaViolation(
                  '', 'response did not contain a JSON object')
            ]
          : _validator.validate(parsed);

      if (violations.isEmpty && parsed != null) {
        return _ValidatedStructure(
          parsed,
          attempts,
          inputTokens,
          outputTokens,
          response.model,
        );
      }

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
    return StructureOutcome(
      document: document,
      raw: parsed,
      repairAttempts: attempts,
      unverifiedQuotes: verifyQuotes(document, transcript),
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
