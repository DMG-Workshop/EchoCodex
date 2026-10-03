import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart' as db;
import '../data/repository.dart';
import '../recording/recording_controller.dart';

/// Tagging and filing one recording.
///
/// Both in one sheet because they are one decision — "where does this go and what is it
/// about" — made once, usually right after reading the notes. Splitting them across two
/// screens would mean nobody does the second one.
Future<void> openTagSheet(
  BuildContext context,
  WidgetRef ref,
  db.Recording recording,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TagSheet(recording: recording),
    );

class _TagSheet extends ConsumerStatefulWidget {
  const _TagSheet({required this.recording});

  final db.Recording recording;

  @override
  ConsumerState<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends ConsumerState<_TagSheet> {
  final _tagController = TextEditingController();

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine =
        ref.watch(recordingTagsProvider(widget.recording.id)).valueOrNull ??
            const <db.TagRow>[];
    final all = ref.watch(tagsProvider).valueOrNull ?? const <TagWithCount>[];
    final folders = ref.watch(foldersProvider).valueOrNull ?? const <String>[];
    final onIt = {for (final tag in mine) tag.id};

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tags', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Any number at once — a standup is both "work" and "weekly".',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (mine.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in mine)
                    InputChip(
                      label: Text(tag.name),
                      // Named, so a screen reader says which tag is being removed
                      // rather than "delete" four times in a row.
                      deleteButtonTooltipMessage: 'Remove ${tag.name}',
                      onDeleted: () => ref
                          .read(repositoryProvider)
                          .untagRecording(widget.recording.id, tag.id),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Add a tag',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add',
                  onPressed: _addTyped,
                ),
              ),
              onSubmitted: (_) => _addTyped(),
            ),
            // Tags already in use, offered rather than retyped. Retyping is how "work"
            // and "Work" would have become two tags, were the normalized name not
            // holding them together underneath.
            if (all.any((t) => !onIt.contains(t.tag.id))) ...[
              const SizedBox(height: 12),
              Text('Already in use',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in all)
                    if (!onIt.contains(entry.tag.id))
                      ActionChip(
                        label: Text(entry.tag.name),
                        onPressed: () => ref
                            .read(repositoryProvider)
                            .tagRecording(widget.recording.id, entry.tag.name),
                      ),
                ],
              ),
            ],
            const Divider(height: 32),
            Text('Folder', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'One at a time. Use a slash to nest, like "Work/Standups".',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _FolderField(
              recording: widget.recording,
              folders: folders,
            ),
          ],
        ),
      ),
    );
  }

  void _addTyped() {
    final typed = _tagController.text.trim();
    if (typed.isEmpty) return;
    _tagController.clear();
    ref.read(repositoryProvider).tagRecording(widget.recording.id, typed);
  }
}

/// The folder a recording sits in, typed or picked.
///
/// Typed as well as picked because the first folder has to come from somewhere, and a
/// picker over an empty list is a dead end.
class _FolderField extends ConsumerStatefulWidget {
  const _FolderField({required this.recording, required this.folders});

  final db.Recording recording;
  final List<String> folders;

  @override
  ConsumerState<_FolderField> createState() => _FolderFieldState();
}

class _FolderFieldState extends ConsumerState<_FolderField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.recording.folder ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(String? value) {
    _controller.text = value ?? '';
    ref.read(repositoryProvider).setFolder(widget.recording.id, value);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Unfiled',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Unfile',
                      onPressed: () => setState(() => _save(null)),
                    ),
            ),
            onSubmitted: (value) => setState(() =>
                _save(value.trim().isEmpty ? null : value.trim())),
          ),
          if (widget.folders.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final folder in widget.folders)
                  ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(folder),
                    onPressed: () => setState(() => _save(folder)),
                  ),
              ],
            ),
          ],
        ],
      );
}
