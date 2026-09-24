import 'dart:math' as math;

import 'recall_chunk.dart';

/// A passage and its vector, as stored.
class EmbeddedChunk {
  const EmbeddedChunk({required this.chunk, required this.vector});

  final RecallChunk chunk;
  final List<double> vector;
}

/// A passage that matched, and how well.
class RecallHit {
  const RecallHit({required this.chunk, required this.score});

  final RecallChunk chunk;

  /// Cosine similarity, -1..1. Exposed rather than hidden because the threshold that
  /// decides "no answer" is a judgement the caller has to be able to see and tune.
  final double score;
}

/// Finds the passages most like a question.
///
/// A linear scan rather than an approximate index, deliberately. One person's
/// recordings are thousands of passages, not millions: a full scan over 20,000 vectors
/// of 768 dimensions is a few million multiply-adds, which is milliseconds, and it
/// returns exactly the right answer. An ANN index would add a native dependency, a
/// build step on five platforms, and a class of "sometimes misses the obvious hit"
/// bug, to solve a scaling problem this app does not have.
class RecallIndex {
  const RecallIndex({this.minScore = 0.25});

  /// Below this a passage is not about the question, it is merely the closest thing
  /// in the corpus. Retrieval always returns *something*; this is what lets the
  /// caller say "nothing here answers that" instead of answering from the nearest
  /// unrelated paragraph.
  final double minScore;

  List<RecallHit> search(
    List<double> query,
    List<EmbeddedChunk> corpus, {
    int limit = 8,
  }) {
    if (query.isEmpty || corpus.isEmpty) return const [];
    final hits = <RecallHit>[];
    for (final entry in corpus) {
      if (entry.vector.length != query.length) continue;
      final score = cosineSimilarity(query, entry.vector);
      if (score < minScore) continue;
      hits.add(RecallHit(chunk: entry.chunk, score: score));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.length <= limit ? hits : hits.sublist(0, limit);
  }
}

/// Cosine similarity of two equal-length vectors, or 0 when either has no magnitude.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return 0;
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}

/// An answer, and the passages it is allowed to have come from.
class RecallAnswer {
  const RecallAnswer({
    required this.text,
    required this.citations,
    required this.hadEvidence,
  });

  final String text;

  /// The passages the answer actually cited, in the order cited. Empty is a valid
  /// and honest outcome.
  final List<RecallChunk> citations;

  /// Whether anything in the corpus scored above the threshold. False means the
  /// answer, whatever it says, was not grounded in these recordings.
  final bool hadEvidence;

  /// Nothing was found and nothing was claimed.
  bool get isEmpty => !hadEvidence && citations.isEmpty;
}

/// Builds the question, and checks the answer against what was retrieved.
///
/// The check is the point. A model asked about six months of meetings will happily
/// answer from what it knows about software teams in general, and that answer will be
/// fluent, plausible and untraceable — which is the single worst thing this app could
/// produce. So citations are parsed out of the reply and verified against the ids
/// actually supplied; an answer citing a passage that was never retrieved is treated
/// as ungrounded rather than shown.
class RecallPrompts {
  const RecallPrompts();

  static const String system = '''
You answer questions about a person's own recordings, using ONLY the passages supplied.

Rules, in order of importance:
1. If the passages do not answer the question, say so plainly and stop. Do not answer
   from general knowledge. "Nothing in these recordings covers that" is a good answer.
2. Cite the passage id in square brackets after every claim, like [rec_1:t3]. A claim
   with no citation will be discarded.
3. Quote sparingly and exactly. Never reword a quotation to fit the sentence.
4. If the passages disagree, say that they disagree and cite both.
5. Do not guess at dates, owners or numbers that the passages do not state.
''';

  /// The passages, rendered with their ids, and the question.
  String user(String question, List<RecallHit> hits) {
    final buffer = StringBuffer()..writeln('<passages>');
    for (final hit in hits) {
      buffer
        ..writeln(hit.chunk.render())
        ..writeln();
    }
    buffer
      ..writeln('</passages>')
      ..writeln()
      ..writeln('Question: $question');
    return buffer.toString();
  }

  /// Ids cited in [reply], in order, without duplicates.
  ///
  /// Matches the id shape this app mints — `recordingId:t3`, `recordingId:n12` — rather
  /// than anything in brackets, so an ordinary aside in square brackets is not mistaken
  /// for a citation.
  static List<String> citedIds(String reply) {
    final pattern = RegExp(r'\[([A-Za-z0-9_\-]+:[tn]\d+)\]');
    final seen = <String>{};
    final out = <String>[];
    for (final match in pattern.allMatches(reply)) {
      final id = match.group(1)!;
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  /// Turns a reply into an answer, keeping only citations that were actually supplied.
  ///
  /// A cited id that was never retrieved means the model invented a source. That is
  /// not a formatting slip to tidy up — it is the failure mode this whole design is
  /// guarding against, so the citation is dropped and the answer is marked ungrounded.
  RecallAnswer verify(String reply, List<RecallHit> hits) {
    final supplied = {for (final hit in hits) hit.chunk.id: hit.chunk};
    final cited = <RecallChunk>[];
    for (final id in citedIds(reply)) {
      final chunk = supplied[id];
      if (chunk != null) cited.add(chunk);
    }
    return RecallAnswer(
      text: reply.trim(),
      citations: cited,
      hadEvidence: hits.isNotEmpty && cited.isNotEmpty,
    );
  }
}
