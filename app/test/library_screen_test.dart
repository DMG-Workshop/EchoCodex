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
    List<db.CodexNote> codexNotes = const [],
    Map<String, Object> settings = const {},
  }) async {
    repo = FakeRecordingRepository(rows ?? [recordingRow()],
        codexNotes: codexNotes);
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

  group('the searchable-history switch', () {
    /// Two recordings: one whose TITLE matches, one where only the transcript does.
    Future<void> pumpTwo(WidgetTester tester, {required bool on}) => pumpLibrary(
          tester,
          settings: {'workflow.searchableHistory': on},
          rows: [
            recordingRow(
              structured: false,
              transcriptText: 'we argued about pelicans for an hour',
            ).copyWith(id: 'r_2', title: 'Standup notes'),
          ],
        );

    testWidgets('on, the search reaches what was actually said', (tester) async {
      await pumpTwo(tester, on: true);

      await tester.enterText(find.byType(TextField), 'pelicans');
      await tester.pumpAndSettle();

      expect(find.text('Standup notes'), findsOneWidget);
    });

    testWidgets('off, transcripts are not searched', (tester) async {
      await pumpTwo(tester, on: false);

      await tester.enterText(find.byType(TextField), 'pelicans');
      await tester.pumpAndSettle();

      expect(find.text('Standup notes'), findsNothing,
          reason: 'the switch used to gate nothing at all — every word anyone '
              'had said stayed searchable with it turned off');
    });

    testWidgets('off, titles are still searchable', (tester) async {
      await pumpTwo(tester, on: false);

      await tester.enterText(find.byType(TextField), 'Standup');
      await tester.pumpAndSettle();

      expect(find.text('Standup notes'), findsOneWidget,
          reason: 'it narrows the search, it does not disable it');
    });
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

  testWidgets(
      'searching the home screen finds a Codex note alongside recordings',
      (tester) async {
    await pumpLibrary(
      tester,
      rows: [recordingRow()],
      codexNotes: [
        codexNoteRow(body: 'The bridge toll was ambushed at dusk.'),
      ],
    );

    // Unfiltered: the Codex only surfaces once there is something to search for.
    expect(find.text('The bridge toll was ambushed at dusk.'), findsNothing);

    await tester.enterText(find.byType(TextField), 'ambushed');
    await tester.pumpAndSettle();

    expect(find.text('The bridge toll was ambushed at dusk.'), findsOneWidget);
    expect(find.text('Codex · 1'), findsOneWidget);
    expect(find.text('Auth migration kickoff'), findsNothing,
        reason: 'the recording does not mention an ambush');
  });

  testWidgets('a Codex result can be edited from the search list',
      (tester) async {
    await pumpLibrary(
      tester,
      rows: [recordingRow()],
      codexNotes: [codexNoteRow(body: 'Original wording.')],
    );

    await tester.enterText(find.byType(TextField), 'Original');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Original wording.'));
    await tester.pumpAndSettle();

    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, 'Edited wording.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The old wording dropping out of a search still scoped to "Original" is what
    // proves the edit actually persisted, rather than just echoing back what was typed.
    expect(find.text('Original wording.'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Edited');
    await tester.pumpAndSettle();
    expect(find.text('Edited wording.'), findsOneWidget);
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

  group('narrowing the library by tag and folder', () {
    testWidgets('the filter row is absent until there is something in it',
        (tester) async {
      await pumpLibrary(tester);

      expect(find.text('Every folder'), findsNothing,
          reason: 'a permanently empty control row is the kind of thing people '
              'learn to ignore before it ever fills up');
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('a tag appears as a chip with its count', (tester) async {
      await pumpLibrary(tester, rows: [
        recordingRow(),
        recordingRow().copyWith(id: 'r_2', title: 'Standup notes'),
      ]);
      repo.seedTag('work', on: ['r_1', 'r_2']);
      await tester.pumpAndSettle();

      expect(find.text('work · 2'), findsOneWidget);
    });

    testWidgets('selecting a tag hides the recordings without it',
        (tester) async {
      await pumpLibrary(tester, rows: [
        recordingRow(),
        recordingRow().copyWith(id: 'r_2', title: 'Standup notes'),
      ]);
      repo.seedTag('work', on: ['r_1']);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      expect(find.text('Auth migration kickoff'), findsOneWidget);
      expect(find.text('Standup notes'), findsNothing);
    });

    testWidgets('two tags selected means both, not either', (tester) async {
      await pumpLibrary(tester, rows: [
        recordingRow(),
        recordingRow().copyWith(id: 'r_2', title: 'Standup notes'),
      ]);
      repo.seedTag('work', on: ['r_1', 'r_2']);
      repo.seedTag('hiring', on: ['r_1']);
      await tester.pumpAndSettle();

      await tester.tap(find.text('hiring · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('work · 2'));
      await tester.pumpAndSettle();

      expect(find.text('Auth migration kickoff'), findsOneWidget);
      expect(find.text('Standup notes'), findsNothing,
          reason: '"the standups that are also about hiring" is the question '
              'worth asking; "either" is just a longer list');
    });

    testWidgets('Clear puts everything back', (tester) async {
      await pumpLibrary(tester, rows: [
        recordingRow(),
        recordingRow().copyWith(id: 'r_2', title: 'Standup notes'),
      ]);
      repo.seedTag('work', on: ['r_1']);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Standup notes'), findsOneWidget);
    });

    testWidgets('a folder and its tags show on the tile', (tester) async {
      await pumpLibrary(tester, rows: [
        recordingRow(folder: 'Work/Standups'),
      ]);
      repo.seedTag('weekly', on: ['r_1']);
      await tester.pumpAndSettle();

      expect(find.text('Work/Standups'), findsWidgets);
      expect(find.text('weekly'), findsWidgets,
          reason: 'a label set in a sheet and never shown again is a filing '
              'system nobody trusts');
    });

    testWidgets('narrowing by tag still composes with the search box',
        (tester) async {
      // structured: false so the rows carry no note text — the shared note fixture
      // mentions auth, which would make every row match the search.
      await pumpLibrary(tester, rows: [
        recordingRow(structured: false).copyWith(id: 'r_1', title: 'Auth kickoff'),
        recordingRow(structured: false).copyWith(id: 'r_2', title: 'Auth retro'),
        recordingRow(structured: false).copyWith(id: 'r_3', title: 'Hiring sync'),
      ]);
      repo.seedTag('work', on: ['r_1', 'r_3']);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Auth');
      await tester.pumpAndSettle();

      expect(find.text('Auth kickoff'), findsOneWidget);
      expect(find.text('Hiring sync'), findsNothing, reason: 'tagged, wrong word');
      expect(find.text('Auth retro'), findsNothing, reason: 'right word, untagged');
    });
  });
}
