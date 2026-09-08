import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echo_codex_app/src/data/database.dart' as db;
import 'package:echo_codex_app/src/recording/recording_controller.dart';
import 'package:echo_codex_app/src/screens/library_screen.dart';
import 'package:echo_codex_app/src/settings/provider_config.dart';

import 'fixtures.dart';

void main() {
  late FakeRecordingRepository repo;

  Future<void> pumpLibrary(
    WidgetTester tester, {
    List<db.Recording>? rows,
    Map<String, Object> settings = const {},
  }) async {
    repo = FakeRecordingRepository(rows ?? [recordingRow()]);
    SharedPreferences.setMockInitialValues(settings);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('searching filters by title and transcript text', (tester) async {
    await pumpLibrary(tester, rows: [
      recordingRow(),
      recordingRow(
        structured: false,
        transcriptText: 'a totally different subject',
      ).copyWith(id: 'r_2', title: 'Standup notes'),
    ]);

    expect(find.text('Auth migration kickoff'), findsOneWidget);
    expect(find.text('Standup notes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'kickoff');
    await tester.pumpAndSettle();

    expect(find.text('Auth migration kickoff'), findsOneWidget);
    expect(find.text('Standup notes'), findsNothing);
  });

  testWidgets('searching finds generated note content', (tester) async {
    final note = noteJson();
    final task = (note['tasks'] as List<dynamic>).first as Map<String, dynamic>;
    task['title'] = 'Prepare the launch readiness checklist';
    await pumpLibrary(tester, rows: [
      recordingRow(
        transcriptText: 'unrelated transcript text',
        overrideNote: jsonEncode(note),
      ).copyWith(title: 'A different recording'),
    ]);

    await tester.enterText(
      find.byType(TextField),
      'launch readiness checklist',
    );
    await tester.pumpAndSettle();

    expect(find.text('A different recording'), findsOneWidget);
  });

  testWidgets('an unfinished recording can be marked urgent', (tester) async {
    await pumpLibrary(tester, rows: [recordingRow(structured: false)]);

    expect(find.byIcon(Icons.bolt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsNothing);

    await tester.tap(find.byIcon(Icons.bolt_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });

  testWidgets('import is offered by default', (tester) async {
    await pumpLibrary(tester);
    expect(find.byTooltip('Import a recording'), findsOneWidget);
  });

  testWidgets('turning both import features off removes the action',
      (tester) async {
    await pumpLibrary(tester, settings: {
      'workflow.audioImport': false,
      'workflow.videoImport': false,
    });

    expect(find.byTooltip('Import a recording'), findsNothing,
        reason: 'an action that would only report being disabled is worse than none');
  });

  testWidgets('video import alone still offers the action', (tester) async {
    await pumpLibrary(tester, settings: {'workflow.audioImport': false});
    expect(find.byTooltip('Import a recording'), findsOneWidget);
  });

  testWidgets('swiping asks for confirmation before deleting anything',
      (tester) async {
    await pumpLibrary(tester);

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete this recording?'), findsOneWidget);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    expect(find.text('Auth migration kickoff'), findsOneWidget,
        reason: 'declining the dialog must leave the recording in place');
    expect(repo.deletedIds, isEmpty);
  });

  testWidgets('confirming a swipe removes the row and reports it', (tester) async {
    await pumpLibrary(tester);

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Auth migration kickoff'), findsNothing,
        reason: 'the list updates immediately, not after a full reload');
    expect(find.text('Recording deleted'), findsOneWidget);
    expect(repo.deletedIds, ['r_1']);
  });
}
