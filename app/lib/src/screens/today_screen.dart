import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:transcript_core/transcript_core.dart';

import '../data/database.dart' as db;
import '../data/repository.dart';
import '../recording/recording_controller.dart';
import 'task_editor.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordings = ref.watch(recordingsProvider);
    final today = DateUtils.dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: recordings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load commitments.\n$error')),
        data: (rows) {
          final items = <_TodayTask>[];
          for (final recording in rows) {
            final note = decodeNote(recording);
            if (note == null) continue;
            for (final task in note.tasks) {
              final due = DateTime.tryParse(task.dueDate ?? '');
              if (task.status == TaskStatus.done || due == null) continue;
              if (!due.isAfter(today)) {
                items.add(_TodayTask(recording, note, task, due));
              }
            }
          }
          items.sort((a, b) => a.due.compareTo(b.due));
          if (items.isEmpty) {
            return const Center(
              child: Text('No open commitments due today or overdue.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final overdue = item.due.isBefore(today);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  overdue ? Icons.warning_amber : Icons.today,
                  color: overdue
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(item.task.title),
                subtitle: Text(
                  '${overdue ? 'Overdue' : 'Due today'} · '
                  '${item.recording.title.isEmpty ? 'Untitled recording' : item.recording.title}'
                  '${item.task.dateBasis == DateBasis.inferred ? ' · inferred' : ''}',
                ),
                trailing: Text(DateFormat.MMMd().format(item.due)),
                onTap: () => openTaskEditor(
                  context,
                  ref,
                  recordingId: item.recording.id,
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

class _TodayTask {
  const _TodayTask(this.recording, this.note, this.task, this.due);

  final db.Recording recording;
  final NoteDocument note;
  final NoteTask task;
  final DateTime due;
}
