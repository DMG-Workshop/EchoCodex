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

  @override
  void dispose() {
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

    return Scaffold(
      appBar: AppBar(title: const Text('Workflow features')),
      body: ListView(
        children: [
          const _SectionHeader('Capture and transcription'),
          _toggle(store, 'speakerLabels', 'Speaker labels',
              'Best-effort "Speaker 1" style labels. Only takes effect when Gemini '
                  '(audio) is your transcription provider — no other service here can '
                  'tell voices apart.'),
          _toggle(store, 'priorityQueue', 'Priority transcription queue',
              'Recordings marked urgent in the library are transcribed before the '
                  'rest of the backlog on next launch.'),
          _toggle(store, 'punctuationCleanup', 'Punctuation and filler cleanup',
              'Remove filler while preserving the meaning and your words.'),
          _toggle(store, 'multiLanguage', 'Multi-language transcription',
              'Allow a language hint to be sent to speech recognition.'),
          _toggle(store, 'customVocabulary', 'Custom vocabulary',
              'Use names, terms, and product words consistently.'),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 20, 8),
            child: TextField(
              controller: _languageController,
              decoration: const InputDecoration(
                labelText: 'Language (BCP-47)',
                hintText: 'en-US, es-ES, fr-FR',
              ),
              onSubmitted: store.setTranscriptionLanguage,
              onEditingComplete: () =>
                  store.setTranscriptionLanguage(_languageController.text),
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
          const _SectionHeader('Meetings and imports'),
          _toggle(store, 'audioImport', 'Import audio',
              'Bring in WAV, MP3, M4A, FLAC, OGG or AAC files — a meeting exported '
                  'from Zoom or Teams, a lecture, a voice memo.'),
          _toggle(store, 'videoImport', 'Import video',
              'Take the audio track out of MP4, M4V and MOV files.'),
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
              'microphone. Two things do work: record the meeting through the '
              'microphone with it played out loud, or import the recording the '
              'meeting tool saved afterwards.',
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
