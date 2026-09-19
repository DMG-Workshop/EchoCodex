import 'dart:convert';

import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

import 'fixtures.dart';

/// Records every prompt it is sent and replies with a queued response.
class ScriptedProvider extends StructuringProvider {
  ScriptedProvider(this.responses, {this.contextWindowTokens = 200000});

  final List<String> responses;
  final int contextWindowTokens;
  final List<StructureRequest> requests = [];

  @override
  ProviderId get id => const ProviderId('scripted');
  @override
  String get displayName => 'Scripted';
  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
        acceptsAudio: false,
        acceptsText: true,
        nativeJsonSchema: true,
        contextWindowTokens: contextWindowTokens,
        maxOutputTokens: 4096,
      );
  @override
  Future<ConnectionResult> test() async =>
      ConnectionResult.success(summary: 'ok');

  @override
  Future<StructureResponse> structure(StructureRequest request) async {
    requests.add(request);
    final index = requests.length - 1;
    return StructureResponse(
      rawText:
          responses[index < responses.length ? index : responses.length - 1],
      inputTokens: 100,
      outputTokens: 40,
    );
  }
}

/// Behaves like a real local server: a prompt past the context window does not come
/// back as a clean error, it comes back as nothing usable.
///
/// This is the shape of the failure the app was actually hitting on long recordings —
/// "the model could not produce a valid note", with nothing pointing at the context.
class ContextBoundProvider extends StructuringProvider {
  ContextBoundProvider({
    required this.reply,
    this.contextWindowTokens = 8192,
    this.maxOutputTokens = 2048,
  });

  final String reply;
  final int contextWindowTokens;
  final int maxOutputTokens;
  final List<StructureRequest> requests = [];
  final List<int> promptTokens = [];

  /// Everything the provider is asked to read: prompt, transcript and prior turns.
  int _tokensOf(StructureRequest r) {
    final text = StringBuffer()
      ..write(r.systemPrompt)
      ..write(r.userContent);
    for (final turn in r.priorTurns) {
      text.write(turn.content);
    }
    return (text.length / 3.5).ceil() +
        (jsonEncode(r.schema).length / 3.5).ceil();
  }

  @override
  ProviderId get id => const ProviderId('bounded');
  @override
  String get displayName => 'Bounded';
  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
        acceptsAudio: false,
        acceptsText: true,
        nativeJsonSchema: true,
        contextWindowTokens: contextWindowTokens,
        maxOutputTokens: maxOutputTokens,
      );
  @override
  Future<ConnectionResult> test() async =>
      ConnectionResult.success(summary: 'ok');

  @override
  Future<StructureResponse> structure(StructureRequest request) async {
    requests.add(request);
    final tokens = _tokensOf(request);
    promptTokens.add(tokens);
    if (tokens + maxOutputTokens > contextWindowTokens) {
      return const StructureResponse(
          rawText: '', inputTokens: 0, outputTokens: 0);
    }
    return StructureResponse(
        rawText: reply, inputTokens: 100, outputTokens: 40);
  }
}

void main() {
  Transcript longTranscript({int segments = 200}) => Transcript([
        for (var i = 0; i < segments; i++)
          TranscriptSegment(
            startMs: i * 5000,
            endMs: (i + 1) * 5000,
            text:
                'This is turn number $i and it carries a reasonable amount of '
                'speech so the window budget is actually consumed.',
            speaker: 'SPEAKER_0${i % 3}',
          ),
      ]);

  group('section planner', () {
    test('a transcript inside the budget is one window', () {
      final windows = const SectionPlanner()
          .split(longTranscript(segments: 3), budgetTokens: 100000);
      expect(windows, hasLength(1));
      expect(windows.single.total, 1);
    });

    test('splits a long transcript into windows within budget', () {
      final windows =
          const SectionPlanner().split(longTranscript(), budgetTokens: 2000);

      expect(windows.length, greaterThan(1));
      for (final window in windows) {
        expect(window.estimatedTokens, lessThanOrEqualTo(2600),
            reason:
                'a window that overflows the context is silently truncated');
      }
    });

    test('windows tile the transcript with nothing dropped or repeated', () {
      final transcript = longTranscript();
      final windows =
          const SectionPlanner().split(transcript, budgetTokens: 2000);

      final rebuilt = [for (final w in windows) ...w.segments];
      expect(rebuilt.length, transcript.segments.length,
          reason: 'losing a segment here loses that part of the meeting');
      expect(
        rebuilt.map((s) => s.startMs),
        orderedEquals(transcript.segments.map((s) => s.startMs)),
      );
    });

    test('windows are numbered for the prompt', () {
      final windows =
          const SectionPlanner().split(longTranscript(), budgetTokens: 2000);
      expect(windows.first.index, 1);
      expect(windows.last.index, windows.length);
      expect(windows.every((w) => w.total == windows.length), isTrue);
    });

    test('breaks on a speaker change rather than mid-turn', () {
      // Alternating speakers: every boundary should land where the speaker changes.
      final windows =
          const SectionPlanner().split(longTranscript(), budgetTokens: 1500);

      for (var i = 1; i < windows.length; i++) {
        final previous = windows[i - 1].segments.last.speaker;
        final next = windows[i].segments.first.speaker;
        expect(next, isNot(previous),
            reason:
                'cutting mid-turn produces half-formed items on both sides');
      }
    });

    test('a single segment larger than the budget gets its own window', () {
      final transcript = Transcript([
        TranscriptSegment(startMs: 0, endMs: 60000, text: 'word ' * 5000),
        const TranscriptSegment(
            startMs: 60000, endMs: 61000, text: 'short one'),
      ]);
      final windows =
          const SectionPlanner().split(transcript, budgetTokens: 500);

      expect(windows, hasLength(2));
      expect(windows.first.segments, hasLength(1),
          reason: 'it cannot be split without cutting mid-sentence');
    });

    test('an empty transcript plans nothing', () {
      expect(
          const SectionPlanner().split(const Transcript([]), budgetTokens: 100),
          isEmpty);
    });

    test(
        'a non-positive budget is a programming error, not a silent single window',
        () {
      expect(
        () => const SectionPlanner().split(longTranscript(), budgetTokens: 0),
        throwsArgumentError,
      );
    });
  });

  group('map/reduce', () {
    Future<StructureOutcome> runLong(
      ScriptedProvider provider, {
      void Function(StructureProgress)? onProgress,
    }) =>
        StructuringPipeline(provider: provider).run(
          transcript: longTranscript(),
          referenceDate: '2026-09-05',
          timeZone: 'UTC',
          sttProviderName: 'Whisper',
          onProgress: onProgress,
        );

    test('a transcript that fits takes one call', () async {
      final provider = ScriptedProvider([jsonEncode(validNoteJson())]);
      await StructuringPipeline(provider: provider).run(
        transcript: const Transcript([
          TranscriptSegment(startMs: 0, endMs: 5000, text: fixtureTranscript),
        ]),
        referenceDate: '2026-09-05',
        timeZone: 'UTC',
        sttProviderName: 'Whisper',
      );
      expect(provider.requests, hasLength(1));
    });

    test('a transcript that does not fit is mapped then reduced', () async {
      final provider = ScriptedProvider(
        List.filled(20, jsonEncode(validNoteJson())),
        contextWindowTokens: 8192,
      );
      await runLong(provider);

      expect(provider.requests.length, greaterThan(2),
          reason: 'several windows plus one merge');

      final prompts = provider.requests.map((r) => r.systemPrompt).toList();
      expect(prompts.where((p) => p.contains('SECTION')).length,
          provider.requests.length - 1);
      expect(prompts.last, contains('merging'),
          reason: 'the final call is the reduce pass');
    });

    test('each window is told to keep offsets absolute', () async {
      final provider = ScriptedProvider(
        List.filled(20, jsonEncode(validNoteJson())),
        contextWindowTokens: 8192,
      );
      await runLong(provider);

      final mapPrompt = provider.requests
          .firstWhere((r) => r.systemPrompt.contains('SECTION'));
      expect(mapPrompt.systemPrompt, contains('absolute positions'));
    });

    test('the participant roster is carried forward between windows', () async {
      final provider = ScriptedProvider(
        List.filled(20, jsonEncode(validNoteJson())),
        contextWindowTokens: 8192,
      );
      await runLong(provider);

      final sections = provider.requests
          .where((r) => r.systemPrompt.contains('SECTION'))
          .toList();
      expect(sections.first.systemPrompt, contains('[]'),
          reason: 'nobody is known before the first window');
      expect(sections[1].systemPrompt, contains('p_priya'),
          reason: 'four separate Sarahs in one note is what this prevents');
    });

    test('the reduce pass receives the partial documents, not the transcript',
        () async {
      final provider = ScriptedProvider(
        List.filled(20, jsonEncode(validNoteJson())),
        contextWindowTokens: 8192,
      );
      await runLong(provider);

      final reduce = provider.requests.last;
      expect(reduce.userContent, contains('partial_documents'));
      expect(reduce.userContent, isNot(contains('This is turn number')),
          reason: 're-sending the transcript to merge would pay for it twice');
    });

    test('progress covers every window plus the merge', () async {
      final provider = ScriptedProvider(
        List.filled(20, jsonEncode(validNoteJson())),
        contextWindowTokens: 8192,
      );
      final seen = <StructureProgress>[];
      await runLong(provider, onProgress: seen.add);

      expect(seen, isNotEmpty);
      expect(seen.last.fraction, 1.0);
      expect(seen.any((p) => p.isMerging), isTrue,
          reason: 'the merge is a visible step, not a mysterious pause at 90%');
    });

    test('tokens are summed across every window and the merge', () async {
      final provider = ScriptedProvider(
        List.filled(20, jsonEncode(validNoteJson())),
        contextWindowTokens: 8192,
      );
      final outcome = await runLong(provider);

      expect(outcome.inputTokens, provider.requests.length * 100,
          reason: 'the cost meter must show what the whole note cost');
    });

    test('an unknown local context window takes the split path, conservatively',
        () async {
      final provider = ScriptedProvider(
        List.filled(20, jsonEncode(validNoteJson())),
        contextWindowTokens: 0,
      );
      await runLong(provider);

      expect(provider.requests.length, greaterThan(1),
          reason:
              'unknown must never be optimistic — silent truncation is worse');
    });

    test('quotes are verified against the whole transcript, not one window',
        () async {
      final note = validNoteJson();
      (note['tasks'] as List<dynamic>).add({
        ...((note['tasks'] as List<dynamic>).first as Map<String, dynamic>),
        'id': 't_invented',
        'sourceRef': {
          'startMs': 1,
          'endMs': 2,
          'quote': 'nobody said any of these words at all',
        },
      });

      final provider = ScriptedProvider(
        List.filled(20, jsonEncode(note)),
        contextWindowTokens: 8192,
      );
      final outcome = await runLong(provider);

      expect(outcome.unverifiedQuotes, contains('t_invented'));
    });
  });

  group('a long recording', () {
    /// A window's worth of note, fat enough that a handful of them cannot share one
    /// prompt — which is what every partial looks like after a real meeting.
    String fatPartial() {
      final note = validNoteJson();
      final section =
          (note['sections'] as List<dynamic>).first as Map<String, dynamic>;
      section['bullets'] = [
        for (var i = 0; i < 24; i++)
          'A point that was made during this stretch of the meeting, number $i, '
              'written out at the length a real bullet runs to.',
      ];
      return jsonEncode(note);
    }

    Future<StructureOutcome> run(StructuringProvider provider) =>
        StructuringPipeline(provider: provider).run(
          transcript: longTranscript(segments: 600),
          referenceDate: '2026-09-05',
          timeZone: 'UTC',
          sttProviderName: 'Whisper',
        );

    test('finishes instead of overflowing the context at the merge', () async {
      final provider = ContextBoundProvider(reply: fatPartial());

      final outcome = await run(provider);

      expect(outcome.document.sections, isNotEmpty,
          reason:
              'the map phase was always budgeted; the merge was not, and an '
              'hour of audio produces enough partials to overflow it');
      expect(
        provider.promptTokens.every((t) => t + 2048 <= 8192),
        isTrue,
        reason: 'no request may exceed the window the map phase is kept inside',
      );
    });

    test('merges in rounds rather than one oversized call', () async {
      final provider = ContextBoundProvider(reply: fatPartial());

      await run(provider);

      final reduces = provider.requests
          .where((r) => r.userContent.contains('<partial_documents>'))
          .toList();
      expect(reduces.length, greaterThan(1),
          reason: 'one merge of every partial is the call that used to fail');
      expect(reduces.last.userContent.contains('<partial_documents>'), isTrue);
    });

    test('every partial reaches the merge — none are dropped to fit', () async {
      final provider = ContextBoundProvider(reply: fatPartial());

      await run(provider);

      final maps = provider.requests
          .where((r) => r.userContent.contains('<transcript>'))
          .length;
      final mergedIn = provider.requests
          .where((r) => r.userContent.contains('<partial_documents>'))
          .map((r) => (jsonDecode(r.userContent
                  .replaceAll('<partial_documents>', '')
                  .replaceAll('</partial_documents>', '')
                  .trim()) as List)
              .length)
          .fold<int>(0, (a, b) => a + b);

      expect(mergedIn, greaterThanOrEqualTo(maps),
          reason:
              'losing a window of the meeting to make the arithmetic work is '
              'not a trade this pipeline makes');
    });

    test('a short recording still merges in a single call', () async {
      // Big enough that every partial fits one merge, small enough that the
      // transcript still has to be split.
      final provider = ScriptedProvider(
        List.filled(30, jsonEncode(validNoteJson())),
        contextWindowTokens: 20000,
      );

      await StructuringPipeline(provider: provider).run(
        transcript: longTranscript(segments: 600),
        referenceDate: '2026-09-05',
        timeZone: 'UTC',
        sttProviderName: 'Whisper',
      );

      final reduces = provider.requests
          .where((r) => r.userContent.contains('<partial_documents>'))
          .length;
      expect(reduces, 1,
          reason:
              'the tree must not cost extra round trips when one call fits');
    });

    test('a single partial too big for any budget is still attempted',
        () async {
      // One window, one enormous partial: grouping cannot help, and refusing to
      // produce anything is worse than one oversized try.
      final provider = ContextBoundProvider(
        reply: jsonEncode(validNoteJson()),
        contextWindowTokens: 3000,
        maxOutputTokens: 2000,
      );

      await expectLater(run(provider), throwsA(isA<StructuringException>()));
      expect(provider.requests, isNotEmpty,
          reason: 'it has to have tried, not refused up front');
    });
  });
}
