import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart' as db;
import '../recording/recording_controller.dart';
import '../settings/settings_screen.dart';
import 'note_screen.dart';
import 'record_screen.dart';

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
    final searchEnabled =
        ref.watch(settingsStoreProvider).workflowEnabled('searchableHistory');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
        actions: [
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

          final filtered = searchEnabled ? _filtered(items) : items;
          return Column(
            children: [
              if (searchEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search recordings and transcripts',
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
      return r.title.toLowerCase().contains(needle) ||
          (r.transcriptText?.toLowerCase().contains(needle) ?? false) ||
          (r.cleanedTranscriptText?.toLowerCase().contains(needle) ?? false);
    }).toList();
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
              'Recordings stay on this device.',
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
      confirmDismiss: (_) async => await showDialog<bool>(
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
