import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/data/repository.dart';

void main() {
  group('packing a vector for storage', () {
    test('a vector survives the round trip', () {
      final vector = [0.0, 1.0, -1.0, 0.5, -0.25];
      final back = unpackVector(packVector(vector));

      expect(back, hasLength(vector.length));
      for (var i = 0; i < vector.length; i++) {
        expect(back[i], closeTo(vector[i], 1e-6));
      }
    });

    test('float32 is four bytes a dimension, not eight', () {
      expect(packVector(List.filled(768, 0.5)).lengthInBytes, 768 * 4,
          reason: 'this table grows with every hour recorded');
    });

    test('a realistic vector keeps enough precision for cosine similarity', () {
      final vector = [
        for (var i = 0; i < 384; i++) (i % 17) / 17 - 0.5,
      ];
      final back = unpackVector(packVector(vector));

      var dot = 0.0;
      var normA = 0.0;
      var normB = 0.0;
      for (var i = 0; i < vector.length; i++) {
        dot += vector[i] * back[i];
        normA += vector[i] * vector[i];
        normB += back[i] * back[i];
      }
      expect(dot / (normA.abs() + 1e-12), closeTo(1.0, 1e-5));
      expect(normB, closeTo(normA, 1e-4));
    });

    test('an empty vector is handled', () {
      expect(unpackVector(packVector(const [])), isEmpty);
    });

    test('a blob at an unaligned offset still reads', () {
      // sqlite makes no promise about a blob's alignment, and Float32List.view
      // demands a multiple of four — so an unaligned row would throw where an
      // aligned one worked, which is the worst kind of intermittent.
      final packed = packVector([1.0, 2.0, 3.0]);
      final padded = Uint8List(packed.lengthInBytes + 1)
        ..setRange(1, packed.lengthInBytes + 1, packed);
      final unaligned = Uint8List.view(padded.buffer, 1, packed.lengthInBytes);

      expect(unaligned.offsetInBytes % 4, isNot(0),
          reason: 'the test is worthless if the offset happens to be aligned');
      final back = unpackVector(unaligned);
      expect(back[0], closeTo(1.0, 1e-6));
      expect(back[2], closeTo(3.0, 1e-6));
    });
  });
}
