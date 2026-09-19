import 'dart:async';

import '../privacy/redaction.dart';
import 'debug_entry.dart';

/// The one logger, and the one flag that switches it on.
///
/// ## Why the whole design is a single boolean field
///
/// Debug Mode instruments the two hottest paths in the app: an amplitude callback at
/// 10Hz and a transcription loop that moves megabytes. Overhead there is not an
/// abstract concern — it is the difference between diagnosing a dropout and causing
/// one. So the gate is a plain `bool` on one long-lived object: no provider read, no
/// map lookup, no `SharedPreferences` round trip, nothing that can throw. The flag is
/// *pushed* here when the user flips it, never *pulled* at a call site.
///
/// That alone is not enough, because the expensive part of a log call is usually the
/// argument, not the call. `log.info('queue', 'chunk ${c.index} of ${all.length}')`
/// builds that string whether or not anyone wants it. So every method here takes a
/// **closure** that builds the message, and the closure runs only when the log is on.
/// When it is off the cost is one branch and one closure allocation.
///
/// Where even that is too much — a callback firing every 100ms for an hour — call sites
/// guard on [isOn] first, so no closure is allocated either:
///
/// ```dart
/// if (log.isOn) log.info('audio', () => 'level $db');
/// ```
///
/// Both forms are used in this codebase, deliberately: the guard where the rate is
/// high, the closure everywhere else, because the guard is easy to forget to remove and
/// reads worse.
///
/// ## Why it buffers
///
/// A line is appended to an in-memory ring and written out in batches. One file append
/// per log line would turn a verbose mode into an I/O storm on exactly the device that
/// is already struggling. The ring is bounded, so a runaway loop in the code being
/// diagnosed cannot exhaust memory in the app doing the diagnosing — the failure mode
/// of a debug tool must never be worse than the bug.
class DebugLog {
  DebugLog({
    DebugSink? sink,
    Redactor? redactor,
    this.bufferLimit = 2000,
    this.flushEvery = const Duration(seconds: 2),
    this.retention = const Duration(hours: 48),
    this.purgeEvery = const Duration(hours: 1),
    DateTime Function()? clock,
  })  : sink = sink ?? const NullDebugSink(),
        redactor = redactor ?? Redactor(),
        _now = clock ?? DateTime.now;

  final DebugSink sink;

  /// Applied to every entry on the way out. See [DebugEntry.scrubbed].
  final Redactor redactor;

  /// How many entries may wait in memory. On overflow the *oldest* are dropped and a
  /// warning takes their place, because when a log outruns its own buffer the recent
  /// lines are the ones explaining why.
  final int bufferLimit;

  final Duration flushEvery;

  /// How far back the log is kept. Older entries are purged on a timer and at startup.
  final Duration retention;

  final Duration purgeEvery;

  final DateTime Function() _now;

  final List<DebugEntry> _buffer = [];
  Timer? _flushTimer;
  Timer? _purgeTimer;
  Future<void>? _inFlight;
  int _dropped = 0;
  bool _enabled = false;

  /// Whether anything is being recorded. The hot-path guard.
  bool get isOn => _enabled;

  /// How many entries are waiting to be written. Exposed for the diagnostics screen and
  /// for tests; not part of the logging contract.
  int get pending => _buffer.length;

  /// Turns recording on or off.
  ///
  /// Switching off flushes what is already buffered rather than discarding it: the
  /// lines leading up to the moment the user gave up and turned it off are the ones
  /// worth keeping.
  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    if (value) {
      _flushTimer ??= Timer.periodic(flushEvery, (_) => unawaited(flush()));
      _purgeTimer ??= Timer.periodic(purgeEvery, (_) => unawaited(purge()));
      await purge();
    } else {
      _flushTimer?.cancel();
      _flushTimer = null;
      _purgeTimer?.cancel();
      _purgeTimer = null;
      await flush();
    }
  }

  void info(String tag, Object? Function() message,
          {Map<String, Object?> Function()? fields}) =>
      _add(DebugLevel.info, tag, message, fields);

  void warning(String tag, Object? Function() message,
          {Map<String, Object?> Function()? fields}) =>
      _add(DebugLevel.warning, tag, message, fields);

  /// Records a failure.
  ///
  /// [error] and [stack] are taken as values rather than a closure because at an error
  /// site they already exist — there is nothing to defer — and because forgetting to
  /// include them is the most common way a log ends up unactionable.
  void error(
    String tag,
    Object? Function() message, {
    Object? error,
    StackTrace? stack,
    Map<String, Object?> Function()? fields,
  }) {
    if (!_enabled) return;
    _add(
      DebugLevel.error,
      tag,
      message,
      () => {
        ...?fields?.call(),
        if (error != null) 'error': error.toString(),
        if (stack != null) 'stack': stack.toString(),
      },
    );
  }

  void _add(
    DebugLevel level,
    String tag,
    Object? Function() message,
    Map<String, Object?> Function()? fields,
  ) {
    if (!_enabled) return;
    // Building the line is the caller's code running inside our try: a toString() that
    // throws must not take down the recording it was describing.
    DebugEntry entry;
    try {
      entry = DebugEntry(
        at: _now(),
        level: level,
        tag: tag,
        message: message()?.toString() ?? '',
        fields: fields?.call() ?? const {},
      );
    } catch (e) {
      entry = DebugEntry(
        at: _now(),
        level: DebugLevel.warning,
        tag: tag,
        message: 'a log line could not be built',
        fields: {'error': e.toString()},
      );
    }

    _buffer.add(entry);
    if (_buffer.length > bufferLimit) {
      _buffer.removeAt(0);
      _dropped++;
    }
    // Don't wait for the timer when the buffer is filling faster than it drains.
    if (_buffer.length >= bufferLimit) unawaited(flush());
  }

  /// Writes everything buffered.
  ///
  /// Serialised against itself: two overlapping flushes would interleave batches and
  /// put the file out of chronological order. A caller that flushes while one is in
  /// flight simply awaits the one already running, then takes whatever arrived after.
  Future<void> flush() {
    final running = _inFlight;
    if (running != null) return running.then((_) => _drain());
    return _drain();
  }

  Future<void> _drain() {
    if (_buffer.isEmpty) return Future<void>.value();

    final batch = [
      if (_dropped > 0)
        DebugEntry(
          at: _now(),
          level: DebugLevel.warning,
          tag: 'log',
          message: 'the log buffer overflowed and dropped its oldest entries',
          fields: {'dropped': _dropped},
        ),
      ..._buffer,
    ];
    _buffer.clear();
    _dropped = 0;

    // Redaction happens here, once per batch, off the call site's critical path.
    final scrubbed = [for (final entry in batch) entry.scrubbed(redactor)];

    final future = sink.append(scrubbed).catchError((Object _) {
      // A log that cannot write is not a reason to fail the recording it was watching.
      // The entries are already gone from the buffer, which is the right trade: keeping
      // them would grow without bound against a disk that is not accepting writes.
    });
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  /// Drops anything past [retention].
  Future<void> purge() => sink.purgeBefore(_now().subtract(retention));

  /// Everything on disk right now, oldest first, flushing first so the caller sees the
  /// lines that have not been written yet.
  Future<List<DebugEntry>> read() async {
    await flush();
    return sink.read();
  }

  Future<void> clear() async {
    _buffer.clear();
    _dropped = 0;
    await sink.clear();
  }

  /// Stops the timers. Flushes on the way out for the same reason [setEnabled] does.
  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _purgeTimer?.cancel();
    _purgeTimer = null;
    await flush();
  }
}
