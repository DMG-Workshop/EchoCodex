import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transcript_core/transcript_core.dart';

import '../data/database.dart' as db;
import '../data/repository.dart';
import '../recording/recording_controller.dart';
import 'package:intl/intl.dart';

import 'export_sheet.dart';
import 'calendar_view.dart';
import 'timeline_view.dart';
import 'record_screen.dart';

/// One recording: its notes, its tasks, and the transcript underneath.
///
/// Three tabs rather than one scroll, because the three are read for different reasons —
/// the notes to catch up, the tasks to act, the transcript to check what was actually
/// said. Every item can be traced to the moment it came from.
class NoteScreen extends ConsumerWidget {
  const NoteScreen({super.key, required this.recordingId});

  final String recordingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordings = ref.watch(recordingsProvider);

    return recordings.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (items) {
        final recording = items.where((r) => r.id == recordingId).firstOrNull;
        if (recording == null) {
          return const Scaffold(
            body: Center(child: Text('That recording is no longer here.')),
          );
        }
        return _NoteView(recording: recording);
      },
    );
  }
}

class _NoteView extends ConsumerWidget {
  const _NoteView({required this.recording});

  final db.Recording recording;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this recording?'),
            content: const Text(
                'The audio and its notes are removed from this device. This cannot '
                'be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(repositoryProvider).delete(recording.id);
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Recording deleted')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = decodeNote(recording);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            recording.title.isEmpty ? 'Untitled recording' : recording.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (note != null)
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Export',
                onPressed: () => openExportSheet(
                  context,
                  note: note,
                  recording: recording,
                  recordedOn: DateFormat.yMMMd().format(recording.startedAt),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete recording',
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Notes'),
              Tab(text: 'Gantt'),
              Tab(text: 'Calendar'),
              Tab(text: 'Study'),
              Tab(text: 'Transcript'),
            ],
          ),
        ),
        body: note == null
            ? const _NotStructuredYet()
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 900) {
                    return _TabletOverview(note: note, recording: recording);
                  }
                  return TabBarView(children: [
                    _NotesTab(note: note, recording: recording),
                    TimelineView(recordingId: recording.id, note: note),
                    CalendarView(recordingId: recording.id, note: note),
                    _StudyTab(note: note),
                    _TranscriptTab(note: note, recording: recording),
                  ]);
                },
              ),
      ),
    );
  }
}

class _TabletOverview extends StatelessWidget {
  const _TabletOverview({required this.note, required this.recording});

  final NoteDocument note;
  final db.Recording recording;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: _NotesTab(note: note, recording: recording)),
          const VerticalDivider(width: 1),
          Expanded(
            child: TimelineView(recordingId: recording.id, note: note),
          ),
        ],
      );
}

class _NotStructuredYet extends StatelessWidget {
  const _NotStructuredYet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text('No notes for this recording',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'The audio and any transcript are still saved. You can write notes from '
              'it again with a different service.',
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

class _NotesTab extends ConsumerWidget {
  const _NotesTab({required this.note, required this.recording});

  final NoteDocument note;
  final db.Recording recording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Text(note.meta.summary, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        if (note.meta.extractionConfidence != ExtractionConfidence.high)
          _Caveat(
            text: note.meta.extractionConfidence == ExtractionConfidence.low
                ? 'The audio was hard to make out, so these notes may be incomplete.'
                : 'Parts of the audio were unclear.',
          ),
        for (final section in note.sections) ...[
          const SizedBox(height: 24),
          Text(section.heading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final bullet in section.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('·  ', style: theme.textTheme.bodyLarge),
                  Expanded(
                      child: Text(bullet, style: theme.textTheme.bodyMedium)),
                  IconButton(
                    icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                    tooltip: 'Save to Codex',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await ref.read(repositoryProvider).createCodexNote(
                            bullet,
                            sourceRecordingId: recording.id,
                            sourceRecordingTitle: recording.title,
                          );
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Saved to Codex')),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
        if (note.decisions.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Decisions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final decision in note.decisions)
            _Cited(
              quote: decision.sourceRef.quote,
              child:
                  Text(decision.statement, style: theme.textTheme.bodyMedium),
            ),
        ],
        if (note.openQuestions.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Open questions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final question in note.openQuestions)
            _Cited(
              quote: question.sourceRef.quote,
              child: Text(question.question, style: theme.textTheme.bodyMedium),
            ),
        ],
        const SizedBox(height: 32),
        _PrivacyReport(recording: recording),
        _Provenance(recording: recording),
      ],
    );
  }
}

class _PrivacyReport extends StatelessWidget {
  const _PrivacyReport({required this.recording});

  final db.Recording recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio =
        recording.audioPath == null ? 'Not stored' : 'Stored on this device';
    final transcript =
        recording.transcriptText == null ? 'Not available' : 'Stored locally';
    final note =
        recording.noteJson == null ? 'Not generated' : 'Stored locally';
    final posture = recording.localOnly
        ? 'Local-only recording'
        : 'Provider configuration at recording time';
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: ExpansionTile(
        leading: const Icon(Icons.privacy_tip_outlined),
        title: const Text('Privacy report'),
        subtitle: Text(posture),
        children: [
          ListTile(
            dense: true,
            title: const Text('Audio'),
            subtitle: Text(audio),
          ),
          ListTile(
            dense: true,
            title: const Text('Transcript'),
            subtitle: Text(transcript),
          ),
          ListTile(
            dense: true,
            title: const Text('Structured note'),
            subtitle: Text(note),
          ),
          ListTile(
            dense: true,
            title: const Text('Transcription provider'),
            subtitle: Text(recording.transcriptionProviderId ?? 'Unknown'),
          ),
          ListTile(
            dense: true,
            title: const Text('Note provider'),
            subtitle: Text(recording.structuringProviderId ?? 'Unknown'),
          ),
        ],
      ),
    );
  }
}

/// Key concepts, flashcards and a quiz — the study aids, when any were generated.
class _StudyTab extends StatelessWidget {
  const _StudyTab({required this.note});

  final NoteDocument note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (note.keyConcepts.isEmpty &&
        note.flashcards.isEmpty &&
        note.quiz.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined,
                  size: 40, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 14),
              Text('No study aids for this recording',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Turn on key concepts, flashcards or quizzes in Settings, then write '
                'the notes again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        if (note.keyConcepts.isNotEmpty) ...[
          Text('Key concepts', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final concept in note.keyConcepts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(concept.term,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(concept.explanation, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          const SizedBox(height: 20),
        ],
        if (note.flashcards.isNotEmpty) ...[
          Text('Flashcards', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final card in note.flashcards) _FlashcardTile(card: card),
          const SizedBox(height: 20),
        ],
        if (note.quiz.isNotEmpty) ...[
          Text('Quiz', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < note.quiz.length; i++)
            _QuizTile(index: i + 1, question: note.quiz[i]),
        ],
      ],
    );
  }
}

class _FlashcardTile extends StatefulWidget {
  const _FlashcardTile({required this.card});

  final Flashcard card;

  @override
  State<_FlashcardTile> createState() => _FlashcardTileState();
}

class _FlashcardTileState extends State<_FlashcardTile> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => setState(() => _revealed = !_revealed),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _revealed ? widget.card.back : widget.card.front,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              Icon(_revealed ? Icons.visibility_off : Icons.visibility,
                  color: theme.colorScheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizTile extends StatefulWidget {
  const _QuizTile({required this.index, required this.question});

  final int index;
  final QuizQuestion question;

  @override
  State<_QuizTile> createState() => _QuizTileState();
}

class _QuizTileState extends State<_QuizTile> {
  int? _selected;
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final correct = widget.question.correctIndex;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.index}. ${widget.question.question}',
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            RadioGroup<int>(
              groupValue: _selected,
              onChanged:
                  _checked ? (_) {} : (v) => setState(() => _selected = v),
              child: Column(
                children: [
                  for (var i = 0; i < widget.question.choices.length; i++)
                    RadioListTile<int>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: i,
                      title: Text(
                        widget.question.choices[i],
                        style: _checked
                            ? TextStyle(
                                color: i == correct
                                    ? theme.colorScheme.primary
                                    : (i == _selected
                                        ? theme.colorScheme.error
                                        : null),
                                fontWeight: i == correct
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            if (!_checked)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _selected == null
                      ? null
                      : () => setState(() => _checked = true),
                  child: const Text('Check answer'),
                ),
              )
            else ...[
              const SizedBox(height: 4),
              Text(
                _selected == correct ? 'Correct.' : 'Not quite.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _selected == correct
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.question.explanation?.trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(widget.question.explanation!,
                      style: theme.textTheme.bodySmall),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TranscriptTab extends ConsumerStatefulWidget {
  const _TranscriptTab({required this.note, required this.recording});

  final NoteDocument note;
  final db.Recording recording;

  @override
  ConsumerState<_TranscriptTab> createState() => _TranscriptTabState();
}

class _TranscriptTabState extends ConsumerState<_TranscriptTab> {
  bool _showRaw = false;
  Map<String, String> _editedNames = const {};

  List<_SpeakerSegment> get _segments {
    final raw = widget.recording.transcriptSegmentsJson;
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((item) {
        return _SpeakerSegment(
          startMs: item['startMs'] as int? ?? 0,
          endMs: item['endMs'] as int? ?? 0,
          text: item['text'] as String? ?? '',
          speaker: item['speaker'] as String?,
        );
      }).toList();
    } on Object {
      return const [];
    }
  }

  Map<String, String> get _speakerNames {
    final raw = widget.recording.speakerNamesJson;
    if (raw == null) return _editedNames;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _editedNames;
      return {
        ...decoded.map((key, value) => MapEntry('$key', '$value')),
        ..._editedNames,
      };
    } on Object {
      return _editedNames;
    }
  }

  Future<void> _editSpeakerNames() async {
    final labels = _segments
        .map((segment) => segment.speaker)
        .whereType<String>()
        .toSet()
        .toList();
    if (labels.isEmpty) return;
    final controllers = {
      for (final label in labels)
        label: TextEditingController(text: _speakerNames[label] ?? label),
    };
    final names = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name speakers'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final label in labels)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: controllers[label],
                    decoration: InputDecoration(labelText: label),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              {
                for (final label in labels)
                  label: controllers[label]!.text.trim().isEmpty
                      ? label
                      : controllers[label]!.text.trim(),
              },
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    });
    if (names == null || !mounted) return;
    setState(() => _editedNames = names);
    await ref
        .read(repositoryProvider)
        .saveSpeakerNames(widget.recording.id, names);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = widget.recording.transcriptText;
    final cleaned = widget.recording.cleanedTranscriptText;

    if (raw == null && cleaned == null) {
      return _CitedTranscript(note: widget.note);
    }

    final showingRaw = _showRaw || cleaned == null;
    final text = (showingRaw ? raw : cleaned) ?? raw ?? '';
    final segments = showingRaw ? _segments : const <_SpeakerSegment>[];
    final hasSpeakerLabels = segments.any((segment) => segment.speaker != null);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
          child: Row(
            children: [
              if (cleaned != null)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Cleaned')),
                    ButtonSegment(value: true, label: Text('Raw')),
                  ],
                  selected: {showingRaw},
                  onSelectionChanged: (s) => setState(() => _showRaw = s.first),
                ),
              if (hasSpeakerLabels) ...[
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.people_outline),
                  tooltip: 'Edit speaker names',
                  onPressed: _editSpeakerNames,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: segments.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final segment in segments)
                        Semantics(
                          label:
                              'Transcript segment at ${_timestamp(segment.startMs)}',
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: SelectableText(
                              '${_timestamp(segment.startMs)}  '
                              '${segment.speaker == null ? '' : '${_speakerNames[segment.speaker] ?? segment.speaker}: '}'
                              '${segment.text}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                    ],
                  )
                : SelectableText(
                    text.isEmpty ? 'No transcript was stored.' : text,
                    style: theme.textTheme.bodyMedium,
                  ),
          ),
        ),
      ],
    );
  }

  static String _timestamp(int ms) =>
      formatDuration(Duration(milliseconds: ms));
}

class _SpeakerSegment {
  const _SpeakerSegment({
    required this.startMs,
    required this.endMs,
    required this.text,
    this.speaker,
  });

  final int startMs;
  final int endMs;
  final String text;
  final String? speaker;
}

/// The pre-Phase-2 reading view: what could be reconstructed from the note's cited
/// spans, for a recording made before the full transcript was stored alongside it.
class _CitedTranscript extends StatelessWidget {
  const _CitedTranscript({required this.note});

  final NoteDocument note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refs = [
      ...note.sections.map((s) => (s.sourceRef, s.heading)),
      ...note.decisions.map((d) => (d.sourceRef, d.statement)),
      ...note.tasks.map((t) => (t.sourceRef, t.title)),
    ]..sort((a, b) => (a.$1.startMs ?? 0).compareTo(b.$1.startMs ?? 0));

    if (refs.isEmpty) {
      return const Center(child: Text('No transcript was stored.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      itemCount: refs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, i) {
        final (ref, label) = refs[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _timestamp(ref.startMs),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text('“${ref.quote}”', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        );
      },
    );
  }

  static String _timestamp(int? ms) =>
      ms == null ? '—' : formatDuration(Duration(milliseconds: ms));
}

/// Shows the words an item was drawn from. Provenance is the whole reason the schema
/// requires a quote, so the UI shows it rather than hiding it behind a tap.
class _Cited extends StatelessWidget {
  const _Cited({required this.quote, required this.child});

  final String quote;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: 3),
          Text(
            '“$quote”',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _Caveat extends StatelessWidget {
  const _Caveat({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

/// Which services produced this note, and what it cost.
///
/// Users spending their own API credit are owed both. Token counts are always shown
/// because they are measured; a dollar figure appears only where a rate is actually
/// known, since a guessed price is believed and prices change without warning.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.recording});

  final db.Recording recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estimate = Pricing.withSeededRates().estimate(
      model: recording.structuringModel,
      inputTokens: recording.inputTokens ?? 0,
      outputTokens: recording.outputTokens ?? 0,
    );

    final services = [
      if (recording.transcriptionProviderId != null)
        'Transcribed by ${recording.transcriptionProviderId}',
      if (recording.structuringProviderId != null)
        'written by ${recording.structuringProviderId}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 10),
        Text(
          services,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (recording.inputTokens != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                estimate.formattedTokens,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (estimate.hasPrice) ...[
                Text(' · ',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(
                  estimate.formattedDollars,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
