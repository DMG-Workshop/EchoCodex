import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'on_device_gemma_engine.dart';

/// What picking and installing a model file resolved to, or null if the sheet was
/// dismissed without changing anything.
class GemmaModelPick {
  const GemmaModelPick({required this.path, required this.family});
  final String path;
  final GemmaFamily family;
}

/// Opens a sheet for picking a `.litertlm` model file already on disk, choosing its
/// chat-template family, and installing it as the active on-device model.
///
/// Returns the pick once installed, or null if the sheet was dismissed.
Future<GemmaModelPick?> showGemmaModelPicker(
  BuildContext context, {
  required OnDeviceGemmaEngine engine,
}) {
  return showModalBottomSheet<GemmaModelPick>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _GemmaModelSheet(engine: engine),
  );
}

class _GemmaModelSheet extends StatefulWidget {
  const _GemmaModelSheet({required this.engine});
  final OnDeviceGemmaEngine engine;

  @override
  State<_GemmaModelSheet> createState() => _GemmaModelSheetState();
}

class _GemmaModelSheetState extends State<_GemmaModelSheet> {
  String? _path;
  GemmaFamily _family = GemmaFamily.gemma4;
  bool _installing = false;
  bool _picking = false;
  String? _error;

  Future<void> _pickFile() async {
    // The platform allows one picker at a time and answers a second call by
    // throwing `already_active` — which a second tap before the sheet appears is
    // enough to trigger, and which nothing here used to catch.
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['litertlm'],
        withData: false,
      );
      final path = picked?.files.singleOrNull?.path;
      if (path == null || !mounted) return;
      setState(() {
        _path = path;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _install() async {
    final path = _path;
    if (path == null) return;
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      await widget.engine.install(path: path, family: _family);
      if (!mounted) return;
      Navigator.of(context)
          .pop(GemmaModelPick(path: path, family: _family));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = _path?.split('/').last;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('On-device Gemma model', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Point the app at a .litertlm file you already downloaded — nothing '
              'is uploaded anywhere, and no key is needed. Get one from Hugging '
              'Face (litert-community) or Kaggle.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _installing || _picking ? null : _pickFile,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: Text(fileName ?? 'Choose a .litertlm file'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<GemmaFamily>(
              initialValue: _family,
              decoration: const InputDecoration(
                labelText: 'Model family',
                helperText: 'Picks the chat template the file expects.',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final family in GemmaFamily.values)
                  DropdownMenuItem(value: family, child: Text(family.label)),
              ],
              onChanged: _installing
                  ? null
                  : (value) => setState(() => _family = value ?? _family),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _path == null || _installing ? null : _install,
              child: _installing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Use this model'),
            ),
          ],
        ),
      ),
    );
  }
}
