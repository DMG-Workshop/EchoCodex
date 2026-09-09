import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

class AudioDiagnosticsScreen extends StatefulWidget {
  const AudioDiagnosticsScreen({super.key});

  @override
  State<AudioDiagnosticsScreen> createState() => _AudioDiagnosticsScreenState();
}

class _AudioDiagnosticsScreenState extends State<AudioDiagnosticsScreen> {
  late Future<AudioDiagnostics> _diagnostics = AudioDiagnostics.load();

  void _refresh() => setState(() {
        _diagnostics = AudioDiagnostics.load();
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Linux audio diagnostics')),
        body: FutureBuilder<AudioDiagnostics>(
          future: _diagnostics,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _StatusTile(
                  title: 'PipeWire',
                  value: data.pipeWire,
                  ok: data.pipeWireOk,
                ),
                _StatusTile(
                  title: 'PulseAudio compatibility',
                  value: data.pulseAudio,
                  ok: data.pulseAudioOk,
                ),
                _StatusTile(
                  title: 'Default input',
                  value: data.defaultSource,
                  ok: data.defaultSource != 'Unavailable',
                ),
                const SizedBox(height: 12),
                Text('Input devices',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (data.inputs.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.mic_off_outlined),
                    title: Text('No input devices detected'),
                    subtitle:
                        Text('Connect a microphone and refresh diagnostics.'),
                  )
                else
                  for (final input in data.inputs)
                    ListTile(
                      leading: const Icon(Icons.mic_none),
                      title: Text(input),
                    ),
                const SizedBox(height: 12),
                const Text(
                  'Echo Codex uses the system default input on Linux. Choose a device '
                  'in your desktop sound settings or with PipeWire tools, then refresh '
                  'this screen before recording.',
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh diagnostics'),
                ),
              ],
            );
          },
        ),
      );
}

class _StatusTile extends StatelessWidget {
  const _StatusTile(
      {required this.title, required this.value, required this.ok});
  final String title;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: ok
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
        title: Text(title),
        subtitle: Text(value),
      );
}

class AudioDiagnostics {
  const AudioDiagnostics({
    required this.pipeWire,
    required this.pipeWireOk,
    required this.pulseAudio,
    required this.pulseAudioOk,
    required this.defaultSource,
    required this.inputs,
  });

  final String pipeWire;
  final bool pipeWireOk;
  final String pulseAudio;
  final bool pulseAudioOk;
  final String defaultSource;
  final List<String> inputs;

  static Future<AudioDiagnostics> load() async {
    if (!Platform.isLinux) {
      return const AudioDiagnostics(
        pipeWire: 'Linux only',
        pipeWireOk: false,
        pulseAudio: 'Linux only',
        pulseAudioOk: false,
        defaultSource: 'Unavailable',
        inputs: [],
      );
    }
    final pipe = await _run('wpctl', ['status']);
    final pulse = await _run('pactl', ['info']);
    final sources = await _run('pactl', ['list', 'short', 'sources']);
    final defaultLine = pulse.output
        .split('\n')
        .where((line) => line.startsWith('Default Source:'))
        .firstOrNull;
    final inputs = sources.output
        .split('\n')
        .where((line) => line.trim().isNotEmpty && !line.contains('.monitor'))
        .map((line) => line.split('\t').skip(1).take(1).firstOrNull ?? line)
        .toList();
    return AudioDiagnostics(
      pipeWire: pipe.ok ? 'Running' : _failure(pipe),
      pipeWireOk: pipe.ok,
      pulseAudio: pulse.ok ? 'Connected' : _failure(pulse),
      pulseAudioOk: pulse.ok,
      defaultSource:
          defaultLine?.split(':').skip(1).join(':').trim() ?? 'Unavailable',
      inputs: inputs,
    );
  }

  static String _failure(_CommandResult result) =>
      result.error?.trim().isNotEmpty == true
          ? result.error!.trim()
          : 'Unavailable';

  static Future<_CommandResult> _run(String command, List<String> args) async {
    try {
      final result =
          await Process.run(command, args).timeout(const Duration(seconds: 3));
      return _CommandResult(
        result.exitCode == 0,
        result.stdout.toString(),
        result.stderr.toString(),
      );
    } catch (error) {
      return _CommandResult(false, '', '$error');
    }
  }
}

class _CommandResult {
  const _CommandResult(this.ok, this.output, this.error);
  final bool ok;
  final String output;
  final String? error;
}
