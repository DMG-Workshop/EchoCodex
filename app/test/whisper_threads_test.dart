import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/whisper/native_whisper_engine.dart';

void main() {
  group('how many threads offline Whisper decodes with', () {
    test('automatic leaves one core free and caps at eight', () {
      final threads = NativeWhisperEngine().threads;
      final cores = Platform.numberOfProcessors;

      expect(threads, greaterThanOrEqualTo(2),
          reason: 'even a single-core machine should not decode on zero threads');
      expect(threads, lessThanOrEqualTo(8),
          reason: 'whisper.cpp stops scaling around here; past it the extra '
              'threads mostly generate heat');
      if (cores > 2 && cores <= 9) {
        expect(threads, cores - 1,
            reason: 'the spare core is what keeps the UI drawing and the '
                'recorder writing while a decode runs');
      }
    });

    test('it is no longer the fixed native default on a capable machine', () {
      if (Platform.numberOfProcessors <= 5) return; // nothing to prove here
      expect(NativeWhisperEngine().threads, greaterThan(4),
          reason: 'the native default of 4 left half an eight-core phone idle '
              'during the slowest thing this app does locally');
    });

    test('an explicit choice is honoured', () {
      expect(NativeWhisperEngine(threads: 6).threads, 6);
      expect(NativeWhisperEngine(threads: 16).threads, 16,
          reason: 'the cap applies to the automatic figure, not to a number the '
              'user picked for hardware they know better than we do');
    });

    test('zero means automatic, not zero threads', () {
      expect(NativeWhisperEngine(threads: 0).threads, greaterThanOrEqualTo(2));
    });
  });
}
