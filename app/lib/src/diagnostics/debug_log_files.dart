import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:transcript_core/transcript_core.dart';

/// The debug log on disk: one JSON-lines file per UTC day.
///
/// ## Why day files rather than one rolling file
///
/// The retention rule is "nothing older than 48 hours", and enforcing that on a single
/// file means reading it, filtering it and writing it back — on an hourly timer, against
/// a file that may be megabytes, on a phone that is already busy recording. Day files
/// turn the common case into `File.delete()`: whole days fall out of the window at once.
/// Only the file straddling the cutoff is ever rewritten, and only when it actually
/// holds something expired.
///
/// The window is still enforced to the entry, not to the day — [read] and [purgeBefore]
/// both filter by timestamp — so "48 hours" means 48 hours rather than "about two days".
///
/// ## Why it lives beside the crash reports
///
/// Same directory, same guarantee: written to the app's own support directory, never
/// uploaded, readable in full by the user before they decide to send it. Debug Mode
/// would otherwise be a second, weaker privacy story running alongside the first.
class DayFileDebugSink implements DebugSink {
  DayFileDebugSink({
    required Directory root,
    this.maxBytesPerDay = 16 * 1024 * 1024,
  }) : _root = root;

  final Directory _root;

  /// A ceiling per day file. Verbose logging of a long meeting should not be able to
  /// fill a device that is in the middle of recording one — the failure mode of a
  /// diagnostic tool must never be worse than the bug it was turned on to find.
  final int maxBytesPerDay;

  static final RegExp _namePattern =
      RegExp(r'^debug-(\d{4})-(\d{2})-(\d{2})\.jsonl$');

  @override
  Future<void> append(List<DebugEntry> batch) async {
    if (batch.isEmpty) return;
    await _root.create(recursive: true);

    // Grouped so a batch spanning midnight still costs one write per file rather than
    // one per entry.
    final byDay = <String, StringBuffer>{};
    for (final entry in batch) {
      final buffer = byDay.putIfAbsent(_dayOf(entry.at), () => StringBuffer());
      buffer.writeln(jsonEncode(entry.toJson()));
    }

    for (final day in byDay.entries) {
      final file = File(p.join(_root.path, 'debug-${day.key}.jsonl'));
      await file.writeAsString(day.value.toString(), mode: FileMode.append);
      await _capSize(file);
    }
  }

  @override
  Future<void> purgeBefore(DateTime cutoff) async {
    if (!_root.existsSync()) return;
    final cutoffDay = _dayOf(cutoff);

    for (final file in _dayFiles()) {
      final day = _dayOf(file.$2);
      if (day.compareTo(cutoffDay) < 0) {
        // Every entry in it predates the window.
        await file.$1.delete();
        continue;
      }
      if (day != cutoffDay) continue;

      // The file straddling the cutoff: rewrite it, but only if it needs it.
      final kept = (await _entriesIn(file.$1))
          .where((e) => !e.at.isBefore(cutoff))
          .toList();
      final total = await _countLines(file.$1);
      if (kept.length == total) continue;
      await _replace(file.$1, kept);
    }
  }

  @override
  Future<List<DebugEntry>> read({DateTime? since}) async {
    final out = <DebugEntry>[];
    for (final file in _dayFiles()) {
      out.addAll(await _entriesIn(file.$1));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    if (since == null) return out;
    return out.where((e) => !e.at.isBefore(since)).toList();
  }

  @override
  Future<void> clear() async {
    for (final file in _dayFiles()) {
      await file.$1.delete();
    }
  }

  /// Writes everything retained into one readable file and returns it.
  ///
  /// Formatted for a person rather than a parser: the point of exporting is to paste it
  /// into a bug report, and JSON-lines is not what anyone wants to read there. [header]
  /// carries the app version and platform, which the caller knows and this does not.
  Future<File> export({String? header, DateTime? since}) async {
    final entries = await read(since: since);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final file = File(p.join(_root.path, 'debug-export-$stamp.log'));
    await _root.create(recursive: true);

    final buffer = StringBuffer();
    if (header != null) buffer..writeln(header)..writeln();
    buffer.writeln('${entries.length} entries');
    buffer.writeln('-' * 72);
    for (final entry in entries) {
      buffer.writeln(entry.format());
    }
    await file.writeAsString(buffer.toString(), flush: true);
    return file;
  }

  /// How much the log is currently taking up, for the screen that offers to clear it.
  int get bytesOnDisk {
    var total = 0;
    for (final file in _dayFiles()) {
      try {
        total += file.$1.lengthSync();
      } on FileSystemException {
        continue;
      }
    }
    return total;
  }

  /// Day files with the date each one covers, oldest first. Anything else in the
  /// directory — the crash reports, an old export — is ignored rather than parsed.
  List<(File, DateTime)> _dayFiles() {
    if (!_root.existsSync()) return const [];
    final out = <(File, DateTime)>[];
    for (final entity in _root.listSync()) {
      if (entity is! File) continue;
      final match = _namePattern.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      out.add((
        entity,
        DateTime.utc(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        )
      ));
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }

  Future<List<DebugEntry>> _entriesIn(File file) async {
    if (!file.existsSync()) return const [];
    final out = <DebugEntry>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, Object?>) continue;
        final entry = DebugEntry.fromJson(decoded);
        if (entry != null) out.add(entry);
      } on FormatException {
        // A line torn in half by a process the OS killed mid-write. Skipping it costs
        // one entry; throwing would cost the whole log.
        continue;
      }
    }
    return out;
  }

  Future<int> _countLines(File file) async {
    if (!file.existsSync()) return 0;
    final lines = await file.readAsLines();
    return lines.where((l) => l.trim().isNotEmpty).length;
  }

  /// Drops the oldest half of a day file that has outgrown its ceiling.
  ///
  /// Half rather than just enough: trimming to exactly the cap would rewrite the file
  /// on nearly every append once it got there.
  Future<void> _capSize(File file) async {
    int length;
    try {
      length = await file.length();
    } on FileSystemException {
      return;
    }
    if (length <= maxBytesPerDay) return;

    final entries = await _entriesIn(file);
    if (entries.length < 2) return;
    final kept = entries.sublist(entries.length ~/ 2);
    await _replace(file, [
      DebugEntry(
        at: kept.first.at,
        level: DebugLevel.warning,
        tag: 'log',
        message: 'the log file reached its ceiling and its oldest half was dropped',
        fields: {'dropped': entries.length - kept.length, 'capBytes': maxBytesPerDay},
      ),
      ...kept,
    ]);
  }

  Future<void> _replace(File file, List<DebugEntry> entries) async {
    if (entries.isEmpty) {
      if (file.existsSync()) await file.delete();
      return;
    }
    final text =
        entries.map((e) => jsonEncode(e.toJson())).join('\n');
    await file.writeAsString('$text\n', flush: true);
  }

  static String _dayOf(DateTime at) {
    final utc = at.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}
