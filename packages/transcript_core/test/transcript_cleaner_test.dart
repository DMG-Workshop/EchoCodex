import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

void main() {
  group('TranscriptCleaner', () {
    test('strips standalone filler words', () {
      expect(
        TranscriptCleaner.clean('So, um, I think uh we should ship it.'),
        'So, I think we should ship it.',
      );
    });

    test('leaves words that merely contain a filler substring alone', () {
      expect(
        TranscriptCleaner.clean('I unlike this, but it will likely work.'),
        'I unlike this, but it will likely work.',
      );
    });

    test('collapses immediate word repeats', () {
      expect(
        TranscriptCleaner.clean('The the plan is is solid.'),
        'The plan is solid.',
      );
    });

    test('fixes spacing before punctuation and after sentence ends', () {
      expect(
        TranscriptCleaner.clean('Hello , world . next sentence.'),
        'Hello, world. Next sentence.',
      );
    });

    test('keeps meaning intact for a clean sentence', () {
      expect(
        TranscriptCleaner.clean('We shipped the release yesterday.'),
        'We shipped the release yesterday.',
      );
    });

    test('is empty-safe', () {
      expect(TranscriptCleaner.clean(''), '');
      expect(TranscriptCleaner.clean('   '), '');
    });
  });
}
