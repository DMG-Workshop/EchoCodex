import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/recording_controller.dart';
import '../screens/benchmark_screen.dart';
import 'provider_config.dart';

class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStoreProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility and updates')),
      body: ListView(
        children: [
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.contrast),
            title: const Text('High contrast'),
            subtitle:
                const Text('Increase contrast for controls and surfaces.'),
            value: settings.highContrast,
            onChanged: (value) async {
              await settings.setHighContrast(value);
              ref.read(settingsRevisionProvider.notifier).state++;
            },
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Text size'),
            subtitle: Text('${(settings.textScale * 100).round()}%'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Slider(
              min: 0.85,
              max: 1.6,
              divisions: 15,
              label: '${(settings.textScale * 100).round()}%',
              value: settings.textScale.clamp(0.85, 1.6),
              onChanged: (value) async {
                await settings.setTextScale(value);
                ref.read(settingsRevisionProvider.notifier).state++;
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Release channel'),
            subtitle: Text(settings.releaseChannel.label),
            trailing: DropdownButton<ReleaseChannel>(
              value: settings.releaseChannel,
              underline: const SizedBox.shrink(),
              onChanged: (value) async {
                if (value == null) return;
                await settings.setReleaseChannel(value);
                ref.read(settingsRevisionProvider.notifier).state++;
              },
              items: [
                for (final channel in ReleaseChannel.values)
                  DropdownMenuItem(value: channel, child: Text(channel.label)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Benchmarks'),
            subtitle: const Text(
                'Inspect local model size and processing readiness.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BenchmarkScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
