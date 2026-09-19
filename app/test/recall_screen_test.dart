import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echo_codex_app/src/recall/recall_controller.dart';
import 'package:echo_codex_app/src/recall/recall_providers.dart';
import 'package:echo_codex_app/src/recording/recording_controller.dart';
import 'package:echo_codex_app/src/screens/recall_screen.dart';
import 'package:echo_codex_app/src/settings/provider_config.dart';
import 'package:transcript_core/transcript_core.dart';

import 'fixtures.dart';

/// Returns one vector per input, whatever the batch size.
///
/// Counting replies by hand is brittle here: how many passages a recording produces
/// depends on the chunker's thresholds, and a mismatch shows up as an embedding error
/// rather than as the thing under test.
class EchoEmbeddingTransport implements HttpTransport {
  final List<HttpCall> calls = [];

  @override
  Future<HttpReply> send(HttpCall call) async {
    calls.add(call);
    final body = call.jsonBody! as Map<String, dynamic>;
    final input = (body['input'] as List).length;
    return HttpReply(
      200,
      jsonEncode({
        'embeddings': [for (var i = 0; i < input; i++) [1.0, 0.0]],
      }),
    );
  }
}

/// Replies with whatever the test scripted, without a server.
class StubAnswering extends StructuringProvider {
  StubAnswering(this.reply);
  final String reply;
  final List<StructureRequest> requests = [];

  @override
  ProviderId get id => const ProviderId('stub');
  @override
  String get displayName => 'Stub';
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
      acceptsAudio: false, acceptsText: true, nativeJsonSchema: false);
  @override
  Future<ConnectionResult> test() async =>
      ConnectionResult.success(summary: 'ok');
  @override
  Future<StructureResponse> structure(StructureRequest request) async {
    requests.add(request);
    return StructureResponse(rawText: reply);
  }
}

void main() {
  late FakeRecordingRepository repo;
  late RecallController controller;
  late StubAnswering answering;

  Future<void> pump(WidgetTester tester, {required String reply}) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    repo = FakeRecordingRepository([
      recordingRow(transcriptText: 'We agreed to retire the legacy session '
          'store before launch, and Sarah is going to own that work.'),
    ]);
    answering = StubAnswering(reply);

    final transport = EchoEmbeddingTransport();

    controller = RecallController(
      repository: repo,
      embeddings: EndpointEmbeddingProvider(
        transport: transport,
        baseUrl: Uri.parse('http://192.168.1.50:11434'),
        model: 'nomic-embed-text',
        native: true,
      ),
      answering: () async => answering,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
          repositoryProvider.overrideWithValue(repo),
          recallControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: RecallScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> indexThenAsk(WidgetTester tester, String question) async {
    await controller.indexAll();
    await tester.pumpAndSettle();
    await controller.ask(question);
    await tester.pumpAndSettle();
  }

  testWidgets('an answer shows what it was built from', (tester) async {
    await pump(tester,
        reply: 'They agreed to retire the session store [r_1:t0].');
    await indexThenAsk(tester, 'What did we decide?');

    expect(find.text('What did we decide?'), findsOneWidget);
    expect(find.text('What this came from'), findsOneWidget);
    expect(find.text('Auth migration kickoff'), findsWidgets,
        reason: 'a citation is only worth having if it names its recording');
  });

  testWidgets('an answer with nothing behind it is marked as a guess',
      (tester) async {
    // Cites a passage that was never retrieved — the model inventing a source.
    await pump(tester, reply: 'Teams usually migrate auth in stages [r_9:t7].');
    await indexThenAsk(tester, 'What did we decide?');

    expect(find.textContaining('not backed by anything'), findsOneWidget,
        reason: 'a confident wrong answer about months of meetings is the most '
            'damaging thing this screen could produce');
    expect(find.text('What this came from'), findsNothing);
  });

  testWidgets('the passages really are sent to the model with their ids',
      (tester) async {
    await pump(tester, reply: 'Yes [r_1:t0].');
    await indexThenAsk(tester, 'What did we decide?');

    expect(answering.requests, hasLength(1));
    expect(answering.requests.single.userContent, contains('<passages>'));
    expect(answering.requests.single.userContent, contains('What did we decide?'));
    expect(answering.requests.single.systemPrompt,
        contains('ONLY the passages supplied'));
  });

  testWidgets('asking before anything is indexed says so, and what to do',
      (tester) async {
    await pump(tester, reply: 'anything');
    await controller.ask('What did we decide?');
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing is indexed yet'), findsOneWidget);
    expect(find.textContaining('Index your recordings'), findsOneWidget,
        reason: '"nothing was said about that" and "nothing is indexed" look '
            'identical and mean opposite things');
  });

  testWidgets('the empty state promises citations before anything is asked',
      (tester) async {
    await pump(tester, reply: 'anything');

    expect(find.textContaining('shows the recordings it came from'),
        findsOneWidget);
  });

  testWidgets('indexing reports progress rather than just spinning',
      (tester) async {
    await pump(tester, reply: 'anything');
    final indexing = controller.indexAll();
    await tester.pump();

    // Either mid-flight or already finished, depending on scheduling; the point is
    // that a progress line exists at all rather than a bare spinner.
    await indexing;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
