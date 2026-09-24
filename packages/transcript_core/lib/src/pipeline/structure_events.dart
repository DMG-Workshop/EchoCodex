/// What the structuring pipeline did, as it does it.
///
/// This exists because of a bug that took a code read to find. A recording of an hour and
/// seven minutes failed where half an hour succeeded, and every diagnostic the app could
/// produce said the same unhelpful thing: "the model could not produce a valid note". The
/// cause was arithmetic — an assumed context window left about 2,500 tokens for the merge,
/// which is less than one partial note, so the merge was attempted in one oversized call
/// that no server could read. Not one number involved in that decision was written down
/// anywhere.
///
/// So the pipeline now says what it is doing and what it is doing it with: the context it
/// believes it has, the budget that falls out of that, how many sections the transcript
/// became, how the merge was planned, and what each call cost. Off by default and free
/// when nobody is listening — [StructuringPipeline] takes a plain callback, so an app with
/// Debug Mode off passes null and pays nothing.
///
/// Deliberately carries no transcript text and no model output beyond a short excerpt of a
/// reply that failed to parse. The log is exportable, and a diagnostic that quietly
/// collects what was said is worse than no diagnostic.
library;

/// One thing the pipeline did.
sealed class StructureEvent {
  const StructureEvent();
}

/// How the work was planned, before any of it was done.
///
/// The line that would have explained the bug: a [budgetTokens] smaller than one partial
/// note means the merge cannot be done by the model, however many windows there are.
class StructurePlanned extends StructureEvent {
  const StructurePlanned({
    required this.transcriptTokens,
    required this.contextWindowTokens,
    required this.budgetTokens,
    required this.windows,
  });

  final int transcriptTokens;

  /// What the provider says it can read at once. Zero means it would not say, and the
  /// pipeline is working from an assumption.
  final int contextWindowTokens;

  /// What is left for a window of transcript, or for a batch of partials, once the
  /// prompt, the schema and the model's own answer are subtracted.
  final int budgetTokens;

  /// 1 for a single pass.
  final int windows;

  bool get isSinglePass => windows <= 1;
  bool get contextIsAssumed => contextWindowTokens == 0;
}

/// Which phase a call belongs to. Three, because they fail differently: a map call fails
/// on the transcript, a reduce call fails on the size of what it is merging, and the meta
/// call is the small one that should never fail at all.
enum StructurePhase { single, map, reduce, meta }

/// A request went out.
class StructureCallStarted extends StructureEvent {
  const StructureCallStarted({
    required this.phase,
    required this.index,
    required this.total,
    required this.promptTokens,
    required this.attempt,
  });

  final StructurePhase phase;

  /// 1-based within the phase.
  final int index;
  final int total;

  /// An estimate of what was sent, by the same arithmetic the budget uses. Against
  /// [StructurePlanned.contextWindowTokens] this is the whole story of an overflow.
  final int promptTokens;

  /// 0 for the first try; 1 and up are repairs after a schema violation.
  final int attempt;
}

/// A request came back and validated.
class StructureCallFinished extends StructureEvent {
  const StructureCallFinished({
    required this.phase,
    required this.index,
    required this.took,
    required this.attempts,
    this.inputTokens,
    this.outputTokens,
  });

  final StructurePhase phase;
  final int index;
  final Duration took;

  /// How many repairs it took. Above zero on every call means the model is not really
  /// honouring the schema, which is worth knowing before blaming the network.
  final int attempts;

  final int? inputTokens;
  final int? outputTokens;
}

/// A reply could not be used.
///
/// Recoverable — a repair turn follows — unless [willRetry] is false, in which case this
/// is the failure the user sees.
class StructureCallFailed extends StructureEvent {
  const StructureCallFailed({
    required this.phase,
    required this.index,
    required this.attempt,
    required this.willRetry,
    required this.violations,
    required this.replyLength,
    this.replyExcerpt,
  });

  final StructurePhase phase;
  final int index;
  final int attempt;
  final bool willRetry;

  /// The schema violations, or a single entry saying nothing parseable came back.
  final List<String> violations;

  /// How long the reply was. Zero is the signature of a prompt past the context window:
  /// the server accepts it and answers with nothing.
  final int replyLength;

  /// The first of what came back, so prose can be told from malformed JSON from silence.
  final String? replyExcerpt;
}

/// How the merge was planned, each round.
///
/// [stitched] is the important one. True means no two partials fit one prompt, so the
/// documents were merged here instead of by the model — correct, and the thing to look at
/// first if a long recording's note reads flatter than a short one's.
class StructureMergePlanned extends StructureEvent {
  const StructureMergePlanned({
    required this.round,
    required this.partials,
    required this.batches,
    required this.budgetTokens,
    required this.largestPartialTokens,
    required this.stitched,
  });

  final int round;
  final int partials;
  final int batches;
  final int budgetTokens;

  /// Against [budgetTokens], this says whether the model could have merged anything:
  /// twice this over budget means every batch holds one document and nothing can shrink.
  final int largestPartialTokens;

  final bool stitched;
}

/// The note is finished.
class StructureFinished extends StructureEvent {
  const StructureFinished({
    required this.took,
    required this.calls,
    required this.repairAttempts,
    required this.unverifiedQuotes,
  });

  final Duration took;
  final int calls;
  final int repairAttempts;

  /// How many cited quotes could not be found in the transcript. A number that climbs
  /// with recording length usually means windows are being cut mid-sentence.
  final int unverifiedQuotes;
}
