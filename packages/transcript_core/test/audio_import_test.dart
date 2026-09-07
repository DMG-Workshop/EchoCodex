import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

void main() {
  /// A WAV carrying [frames] of a simple ramp, in whatever shape the test needs.
  Uint8List wav({
    required int sampleRate,
    required int channels,
    int bitsPerSample = 16,
    int frames = 100,
    int Function(int frame, int channel)? sample,
  }) {
    final bytesPerSample = bitsPerSample ~/ 8;
    final pcm = Uint8List(frames * channels * bytesPerSample);
    final view = ByteData.sublistView(pcm);

    for (var frame = 0; frame < frames; frame++) {
      for (var channel = 0; channel < channels; channel++) {
        final value = sample?.call(frame, channel) ?? (frame * 100) - 3000;
        final at = (frame * channels + channel) * bytesPerSample;
        switch (bitsPerSample) {
          case 8:
            view.setUint8(at, ((value >> 8) + 128).clamp(0, 255));
          case 16:
            view.setInt16(at, value.clamp(-32768, 32767), Endian.little);
          case 24:
            final scaled = value << 8;
            view.setUint8(at, scaled & 0xFF);
            view.setUint8(at + 1, (scaled >> 8) & 0xFF);
            view.setInt8(at + 2, (scaled >> 16).clamp(-128, 127));
          case 32:
            view.setInt32(at, value << 16, Endian.little);
        }
      }
    }

    return buildWav(
      pcm: pcm,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    );
  }

  group('ImportFormat', () {
    test('recognises every extension it offers the picker', () {
      for (final extension in ImportFormat.pickerExtensions) {
        expect(ImportFormat.forPath('meeting.$extension'), isNotNull,
            reason: 'the picker must not offer a type import cannot open');
      }
    });

    test('matches case-insensitively and ignores the rest of the path', () {
      expect(ImportFormat.forPath('/tmp/Zoom Call.M4A'), ImportFormat.m4a);
      expect(ImportFormat.forPath('a.b.c/notes.final.mp3'), ImportFormat.mp3);
    });

    test('an unsupported or missing extension is null, not a guess', () {
      expect(ImportFormat.forPath('recording.txt'), isNull);
      expect(ImportFormat.forPath('recording'), isNull);
      expect(ImportFormat.forPath('recording.'), isNull);
    });

    test('only WAV skips decoding; video is flagged as video', () {
      expect(ImportFormat.wav.needsDecoding, isFalse);
      for (final format
          in ImportFormat.values.where((f) => f != ImportFormat.wav)) {
        expect(format.needsDecoding, isTrue);
      }
      expect(ImportFormat.mp4.isVideo, isTrue);
      expect(ImportFormat.m4a.isVideo, isFalse);
    });
  });

  group('normalizeWavForPipeline', () {
    test('a conforming WAV keeps its samples and its duration', () {
      final source = wav(sampleRate: 16000, channels: 1, frames: 16000);
      final out = normalizeWavForPipeline(source);
      final format = readWavHeader(out);

      expect(format.sampleRate, 16000);
      expect(format.channels, 1);
      expect(format.bitsPerSample, 16);
      expect(format.durationMs, 1000);
    });

    test('stereo is averaged down rather than one channel being dropped', () {
      // One speaker on each side: dropping a channel would drop a participant.
      final source = wav(
        sampleRate: 16000,
        channels: 2,
        frames: 4,
        sample: (frame, channel) => channel == 0 ? 1000 : 3000,
      );

      final out = normalizeWavForPipeline(source);
      final format = readWavHeader(out);
      final samples = Int16List.sublistView(
        Uint8List.sublistView(
            out, format.dataOffset, format.dataOffset + format.dataLength),
      );

      expect(format.channels, 1);
      expect(samples.every((s) => s == 2000), isTrue,
          reason: 'the mono mix is the average of both speakers');
    });

    test('44.1 kHz is resampled to 16 kHz, keeping the real duration', () {
      final source = wav(sampleRate: 44100, channels: 2, frames: 44100);
      final out = normalizeWavForPipeline(source);
      final format = readWavHeader(out);

      expect(format.sampleRate, 16000);
      // One second in, one second out — a rate error would stretch every timestamp in
      // the transcript along with the audio.
      expect(format.durationMs, closeTo(1000, 2));
    });

    test('8, 24 and 32-bit depths all arrive as 16-bit', () {
      for (final bits in [8, 24, 32]) {
        final out = normalizeWavForPipeline(
          wav(sampleRate: 16000, channels: 1, bitsPerSample: bits, frames: 50),
        );
        expect(readWavHeader(out).bitsPerSample, 16, reason: '$bits-bit input');
      }
    });

    test('the byte rate matches what the chunk planner budgets', () {
      final out = normalizeWavForPipeline(
        wav(sampleRate: 48000, channels: 2, frames: 48000),
      );
      final format = readWavHeader(out);

      expect(format.bytesPerSecond, PipelineAudio.bytesPerSecond,
          reason:
              'chunks are sized in bytes; a mismatch overflows the request cap');
      expect(durationMsForPipelineBytes(out.length), closeTo(1000, 2));
    });

    test('a non-PCM WAV is refused rather than misread as samples', () {
      final source = wav(sampleRate: 16000, channels: 1);
      // Rewrite the fmt chunk's audioFormat to IMA ADPCM.
      ByteData.sublistView(source).setUint16(20, 17, Endian.little);

      expect(
          () => normalizeWavForPipeline(source), throwsA(isA<WavException>()));
    });

    test('an empty recording produces an empty, still-valid WAV', () {
      final out = normalizeWavForPipeline(
        wav(sampleRate: 44100, channels: 1, frames: 0),
      );
      expect(readWavHeader(out).dataLength, 0);
    });
  });
}
