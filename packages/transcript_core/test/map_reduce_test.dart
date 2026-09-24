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

/// A local server with a small, honest context, answering each request the way one really
/// would: a prompt that does not fit comes back as nothing usable, every section gets its
/// own note, and every one of those notes numbers its first task `t1`.
///
/// The last detail is the one that matters. Real partials are big enough that two of them
/// cannot share a 2,500-token merge prompt, which is all an assumed 8k context leaves.
class SmallContextServer extends StructuringProvider {
  SmallContextServer({
    this.contextWindowTokens = 8192,
    this.maxOutputTokens = 2048,
    this.bulletsPerSection = 40,
    this.answersMeta = true,
  });

  final int contextWindowTokens;
  final int maxOutputTokens;

  /// How fat each section's note is. Forty bullets is about 1,900 tokens of JSON, which is
  /// what a real note for a few minutes of meeting runs to.
  final int bulletsPerSection;

  /// Whether it can write the merge's title and summary. False stands in for a model that
  /// ignores the smaller schema and hands back something else entirely.
  final bool answersMeta;

  final List<StructureRequest> requests = [];
  final List<int> promptTokens = [];
  var _sections = 0;

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

  Map<String, dynamic> sectionNote(int n) {
    final note = validNoteJson();
    (note['meta'] as Map<String, dynamic>)
      ..['title'] = 'Section $n'
      ..['summary'] = 'Section $n covered ground of its own and closed on a '
          'commitment nobody else made.'
      ..['extractionConfidence'] = n == 2 ? 'low' : 'high';
    note['sections'] = [
      {
        'heading': 'Topic $n',
        'bullets': [
          for (var i = 0; i < bulletsPerSection; i++)
            'Point $i made during section $n, written out at the length a real '
                'bullet runs to so that one of these notes is a realistic size.',
        ],
        'sourceRef': {
          'startMs': n * 1000,
          'endMs': n * 1000 + 500,
          'quote': 'This is turn number $n and it carries',
        },
      },
    ];
    note['tasks'] = [
      {
        ...(validNoteJson()['tasks'] as List).first as Map<String, dynamic>,
        // Every section numbers its own first task `t1`. Two of these are not one task.
        'id': 't1',
        'title': 'Do the thing that came out of section $n',
      },
    ];
    return note;
  }

  @override
  ProviderId get id => const ProviderId('small-context');
  @override
  String get displayName => 'Small context';
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
    if (request.userContent.contains('<section_summaries>')) {
      return StructureResponse(
        rawText: answersMeta
            ? jsonEncode({
                'title': 'One long meeting',
                'summary': 'A whole-recording summary, written from the '
                    'section summaries alone.',
                'recordingType': 'meeting',
                'language': 'en-US',
                'extractionConfidence': 'low',
              })
            : jsonEncode(validNoteJson()),
        inputTokens: 100,
        outputTokens: 40,
      );
    }
    return StructureResponse(
      rawText: jsonEncode(sectionNote(++_sections)),
      inputTokens: 100,
      outputTokens: 40,
    );
  }
}

/// Big enough that the merge is model-led: the transcript still has to be split, but two
/// partial documents fit one merge prompt.
///
/// 8192 does not, once the 4096-token output reserve is taken out — it leaves a 500-token
/// budget, which is less than a single partial. That case is real and has its own group
/// below; these tests are about the merge that happens when there is room for it.
const int mergeableContext = 12000;

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
        contextWindowTokens: mergeableContext,
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
        contextWindowTokens: mergeableContext,
      );
      await runLong(provider);

      final mapPrompt = provider.requests
          .firstWhere((r) => r.systemPrompt.contains('SECTION'));
      expect(mapPrompt.systemPrompt, contains('absolute positions'));
    });

    test('the participant roster is carried forward between windows', () async {
      final provider = ScriptedProvider(
        List.filled(20, jsonEncode(validNoteJson())),
        contextWindowTokens: mergeableContext,
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
        contextWindowTokens: mergeableContext,
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
        contextWindowTokens: mergeableContext,
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
        contextWindowTokens: mergeableContext,
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
        contextWindowTokens: mergeableContext,
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

  group('an hour on a small context', () {
    // What the user actually has: a local server that will not say how big its context is,
    // so the pipeline assumes 8k and has about 2,500 tokens for the merge. Half an hour
    // produced few enough sections to squeeze into one merge call; an hour did not, and the
    // note came back as "the model could not produce a valid note" instead.
    Future<StructureOutcome> run(SmallContextServer server,
            {int segments = 900}) =>
        StructuringPipeline(provider: server).run(
          transcript: longTranscript(segments: segments),
          referenceDate: '2026-09-05',
          timeZone: 'UTC',
          sttProviderName: 'Whisper',
        );

    test('produces a note instead of an error', () async {
      final server = SmallContextServer();

      final outcome = await run(server);

      expect(outcome.document.sections, isNotEmpty);
      expect(outcome.document.tasks, isNotEmpty);
      expect(
        server.promptTokens.every((t) => t + server.maxOutputTokens <= 8192),
        isTrue,
        reason: 'not one request may exceed the context the map phase respects',
      );
    });

    test('keeps every section, and every section\'s task', () async {
      final server = SmallContextServer();

      final outcome = await run(server);

      final sections = server.requests
          .where((r) => r.userContent.contains('<transcript>'))
          .length;
      expect(sections, greaterThan(4),
          reason:
              'an hour at this budget is many sections, or this proves nothing');
      expect(outcome.document.sections, hasLength(sections),
          reason: 'losing a section loses that part of the meeting');
      expect(outcome.document.tasks, hasLength(sections));
    });

    test('holds ids unique across sections that all numbered their task t1',
        () async {
      final server = SmallContextServer();

      final outcome = await run(server);

      final ids = outcome.document.tasks.map((t) => t.id).toList();
      expect(ids.toSet(), hasLength(ids.length),
          reason: 'two cards with one id is a duplicate key on the board');
    });

    test('a dependency still points at the task it pointed at', () async {
      final server = SmallContextServer();
      final outcome = await run(server);

      final ids = outcome.document.tasks.map((t) => t.id).toSet();
      for (final task in outcome.document.tasks) {
        for (final dep in task.dependsOn) {
          expect(ids, contains(dep),
              reason: 'a renamed id must take its references with it');
        }
      }
    });

    test('spends its last request on the summary, not on the documents',
        () async {
      final server = SmallContextServer();

      final outcome = await run(server);

      final last = server.requests.last;
      expect(last.userContent, contains('<section_summaries>'));
      expect(last.userContent, isNot(contains('<partial_documents>')),
          reason:
              'handing the model every document is the call that does not fit');
      expect(
          outcome.document.meta.summary, contains('whole-recording summary'));
      expect(
        (jsonEncode(last.schema).length / 3.5).ceil(),
        lessThan(1000),
        reason: 'the small call must carry the small schema',
      );
    });

    test('still finishes when the model cannot write the summary either',
        () async {
      final server = SmallContextServer(answersMeta: false);

      final outcome = await run(server);

      expect(outcome.document.sections, isNotEmpty,
          reason: 'plain prose beats an error on an hour of audio');
      expect(outcome.document.meta.summary, contains('Section 1'),
          reason: 'the stitched summary is the section summaries, joined');
    });

    test('takes the lowest confidence of any section', () async {
      final server = SmallContextServer(answersMeta: false);

      final outcome = await run(server);

      expect(
          outcome.document.meta.extractionConfidence, ExtractionConfidence.low,
          reason: 'a merged note is only as good as its worst section');
    });

    test('still merges with the model when two notes do fit one prompt',
        () async {
      // Same recording, a server that admits to 32k. The model-led merge is better at
      // folding a commitment made twice, so it must not be given up when it is affordable.
      final server = SmallContextServer(contextWindowTokens: 32768);

      await run(server);

      expect(
        server.requests
            .any((r) => r.userContent.contains('<partial_documents>')),
        isTrue,
        reason: 'the model merge is the better one wherever it fits',
      );
    });
  });
}
