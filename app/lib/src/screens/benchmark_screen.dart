import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../whisper/file_model_store.dart';

class BenchmarkScreen extends ConsumerStatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  ConsumerState<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends ConsumerState<BenchmarkScreen> {
  late Future<_Benchmark> _benchmark = _run();

  Future<_Benchmark> _run() async {
    final directory = await getApplicationSupportDirectory();
    final store = FileModelStore();
    final models = <String, int>{};
    for (final model in const ['tiny', 'base', 'small', 'medium', 'large-v3']) {
      final bytes = await store.bytesOnDisk(model);
      if (bytes > 0 || await store.isComplete(model)) models[model] = bytes;
    }
    return _Benchmark(directory.path, models);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Benchmarks')),
        body: FutureBuilder<_Benchmark>(
          future: _benchmark,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'These measurements stay on this device. Battery and transcription speed are measured during real use rather than simulated.',
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Support directory'),
                  subtitle: Text(data.directory),
                ),
                const Divider(),
                Text('Offline models',
                    style: Theme.of(context).textTheme.titleMedium),
                if (data.models.isEmpty)
                  const ListTile(title: Text('No downloaded models yet.')),
                for (final entry in data.models.entries)
                  ListTile(
                    leading: const Icon(Icons.memory_outlined),
                    title: Text(entry.key),
                    subtitle: Text(_formatBytes(entry.value)),
                  ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _benchmark = _run()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh measurements'),
                ),
              ],
            );
          },
        ),
      );

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Benchmark {
  const _Benchmark(this.directory, this.models);
  final String directory;
  final Map<String, int> models;
}
