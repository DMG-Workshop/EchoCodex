import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transcript_app/src/data/database.dart' as db;
import 'package:transcript_app/src/recording/recording_controller.dart';
import 'package:transcript_app/src/screens/note_screen.dart';

import 'fixtures.dart';

void main() {
  Future<void> pumpNote(WidgetTester tester, db.Recording recording) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordingsProvider.overrideWith((ref) => Stream.value([recording])),
        ],
        child: const MaterialApp(home: NoteScreen(recordingId: 'r_1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the summary and bullets', (tester) async {
    await pumpNote(tester, recordingRow());

    expect(find.text('Auth migration kickoff'), findsWidgets);
    expect(
      find.text('The team agreed to retire the legacy session store before launch.'),
      findsOneWidget,
    );
    expect(find.text('Priya owns the migration.'), findsOneWidget);
  });

  testWidgets('shows a decision with the words it came from', (tester) async {
    await pumpNote(tester, recordingRow());

    expect(find.text('Retire the legacy session store before launch.'), findsOneWidget);
    expect(find.text('“we are retiring it before launch, agreed”'), findsOneWidget,
        reason: 'provenance is shown, not hidden behind a tap');
  });

  testWidgets('a spoken date and an undated task are rendered differently',
      (tester) async {
    await pumpNote(tester, recordingRow());
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();

    expect(find.text('2026-09-18'), findsOneWidget);
    expect(find.text('no date discussed'), findsOneWidget,
        reason: 'an undated task says so rather than showing a guessed date');
    expect(find.textContaining('need dates'), findsOneWidget,
        reason: 'the board counts what still needs dating');
  });

  testWidgets('an inferred date is labelled as inferred', (tester) async {
    final note = noteJson();
    final task = (note['tasks'] as List<dynamic>).first as Map<String, dynamic>;
    task['dateBasis'] = 'inferred';
    task['dueDate'] = '2026-09-30';

    await pumpNote(tester, recordingRow(overrideNote: jsonEncode(note)));
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();

    expect(find.text('2026-09-30 · inferred'), findsOneWidget,
        reason: 'a derived date must never look like one that was spoken');
  });

  testWidgets('the owner is shown when someone took the work', (tester) async {
    await pumpNote(tester, recordingRow());
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();

    // Once on the card, once as a filter chip.
    expect(find.text('Priya'), findsWidgets);
  });

  testWidgets('unclear audio is flagged rather than presented as clean',
      (tester) async {
    final note = noteJson();
    (note['meta'] as Map<String, dynamic>)['extractionConfidence'] = 'low';

    await pumpNote(tester, recordingRow(overrideNote: jsonEncode(note)));
    expect(find.textContaining('hard to make out'), findsOneWidget);
  });

  testWidgets('no action items says so plainly, and offers to add one',
      (tester) async {
    final note = noteJson()..['tasks'] = <Object>[];

    await pumpNote(tester, recordingRow(overrideNote: jsonEncode(note)));
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No action items'), findsOneWidget);
    expect(find.text('Add one yourself'), findsOneWidget,
        reason: 'every extraction misses something, so the board must be correctable');
  });

  testWidgets('a recording whose structuring failed still opens', (tester) async {
    await pumpNote(tester, recordingRow(structured: false));

    expect(find.text('No notes for this recording'), findsOneWidget);
    expect(find.textContaining('still saved'), findsOneWidget,
        reason: 'the user must be told the recording survived');
  });

  testWidgets('the transcript tab traces items back to their timestamps',
      (tester) async {
    await pumpNote(tester, recordingRow());
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    expect(find.text('00:12'), findsOneWidget);
    expect(find.text('“we need to get off the legacy session store”'), findsOneWidget);
  });

  testWidgets('a stored transcript is shown directly, cleaned by default',
      (tester) async {
    await pumpNote(
      tester,
      recordingRow(
        transcriptText: 'um so we need to ship it',
        cleanedTranscriptText: 'So we need to ship it.',
      ),
    );
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    expect(find.text('So we need to ship it.'), findsOneWidget);
    expect(find.text('um so we need to ship it'), findsNothing);

    await tester.tap(find.text('Raw'));
    await tester.pumpAndSettle();

    expect(find.text('um so we need to ship it'), findsOneWidget);
    expect(find.text('So we need to ship it.'), findsNothing);
  });

  testWidgets('a raw-only transcript has no cleaned/raw toggle', (tester) async {
    await pumpNote(
      tester,
      recordingRow(transcriptText: 'hello there'),
    );
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    expect(find.text('hello there'), findsOneWidget);
    expect(find.text('Raw'), findsNothing);
  });

  testWidgets('no study aids says so, rather than an empty tab', (tester) async {
    await pumpNote(tester, recordingRow());
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    expect(find.text('No study aids for this recording'), findsOneWidget);
  });

  testWidgets('key concepts, flashcards and a quiz all render', (tester) async {
    final note = noteJson()
      ..['keyConcepts'] = [
        {'term': 'OIDC', 'explanation': 'The protocol the new auth flow uses.'}
      ]
      ..['flashcards'] = [
        {'front': 'What replaces the session store?', 'back': 'OIDC-based auth.'}
      ]
      ..['quiz'] = [
        {
          'question': 'Who owns the migration?',
          'choices': ['Priya', 'Sam'],
          'correctIndex': 0,
          'explanation': 'Priya accepted it in the recording.',
        }
      ];

    await pumpNote(tester, recordingRow(overrideNote: jsonEncode(note)));
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    expect(find.text('OIDC'), findsOneWidget);
    expect(find.text('The protocol the new auth flow uses.'), findsOneWidget);

    expect(find.text('What replaces the session store?'), findsOneWidget);
    expect(find.text('OIDC-based auth.'), findsNothing,
        reason: 'the back of the card is hidden until tapped');
    await tester.tap(find.text('What replaces the session store?'));
    await tester.pumpAndSettle();
    expect(find.text('OIDC-based auth.'), findsOneWidget);

    expect(find.textContaining('Who owns the migration?'), findsOneWidget);
    expect(find.text('Check answer'), findsOneWidget);
  });

  testWidgets('checking a quiz answer reveals correctness and the explanation',
      (tester) async {
    final note = noteJson()
      ..['quiz'] = [
        {
          'question': 'Who owns the migration?',
          'choices': ['Priya', 'Sam'],
          'correctIndex': 0,
          'explanation': 'Priya accepted it in the recording.',
        }
      ];

    await pumpNote(tester, recordingRow(overrideNote: jsonEncode(note)));
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check answer'));
    await tester.pumpAndSettle();

    expect(find.text('Not quite.'), findsOneWidget);
    expect(find.text('Priya accepted it in the recording.'), findsOneWidget);
  });

  testWidgets('shows which services made the note and what it cost', (tester) async {
    await pumpNote(tester, recordingRow());
    await tester.dragUntilVisible(
      find.textContaining('Transcribed by'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('on-device'), findsOneWidget);
    expect(find.textContaining('1.8k in'), findsOneWidget,
        reason: 'users spending their own API credit are owed the measured tokens');
    expect(find.textContaining('≈\$'), findsOneWidget,
        reason: 'a known model gets a price, marked approximate');
  });

  testWidgets('a recording that no longer exists does not crash', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordingsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: NoteScreen(recordingId: 'r_gone')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('no longer here'), findsOneWidget);
  });

  group('deleting from the detail screen', () {
    late FakeRecordingRepository repo;

    Future<void> pumpFromLibrary(WidgetTester tester) async {
      repo = FakeRecordingRepository([recordingRow()]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Recordings')),
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NoteScreen(recordingId: 'r_1'),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, and declining leaves the recording alone',
        (tester) async {
      await pumpFromLibrary(tester);

      await tester.tap(find.byTooltip('Delete recording'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this recording?'), findsOneWidget);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsNothing,
          reason: 'declining stays on the recording, not back at the library');
      expect(repo.deletedIds, isEmpty);
    });

    testWidgets('confirming deletes it, leaves the screen, and reports it',
        (tester) async {
      await pumpFromLibrary(tester);

      await tester.tap(find.byTooltip('Delete recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Recordings'), findsOneWidget,
          reason: 'a deleted recording has nothing left to show');
      expect(find.text('Recording deleted'), findsOneWidget);
      expect(repo.deletedIds, ['r_1']);
    });
  });
}
