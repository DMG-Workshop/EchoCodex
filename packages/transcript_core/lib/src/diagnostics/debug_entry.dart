import '../privacy/redaction.dart';

/// How much attention a line deserves.
///
/// Three levels, not seven. A level nobody can define the boundary of is a level that
/// gets chosen at random, and a log where `debug` and `trace` are used interchangeably
/// cannot be filtered usefully by the person reading it at 2am.
enum DebugLevel {
  /// A checkpoint that was reached. The bulk of the log, and the part that makes a
  /// failure legible: the last INFO before an ERROR is what says how far it got.
  info,

  /// Something the app recovered from, or a measurement outside its expected range.
  /// Worth reading when something else breaks; not worth acting on by itself.
  warning,

  /// Something failed. Every ERROR should name what was being attempted, not only what
  /// went wrong.
  error,
}

/// One line of the diagnostic log.
///
/// Structured rather than pre-formatted, for two reasons. A viewer can filter and group
/// by [tag] and [fields] without parsing English, and — more importantly — the fields
/// pass through [Redactor] individually, so a value that turns out to hold a key is
/// scrubbed without mangling the message around it.
class DebugEntry {
  const DebugEntry({
    required this.at,
    required this.level,
    required this.tag,
    required this.message,
    this.fields = const {},
  });

  final DateTime at;
  final DebugLevel level;

  /// The subsystem: 'audio', 'queue', 'structuring'. Kept to a short closed set by
  /// convention so filtering by it is actually possible.
  final String tag;

  final String message;

  /// Measurements and identifiers. Values are restricted to JSON scalars by
  /// convention; anything else is stringified on the way out rather than trusted to
  /// encode.
  final Map<String, Object?> fields;

  /// A copy with every string scrubbed.
  ///
  /// Applied at the sink rather than the call site, so no call site can forget. This is
  /// the line between a diagnostic log and the app's largest privacy hole: verbose
  /// logging of a transcription pipeline means transcript text and provider keys move
  /// through here, and the app's whole claim is that it collects nothing.
  DebugEntry scrubbed(Redactor redactor) => DebugEntry(
        at: at,
        level: level,
        tag: tag,
        message: redactor.scrub(message),
        fields: {
          for (final entry in fields.entries)
            entry.key: entry.value is String
                ? redactor.scrub(entry.value! as String)
                : entry.value,
        },
      );

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
        if (fields.isNotEmpty) 'fields': fields,
      };

  /// Parses a stored line. Returns null rather than throwing for anything malformed: a
  /// half-written line from a process the OS killed mid-flush must not make the rest of
  /// the log unreadable.
  static DebugEntry? fromJson(Map<String, Object?> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) return null;
    final level =
        DebugLevel.values.where((l) => l.name == json['level']).firstOrNull;
    if (level == null) return null;
    final fields = json['fields'];
    return DebugEntry(
      at: at,
      level: level,
      tag: json['tag'] as String? ?? '',
      message: json['message'] as String? ?? '',
      fields: fields is Map<String, Object?> ? fields : const {},
    );
  }

  /// One human-readable line, for the viewer and for the exported file's header.
  String format() {
    final buffer = StringBuffer()
      ..write(at.toUtc().toIso8601String())
      ..write('  ')
      ..write(level.name.toUpperCase().padRight(7))
      ..write(tag.padRight(12))
      ..write(message);
    for (final field in fields.entries) {
      buffer.write('  ${field.key}=${field.value}');
    }
    return buffer.toString();
  }
}

/// Where entries go once they leave the buffer.
///
/// An interface so the buffering, batching and purge policy can be tested with no
/// filesystem at all, and so a test can assert on what *would* have been written.
abstract class DebugSink {
  /// Appends a batch. Called with everything buffered since the last flush, so an
  /// implementation writes once rather than once per entry.
  Future<void> append(List<DebugEntry> batch);

  /// Drops anything recorded before [cutoff].
  Future<void> purgeBefore(DateTime cutoff);

  /// Everything still retained, oldest first.
  Future<List<DebugEntry>> read();

  Future<void> clear();
}

/// A sink that accepts everything and keeps nothing.
///
/// The default for a [DebugLog] nobody wired up. It exists so code that logs can take a
/// logger unconditionally — `RecorderService`, the chunk pipeline, a widget test —
/// instead of every call site carrying a null check for a dependency that is only ever
/// absent in tests.
class NullDebugSink implements DebugSink {
  const NullDebugSink();

  @override
  Future<void> append(List<DebugEntry> batch) async {}

  @override
  Future<void> purgeBefore(DateTime cutoff) async {}

  @override
  Future<List<DebugEntry>> read() async => const [];

  @override
  Future<void> clear() async {}
}
