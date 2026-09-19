import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transcript_core/transcript_core.dart';

import '../recall/recall_controller.dart';
import 'note_screen.dart';

/// Ask a question of everything that was ever recorded.
///
/// The design constraint that shapes this whole screen: an answer here is about months
/// of conversations the reader half-remembers, which is exactly the situation where a
/// confident wrong answer does the most damage and is hardest to catch. So the
/// citations are not a footnote — they are the feature. Every answer shows what it was
/// built from, each passage opens the recording it came from, and an answer that cites
/// nothing says so in plain words instead of looking like the others.
class RecallScreen extends ConsumerStatefulWidget {
  const RecallScreen({super.key});

  @override
  ConsumerState<RecallScreen> createState() => _RecallScreenState();
}

class _RecallScreenState extends ConsumerState<RecallScreen> {
  final _question = TextEditingController();

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recallControllerProvider);
    final controller = ref.read(recallControllerProvider.notifier);
    final coverage = ref.watch(recallCoverageProvider);
    final busy = state is RecallThinking || state is RecallIndexing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask your recordings'),
        actions: [
          if (controller.hasEmbeddings)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Index recordings',
              onPressed: busy
                  ? null
                  : () async {
                      await controller.indexAll();
                      ref.invalidate(recallCoverageProvider);
                    },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _question,
              enabled: !busy,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'What did we decide about the auth migration?',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Ask',
                  onPressed:
                      busy ? null : () => controller.ask(_question.text),
                ),
              ),
              onSubmitted: busy ? null : controller.ask,
            ),
          ),
          coverage.maybeWhen(
            data: (c) => _Coverage(indexed: c.$1, total: c.$2),
            orElse: () => const SizedBox.shrink(),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (state) {
              RecallIdle() => const _Blank(),
              RecallIndexing(:final done, :final total) =>
                _Indexing(done: done, total: total),
              RecallThinking() =>
                const Center(child: CircularProgressIndicator()),
              RecallFailed(:final message, :final remedy) =>
                _Problem(message: message, remedy: remedy),
              RecallAnswered(:final question, :final answer) =>
                _Answer(question: question, answer: answer),
            },
          ),
        ],
      ),
    );
  }
}

class _Coverage extends StatelessWidget {
  const _Coverage({required this.indexed, required this.total});

  final int indexed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (total == 0) return const SizedBox.shrink();
    // The distinction that matters: "nothing was said about that" and "nothing has
    // been indexed yet" produce identical empty answers and mean opposite things.
    final complete = indexed == total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Icon(
            complete ? Icons.check_circle_outline : Icons.info_outline,
            size: 15,
            color: complete
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              complete
                  ? '$indexed of $total recordings indexed'
                  : '$indexed of $total recordings indexed — the rest cannot be '
                      'searched until they are',
              style: theme.textTheme.labelSmall?.copyWith(
                color: complete
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Answer extends ConsumerWidget {
  const _Answer({required this.question, required this.answer});

  final String question;
  final RecallAnswer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Text(question, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (!answer.hadEvidence)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This answer is not backed by anything in your recordings. '
                    'Treat it as a guess, not a record of what was said.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer),
                  ),
                ),
              ],
            ),
          ),
        if (!answer.hadEvidence) const SizedBox(height: 14),
        SelectableText(answer.text, style: theme.textTheme.bodyLarge),
        if (answer.citations.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('What this came from', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final chunk in answer.citations)
            _Citation(chunk: chunk),
        ],
      ],
    );
  }
}

class _Citation extends ConsumerWidget {
  const _Citation({required this.chunk});

  final RecallChunk chunk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // The citation is only worth having if it opens the thing it cites.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NoteScreen(recordingId: chunk.source.recordingId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chunk.source.recordingTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Text(chunk.source.recordedOn,
                      style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                chunk.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Indexing extends StatelessWidget {
  const _Indexing({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                  value: total == 0 ? null : done / total),
              const SizedBox(height: 14),
              Text('Reading recording $done of $total'),
              const SizedBox(height: 6),
              Text(
                'This runs on the service you configured, so it takes as long as '
                'that service takes. It only has to happen once per recording.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, this.remedy});

  final String message;
  final String? remedy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 36, color: theme.colorScheme.error),
            const SizedBox(height: 14),
            SelectableText(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall),
            if (remedy != null) ...[
              const SizedBox(height: 8),
              Text(remedy!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Blank extends StatelessWidget {
  const _Blank();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore_outlined,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text('Ask across everything you have recorded',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Every answer shows the recordings it came from, and an answer with '
              'nothing behind it will say so.',
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
