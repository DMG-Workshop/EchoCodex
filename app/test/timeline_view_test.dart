import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echo_codex_app/src/recording/recording_controller.dart';
import 'package:echo_codex_app/src/screens/export_sheet.dart';
import 'package:echo_codex_app/src/screens/note_screen.dart';
import 'package:echo_codex_app/src/settings/provider_config.dart';
import 'package:transcript_core/transcript_core.dart';

import 'fixtures.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1400, 1400);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  late FakeRecordingRepository repo;

  Future<void> pumpNote(WidgetTester tester,
      {Map<String, dynamic>? note}) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final row = recordingRow(
      overrideNote: note == null ? null : jsonEncode(note),
    );
    repo = FakeRecordingRepository([row]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
          repositoryProvider.overrideWithValue(repo),
          recordingsProvider.overrideWith((ref) => Stream.value([row])),
        ],
        child: const MaterialApp(home: NoteScreen(recordingId: 'r_1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpTimeline(WidgetTester tester,
      {Map<String, dynamic>? note}) async {
    await pumpNote(tester, note: note);
    await tester.tap(find.text('Gantt'));
    await tester.pumpAndSettle();
  }

  /// Puts one item on the chart through the form, exactly as a user would.
  Future<void> addThroughForm(
    WidgetTester tester, {
    required String title,
    bool milestone = false,
  }) async {
    await tester.enterText(
        find.widgetWithText(TextField, 'What goes on the chart'), title);
    await tester.pumpAndSettle();
    if (milestone) {
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Add to chart'));
    await tester.pumpAndSettle();
  }

  testWidgets('the chart starts empty even when the recording dated the work',
      (tester) async {
    await pumpTimeline(tester);

    expect(find.text('Nothing on the chart yet'), findsOneWidget);
    expect(find.textContaining('built by hand'), findsOneWidget);
    expect(repo.ganttFor('r_1'), isEmpty,
        reason: 'a date the model found is a suggestion, not a commitment');
  });

  testWidgets('the tray offers every task, dated or not, exactly once',
      (tester) async {
    await pumpTimeline(tester);

    expect(find.text('Not on the chart yet'), findsOneWidget);
    expect(find.textContaining('no dates have been guessed'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Update the runbook'), findsOneWidget,
        reason: 'the undated task is offered, never placed');
    expect(
      find.widgetWithText(
          ActionChip, 'Migrate the auth service off the legacy session store'),
      findsOneWidget,
      reason: 'the dated one is offered too — nothing is placed for the user',
    );
  });

  testWidgets('adding an item through the form puts it on the chart',
      (tester) async {
    await pumpTimeline(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add an item'));
    await tester.pumpAndSettle();
    expect(find.text('Add to Gantt'), findsOneWidget);

    await addThroughForm(tester, title: 'Cut the release branch');

    expect(find.text('Nothing on the chart yet'), findsNothing);
    expect(find.text('Cut the release branch'), findsOneWidget,
        reason: 'a bar with no visible name is not worth drawing');
    expect(repo.ganttFor('r_1').single.title, 'Cut the release branch');
  });

  testWidgets('the form asks for the fields a Gantt bar actually needs',
      (tester) async {
    await pumpTimeline(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add an item'));
    await tester.pumpAndSettle();

    for (final label in ['START', 'FINISH', 'OWNER', 'WORKSTREAM']) {
      expect(find.text(label), findsOneWidget, reason: '$label was not asked for');
    }
    expect(find.text('Milestone'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget, reason: 'percent complete');
    expect(find.textContaining('1 day'), findsOneWidget,
        reason: 'duration is shown, derived from the dates rather than typed twice');
  });

  testWidgets('a task already on the chart stops being offered again',
      (tester) async {
    await pumpTimeline(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Update the runbook'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add to chart'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ActionChip, 'Update the runbook'), findsNothing,
        reason: 'offering it twice invites two bars for one piece of work');
  });

  testWidgets('a dated task arrives prefilled rather than as an empty form',
      (tester) async {
    await pumpTimeline(tester);

    await tester.tap(find.widgetWithText(
        ActionChip, 'Migrate the auth service off the legacy session store'));
    await tester.pumpAndSettle();

    final title = tester.widget<TextField>(
        find.widgetWithText(TextField, 'What goes on the chart'));
    expect(title.controller?.text,
        'Migrate the auth service off the legacy session store');
    expect(find.text('Sep 18, 2026'), findsWidgets,
        reason: 'what the recording established is carried, not discarded');
  });

  testWidgets('a date the model worked out stays marked as worked out',
      (tester) async {
    final note = noteJson();
    final task = (note['tasks'] as List<dynamic>).first as Map<String, dynamic>;
    task['dateBasis'] = 'inferred';
    task['dueDate'] = '2026-09-30';

    await pumpTimeline(tester, note: note);
    await tester.tap(find.widgetWithText(
        ActionChip, 'Migrate the auth service off the legacy session store'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not stated outright'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add to chart'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 inferred'), findsOneWidget,
        reason: 'accepting a prefilled form does not turn a guess into a fact');
  });

  testWidgets('a finish before its start cannot be saved', (tester) async {
    await pumpTimeline(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add an item'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'What goes on the chart'), 'Backwards');
    await tester.pumpAndSettle();

    // Move the finish a month earlier than the start, through the picker.
    await tester.tap(find.byType(OutlinedButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('finish is before the start'), findsOneWidget);
    final save = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add to chart'));
    expect(save.onPressed, isNull, reason: 'nothing can be drawn from that');
  });

  testWidgets('a milestone is a marker, not a bar', (tester) async {
    await pumpTimeline(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add an item'));
    await tester.pumpAndSettle();
    await addThroughForm(tester, title: 'Launch', milestone: true);

    final entry = repo.ganttFor('r_1').single;
    expect(entry.milestone, isTrue);
    expect(entry.startDate, entry.endDate,
        reason: 'a milestone has zero duration by convention');
    expect(find.widgetWithText(ActionChip, 'Launch'), findsOneWidget);
  });

  testWidgets('an item on the chart can be edited and taken off again',
      (tester) async {
    await pumpTimeline(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add an item'));
    await tester.pumpAndSettle();
    await addThroughForm(tester, title: 'Cut the release branch');

    await tester.tap(find.text('Cut the release branch'));
    await tester.pumpAndSettle();
    expect(find.text('Edit chart item'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from chart'));
    await tester.pumpAndSettle();

    expect(repo.ganttFor('r_1'), isEmpty);
    expect(find.text('Nothing on the chart yet'), findsOneWidget);
  });

  testWidgets('the scale can be switched between day, week and month',
      (tester) async {
    await pumpTimeline(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add an item'));
    await tester.pumpAndSettle();
    await addThroughForm(tester, title: 'Cut the release branch');

    for (final label in ['Day', 'Week', 'Month']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a note with nothing in it shows an empty chart, not a broken one',
      (tester) async {
    final note = noteJson();
    note['tasks'] = <Object>[];
    note['timelineAnchors'] = <Object>[];

    await pumpTimeline(tester, note: note);

    expect(find.text('Nothing on the chart yet'), findsOneWidget);
    expect(find.text('Not on the chart yet'), findsNothing,
        reason: 'an empty tray is a tray worth hiding');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the add-to-Gantt button sits beside the Codex one on the notes',
      (tester) async {
    await pumpNote(tester);

    expect(find.byTooltip('Save to Codex'), findsWidgets);
    expect(find.byTooltip('Add to Gantt'), findsWidgets,
        reason: 'the two ways of keeping a line belong next to each other');

    await tester.tap(find.byTooltip('Add to Gantt').first);
    await tester.pumpAndSettle();

    final title = tester.widget<TextField>(
        find.widgetWithText(TextField, 'What goes on the chart'));
    expect(title.controller?.text, isNotEmpty,
        reason: 'the line that was tapped starts the form off');
  });

  testWidgets('the export sheet offers every format and flags inferred dates',
      (tester) async {
    final note = noteJson();
    final task = (note['tasks'] as List<dynamic>).first as Map<String, dynamic>;
    task['dateBasis'] = 'inferred';
    task['dueDate'] = '2026-09-30';

    await pumpTimeline(tester, note: note);

    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();

    expect(find.text('Markdown'), findsOneWidget);
    expect(find.text('Spreadsheet (CSV)'), findsOneWidget);
    expect(find.text('Jira CSV'), findsOneWidget);
    expect(find.text('Add to phone calendar (.ics)'), findsOneWidget);
    expect(find.textContaining('was inferred from the recording'), findsOneWidget,
        reason: 'the warning has to survive the trip out of the app');
  });

  test('every export format renders without throwing', () {
    final note = NoteDocument.fromJson(noteJson());
    for (final format in ExportFormat.values) {
      final rendered = format.render(note, recordedOn: '5 Sep 2026');
      expect(rendered, isNotEmpty, reason: '${format.label} produced nothing');
    }
  });
}
