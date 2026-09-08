import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart' as db;
import '../data/repository.dart';
import '../recording/recording_controller.dart';
import '../settings/settings_screen.dart';
import 'import_action.dart';
import 'note_screen.dart';
import 'record_screen.dart';
import 'today_screen.dart';

/// Everything recorded on this device. Local only — there is no account and no sync.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordings = ref.watch(recordingsProvider);
    final importEnabled = ref.watch(settingsStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Today',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TodayScreen()),
            ),
          ),
          if (importEnabled.workflowEnabled('audioImport') ||
              importEnabled.workflowEnabled('videoImport'))
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'Import a recording',
              onPressed: () => importRecordingFile(context, ref),
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'AI providers',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: recordings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not open the library.\n$e')),
        data: (items) {
          if (items.isEmpty) return const _EmptyLibrary();

          final filtered = _filtered(items);
          return Column(
            children: [
              const _ProcessingQueuePanel(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search notes, transcripts, and tasks',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _query = '';
                            }),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text('Nothing matches "$_query".',
                            style: Theme.of(context).textTheme.bodyMedium),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) =>
                            _RecordingTile(recording: filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<db.Recording> _filtered(List<db.Recording> items) {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return items;
    return items.where((r) {
      final noteText = _searchableNoteText(r.noteJson);
      return _contains(r.title, needle) ||
          _contains(r.transcriptText, needle) ||
          _contains(r.cleanedTranscriptText, needle) ||
          _contains(noteText, needle);
    }).toList();
  }

  static bool _contains(String? value, String needle) =>
      value?.toLowerCase().contains(needle) ?? false;

  /// Extracts user-authored note content instead of searching raw JSON keys and schema
  /// values. This keeps global search useful for summaries, decisions, questions, tasks,
  /// risks, concepts, and participants without a hosted index.
  static String _searchableNoteText(String? raw) {
    if (raw == null) return '';
    try {
      final note = jsonDecode(raw);
      if (note is! Map<String, dynamic>) return '';
      final values = <String>[];
      void add(Object? value) {
        if (value is String && value.trim().isNotEmpty) values.add(value);
      }

      final meta = note['meta'];
      if (meta is Map) {
        add(meta['title']);
        add(meta['summary']);
      }
      for (final section in _maps(note['sections'])) {
        add(section['heading']);
        for (final bullet in section['bullets'] as List? ?? const []) {
          add(bullet);
        }
      }
      for (final decision in _maps(note['decisions'])) {
        add(decision['statement']);
        add(decision['rationale']);
      }
      for (final question in _maps(note['openQuestions'])) {
        add(question['question']);
      }
      for (final task in _maps(note['tasks'])) {
        add(task['title']);
        add(task['detail']);
        add(task['assigneeRaw']);
      }
      for (final risk in _maps(note['risks'])) {
        add(risk['description']);
      }
      for (final concept in _maps(note['keyConcepts'])) {
        add(concept['term']);
        add(concept['explanation']);
      }
      for (final participant in _maps(note['participants'])) {
        add(participant['displayName']);
        for (final alias in participant['aliases'] as List? ?? const []) {
          add(alias);
        }
      }
      return values.join(' ');
    } on Object {
      return '';
    }
  }

  static Iterable<Map<String, dynamic>> _maps(Object? value) sync* {
    if (value is List) {
      for (final item in value) {
        if (item is Map) yield Map<String, dynamic>.from(item);
      }
    }
  }
}

class _ProcessingQueuePanel extends ConsumerStatefulWidget {
  const _ProcessingQueuePanel();

  @override
  ConsumerState<_ProcessingQueuePanel> createState() =>
      _ProcessingQueuePanelState();
}

class _ProcessingQueuePanelState extends ConsumerState<_ProcessingQueuePanel> {
  late Future<List<ProcessingQueueItem>> _queue =
      ref.read(repositoryProvider).processingQueue();

  void _refresh() {
    if (mounted) {
      setState(() {
        _queue = ref.read(repositoryProvider).processingQueue();
      });
    }
  }

  Future<void> _resume(ProcessingQueueItem item) async {
    final repository = ref.read(repositoryProvider);
    if (item.retryable > 0) {
      await repository.retryRecording(item.recording.id);
    }
    await ref
        .read(recordingControllerProvider.notifier)
        .resumeRecording(item.recording.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProcessingQueueItem>>(
      future: _queue,
      builder: (context, snapshot) {
        final items = snapshot.data;
        if (items == null || items.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Row(
                  children: [
                    const Icon(Icons.sync, size: 18),
                    const SizedBox(width: 8),
                    Text('Processing queue', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    Text('${items.length}', style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
              for (final item in items)
                ListTile(
                  dense: true,
                  title: Text(
                    item.recording.title.isEmpty
                        ? 'Untitled recording'
                        : item.recording.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.failed > 0
                            ? '${item.failed} failed chunk${item.failed == 1 ? '' : 's'}'
                            : '${item.completed} of ${item.total} chunks complete',
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: item.fraction),
                    ],
                  ),
                  trailing: TextButton(
                    onPressed: () => _resume(item),
                    child: Text(item.retryable > 0 ? 'Retry now' : 'Resume'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none,
                size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text('Nothing recorded yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Recordings stay on this device. You can also import one made '
              'elsewhere — a meeting exported from Zoom or Teams, or a lecture.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingTile extends ConsumerWidget {
  const _RecordingTile({required this.recording});

  final db.Recording recording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final structured = recording.noteJson != null;
    final duration = Duration(milliseconds: recording.durationMs);
    final priorityQueueEnabled =
        ref.watch(settingsStoreProvider).workflowEnabled('priorityQueue');

    return Dismissible(
      key: ValueKey(recording.id),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: theme.colorScheme.errorContainer,
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 20),
            child: Icon(Icons.delete_outline),
          ),
        ),
      ),
      confirmDismiss: (_) async =>
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete this recording?'),
              content: const Text(
                  'The audio and its notes are removed from this device. This cannot '
                  'be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Keep'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false,
      onDismissed: (_) {
        final messenger = ScaffoldMessenger.of(context);
        unawaited(
          ref.read(repositoryProvider).delete(recording.id).then((_) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Recording deleted')),
            );
          }),
        );
      },
      child: ListTile(
        title: Text(
          recording.title.isEmpty ? 'Untitled recording' : recording.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${DateFormat.yMMMd().add_jm().format(recording.startedAt)} · '
          '${formatDuration(duration)}',
        ),
        leading: Icon(
          structured ? Icons.notes : Icons.hourglass_empty,
          color: structured
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        trailing: !structured && priorityQueueEnabled
            ? IconButton(
                icon: Icon(
                  recording.priority ? Icons.bolt : Icons.bolt_outlined,
                  color: recording.priority ? theme.colorScheme.primary : null,
                ),
                tooltip: recording.priority
                    ? 'Urgent — will transcribe before the rest of the backlog'
                    : 'Mark urgent',
                onPressed: () => ref
                    .read(repositoryProvider)
                    .setPriority(recording.id, !recording.priority),
              )
            : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NoteScreen(recordingId: recording.id),
          ),
        ),
      ),
    );
  }
}
