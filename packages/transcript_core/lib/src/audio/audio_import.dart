import 'dart:typed_data';

import 'wav.dart';

/// The one audio format the rest of the pipeline understands.
///
/// Not an arbitrary choice: [ChunkerConfig] budgets chunk sizes at 32 kB/s, the native
/// Whisper decoder is fed this directly, and every speech engine resamples to 16 kHz mono
/// internally anyway. Rather than teach the planner, the slicer and the decoder about
/// whatever a user happens to import, imported audio is converted to exactly what the
/// recorder itself produces.
class PipelineAudio {
  const PipelineAudio._();

  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitsPerSample = 16;

  /// 32 kB per second, which is what the chunk planner budgets with.
  static const int bytesPerSecond =
      sampleRate * channels * (bitsPerSample ~/ 8);
}

/// A container the app will take in.
///
/// The split that matters is [needsDecoding]: a WAV carries PCM this package can convert
/// in pure Dart, while everything else is a compressed stream that only the platform's
/// own codecs can open.
enum ImportFormat {
  wav(
    extensions: {'wav', 'wave'},
    mimeType: 'audio/wav',
    label: 'WAV',
    needsDecoding: false,
  ),
  mp3(extensions: {'mp3'}, mimeType: 'audio/mpeg', label: 'MP3'),
  m4a(extensions: {'m4a'}, mimeType: 'audio/mp4', label: 'M4A'),
  aac(extensions: {'aac'}, mimeType: 'audio/aac', label: 'AAC'),
  flac(extensions: {'flac'}, mimeType: 'audio/flac', label: 'FLAC'),
  ogg(extensions: {'ogg', 'oga'}, mimeType: 'audio/ogg', label: 'OGG'),
  mp4(
    extensions: {'mp4', 'm4v', 'mov'},
    mimeType: 'video/mp4',
    label: 'MP4 video',
    isVideo: true,
  );

  const ImportFormat({
    required this.extensions,
    required this.mimeType,
    required this.label,
    this.needsDecoding = true,
    this.isVideo = false,
  });

  final Set<String> extensions;
  final String mimeType;
  final String label;

  /// True when only a platform codec can turn this into PCM.
  final bool needsDecoding;

  /// A video container: the audio track is extracted and the video discarded.
  final bool isVideo;

  /// Every extension the file picker should offer, lower-case and without dots.
  static List<String> get pickerExtensions => [
        for (final format in values) ...format.extensions,
      ];

  /// The format for a path, or null when the extension is not one we accept.
  ///
  /// Matched on extension rather than by sniffing content: the picker already filters on
  /// extension, and a file whose bytes disagree with its name fails later at the decoder
  /// with a clearer message than a guess would produce here.
  static ImportFormat? forPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    final extension = path.substring(dot + 1).toLowerCase();
    for (final format in values) {
      if (format.extensions.contains(extension)) return format;
    }
    return null;
  }
}

/// Rewrites a WAV as 16 kHz mono PCM16, the format the pipeline expects.
///
/// Returns a complete, canonical WAV — imported files carry `LIST` and other metadata
/// chunks that a fixed-offset reader elsewhere would read as audio, so the header is
/// always rebuilt rather than patched.
///
/// Throws [WavException] for anything that is not PCM WAV, which includes a float or
/// ADPCM payload: converting those silently would be worse than saying so.
Uint8List normalizeWavForPipeline(Uint8List source) {
  final format = readWavHeader(source);
  if (format.channels < 1) {
    throw const WavException('WAV declares no channels');
  }

  final samples = _toMonoInt16(source, format);
  final resampled = format.sampleRate == PipelineAudio.sampleRate
      ? samples
      : _resample(samples, format.sampleRate, PipelineAudio.sampleRate);

  return buildWav(
    pcm: Uint8List.sublistView(resampled),
    sampleRate: PipelineAudio.sampleRate,
    channels: PipelineAudio.channels,
    bitsPerSample: PipelineAudio.bitsPerSample,
  );
}

/// How long a normalized WAV of this many bytes runs, in milliseconds.
int durationMsForPipelineBytes(int byteLength) =>
    ((byteLength - 44).clamp(0, 1 << 62) / PipelineAudio.bytesPerSecond * 1000)
        .round();

/// Reads any supported integer PCM depth and averages the channels down to mono.
///
/// Averaging rather than taking the left channel: a meeting recorded in stereo often has
/// one speaker louder on each side, and dropping a channel drops a participant.
Int16List _toMonoInt16(Uint8List source, WavFormat format) {
  final bytesPerSample = format.bitsPerSample ~/ 8;
  if (bytesPerSample == 0) {
    throw WavException('unsupported bit depth ${format.bitsPerSample}');
  }

  final frameBytes = bytesPerSample * format.channels;
  final frames = format.dataLength ~/ frameBytes;
  final out = Int16List(frames);
  final view = ByteData.sublistView(source);

  for (var frame = 0; frame < frames; frame++) {
    final base = format.dataOffset + frame * frameBytes;
    var sum = 0;
    for (var channel = 0; channel < format.channels; channel++) {
      sum += _sampleAt(
          view, base + channel * bytesPerSample, format.bitsPerSample);
    }
    out[frame] = (sum / format.channels).round().clamp(-32768, 32767);
  }
  return out;
}

/// One sample, scaled to signed 16-bit whatever depth it was stored at.
int _sampleAt(ByteData view, int at, int bitsPerSample) {
  switch (bitsPerSample) {
    case 8:
      // 8-bit WAV is unsigned, centred on 128.
      return (view.getUint8(at) - 128) << 8;
    case 16:
      return view.getInt16(at, Endian.little);
    case 24:
      final value = view.getUint8(at) |
          (view.getUint8(at + 1) << 8) |
          (view.getInt8(at + 2) << 16);
      return value >> 8;
    case 32:
      return view.getInt32(at, Endian.little) >> 16;
    default:
      throw WavException('unsupported bit depth $bitsPerSample');
  }
}

/// Linear resampling.
///
/// Deliberately not a windowed-sinc filter: the output feeds speech recognition, not a
/// listener, and every engine band-limits to 8 kHz of speech content anyway. What matters
/// is that the sample count is right — a rate error stretches the audio and every
/// timestamp in the transcript with it.
Int16List _resample(Int16List input, int fromRate, int toRate) {
  if (input.isEmpty) return input;
  if (fromRate <= 0) throw const WavException('WAV declares no sample rate');

  final outLength = (input.length * toRate / fromRate).floor();
  if (outLength <= 0) return Int16List(0);

  final out = Int16List(outLength);
  final step = fromRate / toRate;

  for (var i = 0; i < outLength; i++) {
    final position = i * step;
    final left = position.floor();
    final right = left + 1;
    final fraction = position - left;

    final a = input[left.clamp(0, input.length - 1)];
    final b = input[right.clamp(0, input.length - 1)];
    out[i] = (a + (b - a) * fraction).round().clamp(-32768, 32767);
  }
  return out;
}
