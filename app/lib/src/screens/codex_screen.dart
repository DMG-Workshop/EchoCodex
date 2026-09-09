import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart' as db;
import '../recording/recording_controller.dart';

/// The Codex: a personal library of notes the user has kept on purpose.
///
/// Separate from the recordings library on the home screen — a Codex note is not a
/// view onto a recording, it is its own row that outlives whatever transcript it may
/// have started from. See [db.CodexNotes] for the persistence guarantee.
class CodexScreen extends ConsumerStatefulWidget {
  const CodexScreen({super.key});

  @override
  ConsumerState<CodexScreen> createState() => _CodexScreenState();
}

class _CodexScreenState extends ConsumerState<CodexScreen> {
  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(codexNotesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Codex')),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not open the Codex.\n$e')),
        data: (items) => items.isEmpty
            ? const _EmptyCodex()
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _CodexNoteTile(note: items[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add a note',
        onPressed: () => _addNote(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addNote(BuildContext context) async {
    final body = await editCodexNoteDialog(context, initial: '');
    if (body == null || body.trim().isEmpty) return;
    await ref.read(repositoryProvider).createCodexNote(body.trim());
  }
}

Future<String?> editCodexNoteDialog(
  BuildContext context, {
  required String initial,
  String title = 'New Codex note',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 6,
        minLines: 3,
        decoration: const InputDecoration(
          hintText: 'A line worth keeping',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _CodexNoteTile extends ConsumerWidget {
  const _CodexNoteTile({required this.note});

  final db.CodexNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(note.id),
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
              title: const Text('Delete this note?'),
              content: const Text(
                  'This only removes it from the Codex. This cannot be undone.'),
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
          ref.read(repositoryProvider).deleteCodexNote(note.id).then((_) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Note deleted')),
            );
          }),
        );
      },
      child: ListTile(
        title: Text(note.body),
        subtitle: Text(
          note.sourceRecordingTitle != null
              ? 'From "${note.sourceRecordingTitle}" · '
                  '${DateFormat.yMMMd().format(note.updatedAt)}'
              : DateFormat.yMMMd().add_jm().format(note.updatedAt),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () async {
          final edited = await editCodexNoteDialog(
            context,
            initial: note.body,
            title: 'Edit note',
          );
          if (edited == null || edited.trim().isEmpty) return;
          if (edited.trim() == note.body) return;
          await ref
              .read(repositoryProvider)
              .updateCodexNote(note.id, edited.trim());
        },
      ),
    );
  }
}

class _EmptyCodex extends StatelessWidget {
  const _EmptyCodex();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_outlined,
                  size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'Nothing in the Codex yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Keep a line by hand with the + button, or save one straight out of '
                'a recording\'s notes.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
}
