import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:transcript_core/transcript_core.dart';
import 'dart:io';

import '../diagnostics/debug_mode.dart';

/// Debug Mode: the switch, and what it has recorded.
///
/// The log is shown in full rather than summarised, because the point of keeping it on
/// the device is that the user can read exactly what they would be sending before they
/// decide to send it. Nothing here uploads anything.
class DebugLogScreen extends ConsumerStatefulWidget {
  const DebugLogScreen({super.key});

  @override
  ConsumerState<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends ConsumerState<DebugLogScreen> {
  late Future<List<DebugEntry>> _entries = _load();
  DebugLevel? _filter;
  bool _busy = false;

  Future<List<DebugEntry>> _load() => ref.read(debugLogProvider).read();

  void _reload() => setState(() => _entries = _load());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = ref.watch(debugModeSwitchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug mode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            value: on,
            title: const Text('Record a diagnostic log'),
            subtitle: const Text(
              'Writes a detailed, step-by-step record of recording and note '
              'writing to this device. Never uploaded, and anything that looks '
              'like a key is removed. Kept for 48 hours, then deleted.',
            ),
            onChanged: _busy
                ? null
                : (value) async {
                    setState(() => _busy = true);
                    await ref.read(debugModeSwitchProvider.notifier).set(value);
                    if (!mounted) return;
                    setState(() => _busy = false);
                    _reload();
                  },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final level in [null, ...DebugLevel.values])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(level?.name ?? 'all'),
                              selected: _filter == level,
                              onSelected: (_) =>
                                  setState(() => _filter = level),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<DebugEntry>>(
              future: _entries,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('Could not read the log.\n${snapshot.error}',
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                final all = snapshot.data ?? const <DebugEntry>[];
                final shown = _filter == null
                    ? all
                    : all.where((e) => e.level == _filter).toList();
                if (shown.isEmpty) return _Empty(recording: on);

                // Newest first: when something has just gone wrong, the last line is
                // the one being looked for.
                return ListView.separated(
                  reverse: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _EntryTile(entry: shown[shown.length - 1 - i]),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _clear,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('Export'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }

  Future<void> _clear() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    await ref.read(debugLogProvider).clear();
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    messenger.showSnackBar(const SnackBar(content: Text('Log cleared')));
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // Flush first: the last few seconds are usually the interesting ones, and they
      // are still in memory until something asks for them.
      await ref.read(debugLogProvider).flush();
      final info = await PackageInfo.fromPlatform();
      final file = await ref.read(debugModeProvider).sink.export(
            header: 'Echo Codex ${info.version}+${info.buildNumber} · '
                '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          );
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Echo Codex debug log'),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export the log. $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final DebugEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = switch (entry.level) {
      DebugLevel.info => theme.colorScheme.onSurfaceVariant,
      DebugLevel.warning => theme.colorScheme.tertiary,
      DebugLevel.error => theme.colorScheme.error,
    };

    return ListTile(
      dense: true,
      leading: Icon(
        switch (entry.level) {
          DebugLevel.info => Icons.chevron_right,
          DebugLevel.warning => Icons.warning_amber_outlined,
          DebugLevel.error => Icons.error_outline,
        },
        size: 18,
        color: colour,
      ),
      title: Text(entry.message, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        [
          entry.at.toLocal().toIso8601String().substring(11, 19),
          entry.tag,
          for (final field in entry.fields.entries)
            if (field.key != 'stack') '${field.key}=${field.value}',
        ].join('  ·  '),
        style: theme.textTheme.labelSmall?.copyWith(color: colour),
      ),
      isThreeLine: entry.fields.isNotEmpty,
      onTap: () => _showDetail(context, entry),
    );
  }

  void _showDetail(BuildContext context, DebugEntry entry) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.tag),
        content: SingleChildScrollView(
          child: SelectableText(entry.format()),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              await Clipboard.setData(ClipboardData(text: entry.format()));
              navigator.pop();
              messenger
                  .showSnackBar(const SnackBar(content: Text('Line copied')));
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.recording});

  final bool recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(recording ? Icons.hourglass_empty : Icons.toggle_off_outlined,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(recording ? 'Nothing recorded yet' : 'Debug mode is off',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              recording
                  ? 'Reproduce the problem — make a recording, or write notes from '
                      'one — and the steps will appear here.'
                  : 'Switch it on, then reproduce the problem. The app behaves '
                      'exactly the same either way.',
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
