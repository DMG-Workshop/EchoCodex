import '../models/note_document.dart';
import '../pipeline/transcript.dart';

/// Where a retrievable passage came from.
///
/// Every field here exists to get back to the moment: an answer this app gives about
/// six months of meetings is worth nothing unless the reader can check it, and "check
/// it" means opening the recording at the right second and reading what was actually
/// said. A passage that cannot say where it came from is not indexed.
class RecallSource {
  const RecallSource({
    required this.recordingId,
    required this.recordingTitle,
    required this.recordedOn,
    this.startMs,
    this.endMs,
  });

  final String recordingId;
  final String recordingTitle;

  /// ISO-8601 date of the recording, for ordering and for "what did we say in July".
  final String recordedOn;

  /// Position within the recording, when the passage came from the transcript. Null
  /// for note-derived passages, which belong to the recording rather than a moment.
  final int? startMs;
  final int? endMs;
}

/// What a passage is, which changes how much it should be trusted.
enum RecallKind {
  /// Spoken words, verbatim. The strongest evidence there is.
  transcript,

  /// A line the model wrote summarising the recording.
  summary,

  /// A decision, task or open question the model extracted, with its own quote behind
  /// it in the note.
  extract,

  /// A line the user chose to keep in the Codex. Rare, and worth weighting: a human
  /// decided this one mattered.
  codex,
}

/// One retrievable passage, with the provenance to cite it.
class RecallChunk {
  const RecallChunk({
    required this.id,
    required this.text,
    required this.kind,
    required this.source,
  });

  /// Stable within a recording, so re-indexing replaces rather than duplicates.
  final String id;

  final String text;
  final RecallKind kind;
  final RecallSource source;

  /// How the model is shown this passage: an id it can cite, and enough context to
  /// know what it is looking at.
  String render() {
    final where = source.startMs == null
        ? source.recordedOn
        : '${source.recordedOn} at ${_clock(source.startMs!)}';
    return '[$id] (${kind.name} · ${source.recordingTitle} · $where)\n$text';
  }

  static String _clock(int ms) {
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

/// Cuts a recording into passages worth retrieving.
///
/// Pure and synchronous, so what gets indexed — and what deliberately does not — is
/// testable without a database, an embedding model or a network.
class RecallChunker {
  const RecallChunker({
    this.targetChars = 900,
    this.overlapChars = 150,
    this.minChars = 40,
  });

  /// Roughly a paragraph of speech. Small enough that a hit points at something
  /// specific, large enough that a sentence keeps the context that gives it meaning.
  final int targetChars;

  /// Carried from the previous chunk, so an answer that straddles a boundary is still
  /// found whole by one of the two.
  final int overlapChars;

  /// Below this a passage is a fragment — "Yes." retrieves against everything and
  /// means nothing on its own.
  final int minChars;

  /// Passages from what was said.
  List<RecallChunk> fromTranscript(Transcript transcript, RecallSource source) {
    final out = <RecallChunk>[];
    final buffer = StringBuffer();
    var bufferStart = 0;
    var bufferEnd = 0;
    var index = 0;

    void flush() {
      final text = buffer.toString().trim();
      buffer.clear();
      if (text.length < minChars) return;
      out.add(RecallChunk(
        id: '${source.recordingId}:t$index',
        text: text,
        kind: RecallKind.transcript,
        source: RecallSource(
          recordingId: source.recordingId,
          recordingTitle: source.recordingTitle,
          recordedOn: source.recordedOn,
          startMs: bufferStart,
          endMs: bufferEnd,
        ),
      ));
      index++;
    }

    for (final segment in transcript.segments) {
      final text = segment.text.trim();
      if (text.isEmpty) continue;
      if (buffer.isEmpty) bufferStart = segment.startMs;
      bufferEnd = segment.endMs;
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(text);

      if (buffer.length >= targetChars) {
        final carried = _tail(buffer.toString(), overlapChars);
        flush();
        // The overlap starts the next chunk, and starts it at this segment: a
        // carried tail belongs to where it is about to be read, not where it was.
        if (carried.isNotEmpty) {
          buffer.write(carried);
          bufferStart = segment.startMs;
        }
      }
    }
    flush();
    return out;
  }

  /// Passages from what the model wrote about the recording.
  ///
  /// One per item rather than one per note: a decision and an unrelated open question
  /// share nothing but a document, and indexing them together makes both harder to
  /// find. Each already carries a source quote in the note, so a hit here can still
  /// be traced to the words behind it.
  List<RecallChunk> fromNote(NoteDocument note, RecallSource source) {
    final out = <RecallChunk>[];
    var index = 0;

    void add(String text, RecallKind kind, {int? startMs, int? endMs}) {
      final trimmed = text.trim();
      if (trimmed.length < minChars) return;
      out.add(RecallChunk(
        id: '${source.recordingId}:n${index++}',
        text: trimmed,
        kind: kind,
        source: RecallSource(
          recordingId: source.recordingId,
          recordingTitle: source.recordingTitle,
          recordedOn: source.recordedOn,
          startMs: startMs,
          endMs: endMs,
        ),
      ));
    }

    add(note.meta.summary, RecallKind.summary);

    for (final section in note.sections) {
      for (final bullet in section.bullets) {
        add('${section.heading}: $bullet', RecallKind.summary);
      }
    }
    for (final decision in note.decisions) {
      add('Decision: ${decision.statement}', RecallKind.extract,
          startMs: decision.sourceRef.startMs, endMs: decision.sourceRef.endMs);
    }
    for (final question in note.openQuestions) {
      add('Open question: ${question.question}', RecallKind.extract,
          startMs: question.sourceRef.startMs, endMs: question.sourceRef.endMs);
    }
    for (final task in note.tasks) {
      final owner = task.assigneeRaw ?? task.assigneeId;
      add(
        'Task: ${task.title}${owner == null ? '' : ' (owner: $owner)'}'
        '${task.dueDate == null ? '' : ' (due ${task.dueDate})'}',
        RecallKind.extract,
        startMs: task.sourceRef.startMs,
        endMs: task.sourceRef.endMs,
      );
    }
    return out;
  }

  static String _tail(String text, int chars) {
    if (chars <= 0 || text.length <= chars) return '';
    final cut = text.substring(text.length - chars);
    // Start the carried tail at a word boundary; half a word helps nobody.
    final space = cut.indexOf(' ');
    return space == -1 ? cut : cut.substring(space + 1);
  }
}
