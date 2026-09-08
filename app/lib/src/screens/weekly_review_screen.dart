import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:transcript_core/transcript_core.dart';

import '../data/repository.dart';
import '../recording/recording_controller.dart';
import 'task_editor.dart';

class WeeklyReviewScreen extends ConsumerWidget {
  const WeeklyReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordings = ref.watch(recordingsProvider);
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly review')),
      body: recordings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load review.\n$error')),
        data: (rows) {
          final items = <_ReviewTask>[];
          for (final recording in rows) {
            if (recording.startedAt.isBefore(cutoff)) continue;
            final note = decodeNote(recording);
            if (note == null) continue;
            for (final task in note.tasks) {
              if (task.status != TaskStatus.done) {
                items.add(
                    _ReviewTask(recording.id, recording.title, note, task));
              }
            }
          }
          if (items.isEmpty) {
            return const Center(
                child: Text('No unfinished commitments this week.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.assignment_late_outlined),
                title: Text(item.task.title),
                subtitle: Text(
                  '${item.recordingTitle.isEmpty ? 'Untitled recording' : item.recordingTitle}'
                  '${item.task.dueDate == null ? '' : ' · due ${DateFormat.MMMd().format(DateTime.parse(item.task.dueDate!))}'}',
                ),
                onTap: () => openTaskEditor(
                  context,
                  ref,
                  recordingId: item.recordingId,
                  note: item.note,
                  task: item.task,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ReviewTask {
  const _ReviewTask(
      this.recordingId, this.recordingTitle, this.note, this.task);

  final String recordingId;
  final String recordingTitle;
  final NoteDocument note;
  final NoteTask task;
}
