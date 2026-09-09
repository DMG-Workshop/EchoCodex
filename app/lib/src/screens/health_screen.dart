import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../recording/recording_controller.dart';
import '../settings/provider_config.dart';

class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen> {
  late Future<_HealthSnapshot> _health = _load();

  Future<_HealthSnapshot> _load() async {
    final settings = ref.read(settingsStoreProvider);
    final dir = await getApplicationDocumentsDirectory();
    var bytes = 0;
    if (dir.existsSync()) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) bytes += entity.lengthSync();
      }
    }
    final providers = <_ProviderHealth>[];
    final factory = ref.read(providerFactoryProvider);
    for (final stage in ProviderStage.values) {
      final kind = settings.kindFor(stage);
      if (kind == null) {
        providers.add(_ProviderHealth(stage.label, 'Not configured', false));
        continue;
      }
      final selection = ProviderSelection(
        kind: kind,
        hasKey: true,
        model: settings.modelFor(kind),
        endpoint: settings.endpointFor(kind),
      );
      try {
        final provider = await factory.testable(selection, stage);
        final result = await provider?.test();
        providers.add(_ProviderHealth(
          stage.label,
          result?.summary ?? 'Not available',
          result?.ok ?? false,
        ));
      } catch (_) {
        providers
            .add(_ProviderHealth(stage.label, 'Health check failed', false));
      }
    }
    return _HealthSnapshot(bytes, providers);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Storage and provider health')),
        body: FutureBuilder<_HealthSnapshot>(
          future: _health,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('Local storage in use'),
                  subtitle: Text(_formatBytes(data.bytes)),
                ),
                const Divider(),
                Text('Providers',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final provider in data.providers)
                  ListTile(
                    leading: Icon(
                      provider.ok
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: provider.ok
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    title: Text(provider.stage),
                    subtitle: Text(provider.message),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _health = _load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Run checks again'),
                ),
              ],
            );
          },
        ),
      );

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _HealthSnapshot {
  const _HealthSnapshot(this.bytes, this.providers);
  final int bytes;
  final List<_ProviderHealth> providers;
}

class _ProviderHealth {
  const _ProviderHealth(this.stage, this.message, this.ok);
  final String stage;
  final String message;
  final bool ok;
}
