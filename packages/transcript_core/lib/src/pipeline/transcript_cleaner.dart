/// Removes filler words and tidies punctuation without paraphrasing.
///
/// Deliberately not an LLM call: the promise is "your words, minus the noise", and a
/// second model pass would risk rewriting what was actually said. Everything here is a
/// reversible, mechanical transform — the raw transcript is always kept alongside this
/// one so nothing is lost.
class TranscriptCleaner {
  const TranscriptCleaner._();

  /// Standalone filler words and phrases, matched as whole words so "like" is stripped
  /// but "unlike" and "likely" are not.
  static final List<RegExp> _fillers = [
    for (final phrase in const [
      'um+',
      'uh+',
      'uhh+',
      'erm+',
      'you know',
      'i mean',
      'sort of',
      'kind of',
      'basically',
      'literally',
      'actually',
    ])
      RegExp(r'\b' + phrase.replaceAll(' ', r'\s+') + r'\b',
          caseSensitive: false),
    // "like" only as a filler — surrounded by punctuation-adjacent pauses, not every
    // occurrence of the word, since "I like this" is a real sentence.
    RegExp(r'(?<=,|^)\s*like\s*(?=,|$)', caseSensitive: false),
  ];

  /// Immediate word repeats a stutter or a restart leaves behind: "the the plan",
  /// "I I think". Case-insensitive, keeps the first occurrence's casing.
  static final _immediateRepeat =
      RegExp(r'\b(\w+)(\s+\1\b)+', caseSensitive: false);

  static final _multiSpace = RegExp(r'[ \t]+');
  static final _spaceBeforePunctuation = RegExp(r'\s+([.,!?;:])');
  static final _sentenceEnd = RegExp(r'([.!?]\s+)([a-z])');

  /// A removed filler often leaves its neighbouring comma stranded next to another one,
  /// e.g. "So, um, I think" -> "So, , I think". Collapsed to a single comma.
  static final _repeatedPunctuation = RegExp(r'([,;:])(?:\s*\1)+');
  static final _leadingPunctuation = RegExp(r'^\s*[,;:]\s*');

  /// Strips filler, collapses stutters, and fixes spacing — the words that remain are
  /// exactly the words that were said.
  static String clean(String raw) {
    var text = raw;
    for (final filler in _fillers) {
      text = text.replaceAll(filler, '');
    }
    text = text.replaceAllMapped(_immediateRepeat, (m) => m.group(1)!);
    text = text.replaceAll(_multiSpace, ' ');
    text = text.replaceAllMapped(_repeatedPunctuation, (m) => m.group(1)!);
    text = text.replaceAllMapped(_spaceBeforePunctuation, (m) => m.group(1)!);
    text = text.replaceAll(_leadingPunctuation, '');
    text = text.replaceAllMapped(
        _sentenceEnd, (m) => '${m.group(1)}${m.group(2)!.toUpperCase()}');
    text = text.trim();
    if (text.isNotEmpty) {
      text = text[0].toUpperCase() + text.substring(1);
    }
    return text;
  }
}
