import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recording/recording_controller.dart';
import 'provider_config.dart';

/// User controls for the recording, transcription, import, and study workflow.
class WorkflowSettingsScreen extends ConsumerStatefulWidget {
  const WorkflowSettingsScreen({super.key});

  @override
  ConsumerState<WorkflowSettingsScreen> createState() =>
      _WorkflowSettingsScreenState();
}

class _WorkflowSettingsScreenState
    extends ConsumerState<WorkflowSettingsScreen> {
  final _languageController = TextEditingController();
  final _vocabularyController = TextEditingController();
  final _webhookController = TextEditingController();
  final _notionController = TextEditingController();

  @override
  void dispose() {
    _webhookController.dispose();
    _notionController.dispose();
    _languageController.dispose();
    _vocabularyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(settingsStoreProvider);
    _languageController.value = _languageController.value.copyWith(
      text: store.transcriptionLanguage,
      selection:
          TextSelection.collapsed(offset: store.transcriptionLanguage.length),
    );
    _vocabularyController.value = _vocabularyController.value.copyWith(
      text: store.customVocabulary,
      selection: TextSelection.collapsed(offset: store.customVocabulary.length),
    );
    _webhookController.value = _webhookController.value.copyWith(
      text: store.webhookUrl,
      selection: TextSelection.collapsed(offset: store.webhookUrl.length),
    );
    _notionController.value = _notionController.value.copyWith(
      text: store.notionDatabaseId,
      selection: TextSelection.collapsed(offset: store.notionDatabaseId.length),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Workflow features')),
      body: ListView(
        children: [
          const _SectionHeader('Capture and transcription'),
          _toggle(
              store,
              'speakerLabels',
              'Speaker labels',
              'Best-effort "Speaker 1" style labels. Only takes effect when Gemini '
                  '(audio) is your transcription provider — no other service here can '
                  'tell voices apart.'),
          _toggle(
              store,
              'priorityQueue',
              'Priority transcription queue',
              'Recordings marked urgent in the library are transcribed before the '
                  'rest of the backlog on next launch.'),
          _toggle(store, 'punctuationCleanup', 'Punctuation and filler cleanup',
              'Remove filler while preserving the meaning and your words.'),
          _toggle(store, 'multiLanguage', 'Multi-language transcription',
              'Allow a language hint to be sent to speech recognition.'),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.auto_awesome),
            title: const Text('Detect language automatically'),
            subtitle: const Text(
                'Let the transcription provider identify the spoken language.'),
            value: store.autoDetectLanguage,
            onChanged: (value) async {
              await store.setAutoDetectLanguage(value);
              if (mounted) setState(() {});
            },
          ),
          _toggle(store, 'customVocabulary', 'Custom vocabulary',
              'Use names, terms, and product words consistently.'),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _languageController,
                    decoration: const InputDecoration(
                      labelText: 'Language (BCP-47)',
                      hintText: 'en-US, es-ES, fr-FR',
                    ),
                    onSubmitted: store.setTranscriptionLanguage,
                    onEditingComplete: () => store
                        .setTranscriptionLanguage(_languageController.text),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Choose language preset',
                  icon: const Icon(Icons.language),
                  onSelected: (value) async {
                    await store.setTranscriptionLanguage(value);
                    if (mounted) setState(() {});
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'en-US', child: Text('English (US)')),
                    PopupMenuItem(value: 'en-GB', child: Text('English (UK)')),
                    PopupMenuItem(value: 'es-ES', child: Text('Spanish')),
                    PopupMenuItem(value: 'fr-FR', child: Text('French')),
                    PopupMenuItem(value: 'de-DE', child: Text('German')),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Maximum recording duration'),
            subtitle: Text(store.maxRecordingMinutes == 0
                ? 'No limit'
                : '${store.maxRecordingMinutes} minutes'),
            trailing: DropdownButton<int>(
              value: store.maxRecordingMinutes,
              underline: const SizedBox.shrink(),
              onChanged: (value) async {
                if (value == null) return;
                await store.setMaxRecordingMinutes(value);
                if (mounted) setState(() {});
              },
              items: const [
                DropdownMenuItem(value: 0, child: Text('No limit')),
                DropdownMenuItem(value: 30, child: Text('30 min')),
                DropdownMenuItem(value: 60, child: Text('60 min')),
                DropdownMenuItem(value: 120, child: Text('2 hours')),
              ],
            ),
          ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.fact_check_outlined),
            title: const Text('Pre-recording checklist'),
            subtitle: const Text(
                'Review microphone, storage, and privacy before capture.'),
            value: store.preRecordingChecklist,
            onChanged: (value) async {
              await store.setPreRecordingChecklist(value);
              if (mounted) setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Scheduled recording'),
            subtitle: Text(store.scheduledRecording == null
                ? 'Not scheduled'
                : store.scheduledRecording!.toLocal().toString()),
            trailing: IconButton(
              icon: Icon(store.scheduledRecording == null
                  ? Icons.add_alarm
                  : Icons.alarm_off),
              tooltip: store.scheduledRecording == null
                  ? 'Schedule recording'
                  : 'Cancel scheduled recording',
              onPressed: () async {
                if (store.scheduledRecording != null) {
                  await ref
                      .read(reminderServiceProvider)
                      .cancel('scheduled-recording');
                  await store.setScheduledRecording(null);
                } else {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null && context.mounted) {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      final date = DateTime(picked.year, picked.month,
                          picked.day, time.hour, time.minute);
                      await store.setScheduledRecording(date);
                      await ref.read(reminderServiceProvider).scheduleRecording(
                            id: 'scheduled-recording',
                            startsAt: date,
                          );
                    }
                  }
                }
                if (mounted) setState(() {});
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.pause_circle_outline),
            title: const Text('Auto-pause after silence'),
            subtitle: Text(store.autoPauseSilenceSeconds == 0
                ? 'Off'
                : '${store.autoPauseSilenceSeconds} seconds'),
            trailing: DropdownButton<int>(
              value: store.autoPauseSilenceSeconds,
              underline: const SizedBox.shrink(),
              onChanged: (value) async {
                if (value == null) return;
                await store.setAutoPauseSilenceSeconds(value);
                if (mounted) setState(() {});
              },
              items: const [
                DropdownMenuItem(value: 0, child: Text('Off')),
                DropdownMenuItem(value: 5, child: Text('5 sec')),
                DropdownMenuItem(value: 10, child: Text('10 sec')),
                DropdownMenuItem(value: 20, child: Text('20 sec')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 20, 16),
            child: TextField(
              controller: _vocabularyController,
              decoration: const InputDecoration(
                labelText: 'Custom vocabulary',
                hintText: 'Names or terms, separated by commas',
              ),
              onSubmitted: store.setCustomVocabulary,
              onEditingComplete: () =>
                  store.setCustomVocabulary(_vocabularyController.text),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(72, 0, 20, 16),
            child: Text(
              'Add names, places, products, and technical terms separated by commas. '
              'The vocabulary is sent only when the selected transcription provider needs it.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.bluetooth_audio_outlined),
            title: Text('Bluetooth and car microphones'),
            subtitle: Text(
              'Connect the headset or car system before recording. Echo Codex uses the '
              'system-selected input device; Android and iOS audio sessions allow Bluetooth input.',
            ),
          ),
          const _SectionHeader('Meetings and imports'),
          _toggle(
              store,
              'audioImport',
              'Import audio',
              'Bring in WAV, MP3, M4A, FLAC, OGG or AAC files — a meeting exported '
                  'from Zoom or Teams, a lecture, a voice memo.'),
          _toggle(store, 'videoImport', 'Import video',
              'Take the audio track out of MP4, M4V and MOV files.'),
          if (!kIsWeb &&
              (Platform.isLinux || Platform.isMacOS || Platform.isWindows))
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Watch a folder'),
              subtitle: Text(store.watchFolderPath ??
                  'Import new recordings as they appear on disk.'),
              trailing: IconButton(
                icon: Icon(store.watchFolderPath == null
                    ? Icons.create_new_folder_outlined
                    : Icons.close),
                onPressed: () async {
                  if (store.watchFolderPath != null) {
                    await store.setWatchFolderPath(null);
                  } else {
                    final picked =
                        await FilePicker.platform.getDirectoryPath();
                    if (picked != null) {
                      await store.setWatchFolderPath(picked);
                    }
                  }
                  if (mounted) setState(() {});
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              controller: _webhookController,
              decoration: const InputDecoration(
                labelText: 'Webhook URL',
                hintText: 'https://example.com/hooks/echo-codex',
              ),
              onSubmitted: store.setWebhookUrl,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              controller: _notionController,
              decoration: const InputDecoration(
                labelText: 'Notion database ID',
              ),
              onSubmitted: store.setNotionDatabaseId,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Notion integration token',
                hintText: 'Stored only on this device',
              ),
              onSubmitted: (value) =>
                  ref.read(keyStoreProvider).write('notion', value),
            ),
          ),
          _toggle(
              store,
              'deviceAudioCapture',
              'Record device audio (Android)',
              'Record what this device is playing — a recorded webinar or lecture. '
                  'Not calls: Android reserves call audio, so Zoom, Teams and Meet '
                  'come through silent.'),
          const _MeetingCaptureNote(),
          const _SectionHeader('History and feedback'),
          _toggle(store, 'searchableHistory', 'Searchable local history',
              'Keep every dictation locally with raw and cleaned transcript text.'),
          _toggle(store, 'liveProgress', 'Live progress',
              'Show the rolling transcript and true recording-position progress.'),
          const _SectionHeader('Smart study aids'),
          _toggle(store, 'smartSummaries', 'Smart summaries and key concepts',
              'Generate a concise summary and the important concepts.'),
          _toggle(store, 'flashcards', 'Auto-generated flashcards',
              'Generate up to 20 flashcards per recording.'),
          _toggle(store, 'quizzes', 'Auto-generated quizzes',
              'Generate up to 20 quiz questions per recording.'),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _toggle(
      SettingsStore store, String key, String title, String subtitle) {
    return SwitchListTile.adaptive(
      value: store.workflowEnabled(key),
      title: Text(title),
      subtitle: Text(subtitle),
      onChanged: (value) async {
        await store.setWorkflowEnabled(key, value);
        if (mounted) setState(() {});
      },
    );
  }
}

/// Why there is no "record my Zoom call" switch here.
///
/// A toggle that cannot work is worse than none: both platforms forbid an app from
/// capturing another app's call audio, so the honest answer is the microphone or an
/// import, and the user is owed that answer where they went looking for the feature.
class _MeetingCaptureNote extends StatelessWidget {
  const _MeetingCaptureNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recording a Zoom, Teams, Meet or FaceTime call',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'No app can capture another app\'s call audio on iOS or Android — the '
              'platforms block it, and one that claims otherwise is recording your '
              'microphone. Three things do work: record the meeting through the '
              'microphone with it played out loud, import the recording the meeting '
              'tool saved afterwards, or — on Android, for a recorded webinar rather '
              'than a live call — record device audio with the setting above.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge),
      );
}
