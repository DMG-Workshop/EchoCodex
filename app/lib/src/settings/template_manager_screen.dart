import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/recording_controller.dart';

class TemplateManagerScreen extends ConsumerWidget {
  const TemplateManagerScreen({super.key});

  Future<void> _addTemplate(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final instructions = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New note template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: instructions,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Instructions for the AI',
                hintText: 'For example: emphasize risks and decisions.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, name.text.trim().isNotEmpty),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;
    await ref.read(repositoryProvider).saveTemplate(
          id: 'template_${DateTime.now().microsecondsSinceEpoch}',
          name: name.text.trim(),
          instructions: instructions.text.trim(),
        );
    if (context.mounted) (context as Element).markNeedsBuild();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add template',
            onPressed: () => _addTemplate(context, ref),
          ),
        ],
      ),
      body: FutureBuilder(
        future: repository.templates(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final templates = snapshot.data!;
          if (templates.isEmpty) {
            return const Center(child: Text('No custom templates yet.'));
          }
          return ListView.separated(
            itemCount: templates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final template = templates[index];
              final active =
                  ref.watch(settingsStoreProvider).activeTemplateId ==
                      template.id;
              return ListTile(
                title: Text(template.name),
                subtitle: Text(template.instructions),
                isThreeLine: true,
                leading: Icon(
                    active ? Icons.check_circle : Icons.description_outlined),
                onTap: () async {
                  await ref.read(settingsStoreProvider).setActiveTemplateId(
                        active ? null : template.id,
                      );
                  if (context.mounted) (context as Element).markNeedsBuild();
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete template',
                  onPressed: () async {
                    await repository.deleteTemplate(template.id);
                    if (context.mounted) (context as Element).markNeedsBuild();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
