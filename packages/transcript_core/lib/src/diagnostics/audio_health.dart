/// What the recorder looked like at one instant.
class AudioSample {
  const AudioSample({
    required this.elapsed,
    required this.amplitudeDb,
    required this.bytesWritten,
  });

  /// Wall-clock time since recording started.
  final Duration elapsed;

  /// Current level in dBFS, as the platform reports it.
  final double amplitudeDb;

  /// Size of the file being written, in bytes.
  final int bytesWritten;
}

/// Something worth saying about the capture.
enum AudioFinding {
  /// Nothing but the noise floor for a sustained stretch. On its own this is only
  /// suspicious — a muted microphone and a quiet room look identical — so it is a
  /// warning, not a failure.
  silence,

  /// Silent *and* the file has stopped growing.
  ///
  /// This is the pair that distinguishes a dead capture from a quiet one: a muted or
  /// idle microphone still writes zero-valued samples at the full byte rate, so a
  /// stream that has stopped producing bytes altogether is no longer a stream. This is
  /// the signal for a microphone unplugged, stolen by another app, or torn down by the
  /// OS mid-recording.
  microphoneLost,

  /// A short deficit against the expected byte rate, with the rate recovering after.
  /// Samples that should have been written were not — the capture buffer filled faster
  /// than it was drained and the overflow was discarded.
  bufferOverrun,

  /// A deficit that does not recover. The stream is producing fewer bytes per second
  /// than the configured format calls for, which in practice means it is running at a
  /// different sample rate than was asked for.
  sampleRateDrop,

  /// The byte rate came back to normal after a [bufferOverrun] or [sampleRateDrop].
  /// Logged so a reader can bound the damage instead of assuming the rest of the
  /// recording is suspect.
  recovered,
}

/// Watches a recording for the hardware failures the platform does not announce.
///
/// ## Why this is derived rather than reported
///
/// The recorder plugin raises no event for a dropped buffer, a sample-rate
/// renegotiation, or a microphone that disappears; on most platforms the capture simply
/// goes quiet or the stream stalls. So the failures are inferred from the two things
/// that *are* observable — the level meter and the size of the file on disk — by
/// checking them against what the configured format says should be happening.
///
/// That inference is stated plainly in the log rather than dressed up as a hardware
/// report, because a reader who believes the OS told us the sample rate dropped will
/// stop looking for the real cause.
///
/// Pure and synchronous: every threshold here is testable without a microphone.
class AudioHealthMonitor {
  AudioHealthMonitor({
    this.sampleRate = 16000,
    this.channels = 1,
    this.bytesPerSample = 2,
    this.silenceFloorDb = -100,
    this.silenceSamplesBeforeWarning = 30,
    this.rateTolerance = 0.85,
    this.intervalsBeforeRateDrop = 3,
  });

  /// The format that was asked for. Everything here is measured against it.
  final int sampleRate;
  final int channels;
  final int bytesPerSample;

  /// At or below this the platform is reporting its floor rather than a quiet room.
  final double silenceFloorDb;

  /// Roughly three seconds at a 100ms meter. Long enough that a pause between
  /// sentences never trips it.
  final int silenceSamplesBeforeWarning;

  /// How far below the expected byte rate counts as a deficit. Not 1.0: the file size
  /// and the clock are sampled at slightly different moments, and a little slack keeps
  /// that from reading as a fault every interval.
  final double rateTolerance;

  /// A deficit shorter than this is transient — dropped buffers. Longer, and the stream
  /// itself is running slow.
  final int intervalsBeforeRateDrop;

  /// Bytes the format should produce per second: 32,000 for 16kHz mono 16-bit.
  int get expectedBytesPerSecond => sampleRate * channels * bytesPerSample;

  AudioSample? _previous;
  int _silentRun = 0;
  int _deficitRun = 0;
  bool _reportedSilence = false;
  bool _reportedLoss = false;
  bool _reportedRateDrop = false;
  bool _inDeficit = false;

  /// The byte rate over the most recent interval, or null before two samples exist.
  double? get lastBytesPerSecond => _lastRate;
  double? _lastRate;

  /// Feeds one observation and returns whatever it newly established.
  ///
  /// Returns findings only on transitions, never on every sample: a monitor that
  /// repeats "still silent" 600 times buries the line that matters.
  List<AudioFinding> observe(AudioSample sample) {
    final findings = <AudioFinding>[];
    final previous = _previous;
    _previous = sample;

    final silent = sample.amplitudeDb <= silenceFloorDb;
    _silentRun = silent ? _silentRun + 1 : 0;
    if (!silent) {
      _reportedSilence = false;
      _reportedLoss = false;
    }

    if (previous == null) return findings;

    final elapsedMs = (sample.elapsed - previous.elapsed).inMilliseconds;
    if (elapsedMs <= 0) return findings;

    final grew = sample.bytesWritten - previous.bytesWritten;
    final rate = grew * 1000 / elapsedMs;
    _lastRate = rate;

    // A stream that has stopped producing bytes while silent is not a quiet room.
    if (silent && grew <= 0 && _silentRun >= silenceSamplesBeforeWarning) {
      if (!_reportedLoss) {
        _reportedLoss = true;
        findings.add(AudioFinding.microphoneLost);
      }
      return findings;
    }

    if (silent &&
        _silentRun >= silenceSamplesBeforeWarning &&
        !_reportedSilence) {
      _reportedSilence = true;
      findings.add(AudioFinding.silence);
    }

    final short = rate < expectedBytesPerSecond * rateTolerance;
    if (short) {
      _deficitRun++;
      _inDeficit = true;
      if (_deficitRun >= intervalsBeforeRateDrop && !_reportedRateDrop) {
        _reportedRateDrop = true;
        findings.add(AudioFinding.sampleRateDrop);
      }
    } else {
      if (_inDeficit) {
        // A deficit that ended before it looked like a rate change: buffers were lost
        // and the stream caught up.
        if (!_reportedRateDrop) findings.add(AudioFinding.bufferOverrun);
        if (_reportedRateDrop) findings.add(AudioFinding.recovered);
      }
      _deficitRun = 0;
      _inDeficit = false;
      _reportedRateDrop = false;
    }

    return findings;
  }

  /// Forgets everything. Called when a recording starts, so one session's findings
  /// never leak into the next.
  void reset() {
    _previous = null;
    _silentRun = 0;
    _deficitRun = 0;
    _lastRate = null;
    _reportedSilence = false;
    _reportedLoss = false;
    _reportedRateDrop = false;
    _inDeficit = false;
  }
}
