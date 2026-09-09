import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:transcript_core/transcript_core.dart';

import '../recording/folder_watch.dart';
import '../recording/recording_controller.dart';
import '../settings/settings_screen.dart';
import '../widgets/waveform.dart';
import 'library_screen.dart';
import 'note_screen.dart';
import 'weekly_review_screen.dart';

/// Record, then watch it become notes.
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  final List<double> _levels = [];
  StreamSubscription<String>? _sharedFiles;
  FolderWatchService? _watch;
  bool _dropping = false;

  @override
  void initState() {
    super.initState();

    const widgetChannel = MethodChannel('com.echocodex/widget');
    final hasAndroidWidget = defaultTargetPlatform == TargetPlatform.android;
    if (hasAndroidWidget) {
      widgetChannel.setMethodCallHandler((call) async {
        if (call.method == 'widgetAction' &&
            call.arguments == 'com.dmgworkshop.echo_codex_app.WIDGET_RECORD') {
          await ref.read(recordingControllerProvider.notifier).startRecording();
        }
      });
    }

    // Anything the OS killed mid-meeting resumes now, before the user has done
    // anything. They open the app and their notes are already being written.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (hasAndroidWidget) {
        try {
          final initialAction =
              await widgetChannel.invokeMethod<String>('initialAction');
          if (initialAction == 'com.dmgworkshop.echo_codex_app.WIDGET_RECORD') {
            await ref
                .read(recordingControllerProvider.notifier)
                .startRecording();
          }
        } on MissingPluginException {
          // A desktop target has no Android home-screen widget bridge.
        }
      }
      final controller = ref.read(recordingControllerProvider.notifier);
      await controller.resumeUnfinished();

      // A file shared into the app while it was closed: the platform held it until Dart
      // existed to be told. Handled after the resume so a recording interrupted
      // mid-meeting still takes priority over a file that can wait.
      final shared = await ref.read(sharedFilesProvider).take();
      if (shared != null) await controller.importRecording(shared);
    });

    // And files shared while the app is already open.
    _sharedFiles = ref.read(sharedFilesProvider).files.listen((path) {
      ref.read(recordingControllerProvider.notifier).importRecording(path);
    });

    ref.read(recorderProvider).levels.listen((level) {
      if (!mounted) return;
      setState(() {
        _levels.add(level);
        // An hour at 10 Hz is 36,000 samples; only the visible tail is ever drawn.
        if (_levels.length > 2000) _levels.removeRange(0, 500);
      });
    });

    if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      _watch = FolderWatchService(
        onFile: (path) =>
            ref.read(recordingControllerProvider.notifier).importRecording(path),
      );
      unawaited(_watch!.start(ref.read(settingsStoreProvider).watchFolderPath));
    }
  }

  @override
  void dispose() {
    unawaited(_sharedFiles?.cancel());
    unawaited(_watch?.stop());
    super.dispose();
  }

  /// Settings has no change stream, so whether the note-writing stage is configured is
  /// only known to be stale after a trip there — refreshed on return rather than left
  /// showing what was true before the visit.
  Future<void> _openSettings(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    ref.invalidate(structuringReadyProvider);
  }

  Future<bool> _confirmCloudRecording(BuildContext context) async {
    final settings = ref.read(settingsStoreProvider);
    if (settings.posture.posture != DataPosture.cloud) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Before this recording starts'),
            content: Text(
              '${settings.posture.summary}.\n\n${settings.posture.detail}\n\n'
              'Continue with this provider configuration?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _preRecordingChecklist(BuildContext context) async {
    final settings = ref.read(settingsStoreProvider);
    if (!settings.preRecordingChecklist) return true;
    final hasPermission = await ref.read(recorderProvider).hasPermission();
    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ready to record?'),
        content: Text(
          'Microphone: ${hasPermission ? 'available' : 'permission needed'}\n'
          'Storage: ${settings.recordingsDirPath ?? 'device storage'}\n'
          'Privacy: ${settings.posture.summary}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, hasPermission),
            child: const Text('Start recording'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingControllerProvider);

    ref.listen<RecordState>(recordingControllerProvider, (previous, next) {
      if (next is RecordDone) {
        setState(_levels.clear);
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => NoteScreen(recordingId: next.recordingId),
        ));
        if (next.warning != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(next.warning!)),
          );
        }
      }
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          final controller = ref.read(recordingControllerProvider.notifier);
          if (state is RecordActive) {
            controller.stopAndProcess();
          } else if (state is RecordIdle || state is RecordDone) {
            controller.startRecording();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const LibraryScreen()),
          );
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          _openSettings(context, ref);
        },
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dropping = true),
          onDragExited: (_) => setState(() => _dropping = false),
          onDragDone: (details) async {
            setState(() => _dropping = false);
            final controller = ref.read(recordingControllerProvider.notifier);
            for (final file in details.files) {
              await controller.importRecording(file.path);
            }
          },
          child: Scaffold(
          appBar: AppBar(
            title: const Text('Echo Codex'),
            actions: [
              IconButton(
                icon: const Icon(Icons.library_books_outlined),
                tooltip: 'Recordings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const LibraryScreen()),
                ),
              ),
              // Settings was previously reachable only through the library, which put the
              // provider choice two screens away from the button that starts sending audio
              // to it.
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'AI providers',
                onPressed: () => _openSettings(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.fact_check_outlined),
                tooltip: 'Weekly review',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const WeeklyReviewScreen()),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state is RecordIdle ||
                      state is RecordDone ||
                      state is RecordError)
                    _ConfigureAiBanner(
                        onTap: () => _openSettings(context, ref)),
                  if (_dropping)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Drop audio or video to import',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  Expanded(child: RecordBody(state: state, levels: _levels)),
                ],
              ),
            ),
          ),
          floatingActionButton: switch (state) {
            // Stopping goes to whichever capture is actually running: the two are torn down
            // by different paths, and the microphone one would leave the projection open.
            RecordActive(source: RecordSource.deviceAudio) => Semantics(
                button: true,
                label: 'Stop and write notes',
                child: FloatingActionButton.large(
                  onPressed: () => ref
                      .read(recordingControllerProvider.notifier)
                      .stopDeviceCapture(),
                  tooltip: 'Stop and write notes',
                  child: const Icon(Icons.stop),
                ),
              ),
            RecordActive() => Semantics(
                button: true,
                label: 'Stop and write notes',
                child: FloatingActionButton.large(
                  onPressed: () => ref
                      .read(recordingControllerProvider.notifier)
                      .stopAndProcess(),
                  tooltip: 'Stop and write notes',
                  child: const Icon(Icons.stop),
                ),
              ),
            RecordProcessing() => null,
            _ => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const DeviceAudioButton(),
                  FloatingActionButton.large(
                    onPressed: () async {
                      if (!await _preRecordingChecklist(context)) return;
                      if (!context.mounted) return;
                      if (!await _confirmCloudRecording(context)) return;
                      if (!context.mounted) return;
                      await ref
                          .read(recordingControllerProvider.notifier)
                          .startRecording();
                    },
                    tooltip: 'Start recording',
                    child: const Icon(Icons.mic),
                  ),
                ],
              ),
          },
        ),
        ),
      ),
    );
  }
}

/// Starts a recording of what the device is playing, when the platform allows it.
///
/// Hidden rather than disabled where it cannot work — iOS has no such API, and Android
/// below 10 lacks playback capture — because a permanently dead control is worse than an
/// absent one. It is a secondary action: the microphone is what most recordings are.
class DeviceAudioButton extends ConsumerWidget {
  const DeviceAudioButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled =
        ref.watch(settingsStoreProvider).workflowEnabled('deviceAudioCapture');
    if (!enabled) return const SizedBox.shrink();

    final supported = ref.watch(deviceAudioSupportedProvider).valueOrNull;
    if (supported != true) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FloatingActionButton.small(
        heroTag: 'device-audio',
        onPressed: () async {
          final settings = ref.read(settingsStoreProvider);
          if (settings.posture.posture == DataPosture.cloud) {
            final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Before capture starts'),
                    content: Text(
                        '${settings.posture.summary}.\n\n${settings.posture.detail}'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Continue')),
                    ],
                  ),
                ) ??
                false;
            if (!confirmed || !context.mounted) return;
          }
          await ref
              .read(recordingControllerProvider.notifier)
              .startDeviceCapture();
        },
        tooltip: 'Record what this device is playing',
        child: const Icon(Icons.speaker),
      ),
    );
  }
}

/// Recording always works — on-device transcription needs nothing — but notes and tasks
/// do not get written until a service is chosen and actually configured. Shown whenever
/// that is not yet true, rather than only on first launch, so a key cleared later in
/// Settings gets the same nudge as never having set one up.
class _ConfigureAiBanner extends ConsumerWidget {
  const _ConfigureAiBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(structuringReadyProvider);
    final isReady = ready.valueOrNull;
    if (isReady == null || isReady) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.key_outlined,
                    color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Set up notes and tasks',
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer)),
                      const SizedBox(height: 2),
                      Text(
                        'Recording works right now. Choose an AI service to also get '
                        'a summary and action items.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.onTertiaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps recording state to what is on screen.
///
/// Separated from [RecordScreen] so the five states can be exercised directly, without a
/// microphone, a provider, or a database behind them.
class RecordBody extends StatelessWidget {
  const RecordBody({super.key, required this.state, this.levels = const []});

  final RecordState state;
  final List<double> levels;

  @override
  Widget build(BuildContext context) => switch (state) {
        RecordIdle() => const _IdlePane(),
        final RecordActive s => _ActivePane(state: s, levels: levels),
        final RecordProcessing s => _ProcessingPane(state: s),
        // Navigation to the note happens in a listener; the pane behind it returns to
        // rest so a second recording can start immediately.
        RecordDone() => const _IdlePane(),
        final RecordError s => _ErrorPane(state: s),
      };
}

class _IdlePane extends StatelessWidget {
  const _IdlePane();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.graphic_eq,
            size: 56, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
        const SizedBox(height: 20),
        Text('Ready to record', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          'Everything goes straight from this device to the AI you chose. '
          'Nothing passes through anyone else.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ActivePane extends StatelessWidget {
  const _ActivePane({required this.state, required this.levels});

  final RecordActive state;
  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // One semantics node for the dot and the clock together. Read separately a
        // screen reader gives "red circle" then "zero five colon three two", which is
        // both meaningless and the only place the recording/paused distinction is
        // carried — the dot's colour is otherwise the sole indicator.
        Semantics(
          liveRegion: true,
          label: state.interrupted
              ? 'Paused, ${spokenDuration(state.elapsed)} recorded'
              : 'Recording, ${spokenDuration(state.elapsed)}',
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  // Amber while interrupted: the recording is open but nothing is being
                  // captured, and a red dot would say otherwise.
                  color: state.interrupted
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatDuration(state.elapsed),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (state.interrupted) ...[
          const SizedBox(height: 16),
          _InterruptionBanner(reason: state.interruptionReason),
        ],
        const SizedBox(height: 28),
        // Decorative. The level trace says nothing the timer and status do not, and a
        // screen reader stopping on it would only add noise between them.
        ExcludeSemantics(
          child: SizedBox(height: 120, child: Waveform(levels: levels)),
        ),
        const SizedBox(height: 28),
        if (state.liveText.isNotEmpty)
          Expanded(
            child: SingleChildScrollView(
              reverse: true,
              child: Semantics(
                liveRegion: true,
                label: 'Live transcript',
                child: Text(
                  state.liveText,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: Center(
              child: Text(
                'Listening',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }
}

/// Says plainly that the microphone has been taken, and that the recording is still
/// open. Silence with a running timer and no explanation is how a user concludes the app
/// is broken and force-quits mid-meeting.
class _InterruptionBanner extends StatelessWidget {
  const _InterruptionBanner({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.pause_circle_outline,
              size: 18, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Paused — ${reason ?? 'another app is using the microphone'}. '
              'Recording continues automatically.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessingPane extends StatelessWidget {
  const _ProcessingPane({required this.state});

  final RecordProcessing state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = state.fraction == null
        ? null
        : '${(state.fraction! * 100).round()} percent';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 220,
          // A real fraction where one exists. On a long recording this runs for minutes,
          // and an indeterminate spinner is what makes people force-quit.
          child: LinearProgressIndicator(value: state.fraction),
        ),
        const SizedBox(height: 20),
        // The bar and its caption are one status, announced together and re-announced
        // as it advances — a blind user otherwise has no way to tell a long job from a
        // stuck one.
        Semantics(
          liveRegion: true,
          label: percent == null ? state.label : '${state.label}, $percent',
          excludeSemantics: true,
          child: Text(state.label, style: theme.textTheme.titleMedium),
        ),
      ],
    );
  }
}

class _ErrorPane extends ConsumerWidget {
  const _ErrorPane({required this.state});

  final RecordError state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 44, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(state.message,
            textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        if (state.remedy != null) ...[
          const SizedBox(height: 10),
          Text(
            state.remedy!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (state.recordingId != null) ...[
          const SizedBox(height: 20),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NoteScreen(recordingId: state.recordingId!),
              ),
            ),
            child: const Text('Open the transcript'),
          ),
        ],
      ],
    );
  }
}

/// mm:ss, or h:mm:ss once the recording is long enough to need it.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// The same duration as words, for a screen reader.
///
/// `05:32` is announced as "five thirty-two" or "zero five colon three two" depending
/// on the reader and the language — neither of which is a length of time. Spelling out
/// the units is the only way the running total is actually usable without sight.
String spokenDuration(Duration d) {
  final parts = <String>[];
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);

  if (h > 0) parts.add('$h hour${h == 1 ? '' : 's'}');
  if (m > 0) parts.add('$m minute${m == 1 ? '' : 's'}');
  // Seconds are dropped once there is an hour on the clock: at that length they are
  // noise, and they would be stale by the time the sentence finished being read.
  if (h == 0 && (s > 0 || parts.isEmpty)) {
    parts.add('$s second${s == 1 ? '' : 's'}');
  }

  return parts.join(' ');
}
