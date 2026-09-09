import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:transcript_core/transcript_core.dart';
import 'package:watcher/watcher.dart';

/// Imports recordings as they appear in a watched folder.
class FolderWatchService {
  FolderWatchService({
    required this.onFile,
    this.isSupported = ImportFormat.forPath,
  });

  final Future<void> Function(String path) onFile;
  final ImportFormat? Function(String path) isSupported;

  StreamSubscription<WatchEvent>? _subscription;
  String? _path;
  final _seen = <String>{};

  String? get path => _path;

  Future<void> start(String? folder) async {
    await stop();
    if (folder == null || folder.trim().isEmpty) return;
    final directory = Directory(folder);
    if (!directory.existsSync()) return;
    _path = directory.path;
    _subscription = DirectoryWatcher(directory.path).events.listen((event) {
      if (event.type == ChangeType.REMOVE) return;
      unawaited(_maybeImport(event.path));
    });
    await for (final entity in directory.list()) {
      if (entity is File) await _maybeImport(entity.path);
    }
  }

  Future<void> _maybeImport(String path) async {
    if (isSupported(path) == null) return;
    final normalized = p.normalize(path);
    if (!_seen.add(normalized)) return;
    if (!File(normalized).existsSync()) return;
    await onFile(normalized);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _path = null;
    _seen.clear();
  }
}
