import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/data/database.dart' as db;
import 'package:echo_codex_app/src/recording/recording_controller.dart';
import 'package:echo_codex_app/src/screens/note_screen.dart';
import 'package:echo_codex_app/src/settings/provider_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  /// The note screen reads settings: which tabs it shows depends on the workflow
  /// feature switches, so every pump needs a store behind it.
  Future<List<Override>> baseOverrides() async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    return [settingsStoreProvider.overrideWithValue(SettingsStore(prefs))];
  }

  late FakeRecordingRepository noteRepo;

  /// Every recording the fake should know about. The screen reads the repository
  /// directly now — naming a speaker offers names used in OTHER recordings — so a
  /// real drift database behind these tests would be both slow and shared state.
  Future<void> pumpNote(
    WidgetTester tester,
    db.Recording recording, {
    List<db.Recording> alsoKnown = const [],
  }) async {
    noteRepo = FakeRecordingRepository([recording, ...alsoKnown]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await baseOverrides(),
          repositoryProvider.overrideWithValue(noteRepo),
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

  testWidgets('unclear audio is flagged rather than presented as clean',
      (tester) async {
    final note = noteJson();
    (note['meta'] as Map<String, dynamic>)['extractionConfidence'] = 'low';

    await pumpNote(tester, recordingRow(overrideNote: jsonEncode(note)));
    expect(find.textContaining('hard to make out'), findsOneWidget);
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

  testWidgets('speaker labels are shown and can be renamed', (tester) async {
    final segments = jsonEncode([
      {
        'startMs': 0,
        'endMs': 1000,
        'text': 'Hello there',
        'speaker': 'SPEAKER_00',
      },
      {
        'startMs': 1000,
        'endMs': 2000,
        'text': 'Hi',
        'speaker': 'SPEAKER_01',
      },
    ]);
    await pumpNote(
      tester,
      recordingRow(
        transcriptText: 'Hello there Hi',
        transcriptSegmentsJson: segments,
      ),
    );
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    expect(find.textContaining('SPEAKER_00'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit speaker names'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Alice');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alice: Hello there'), findsOneWidget);
  });

  group('naming the same person across recordings', () {
    String segmentsFor(List<String> speakers) => jsonEncode([
          for (var i = 0; i < speakers.length; i++)
            {
              'startMs': i * 1000,
              'endMs': (i + 1) * 1000,
              'text': 'line $i',
              'speaker': speakers[i],
            },
        ]);

    /// An earlier recording where the user already named two voices. Note the
    /// labels differ from the current recording's — that is the whole problem.
    db.Recording earlierNamed() => recordingRow(
          transcriptText: 'older meeting',
          transcriptSegmentsJson: segmentsFor(['SPEAKER_04', 'SPEAKER_05']),
        ).copyWith(
          id: 'r_old',
          title: 'Last week',
          startedAt: DateTime(2026, 9, 1),
          speakerNamesJson: drift.Value(jsonEncode(
              {'SPEAKER_04': 'Sarah Chen', 'SPEAKER_05': 'Marcus'})),
        );

    Future<void> openNaming(WidgetTester tester,
        {List<db.Recording> alsoKnown = const []}) async {
      await pumpNote(
        tester,
        recordingRow(
          transcriptText: 'Hello there Hi',
          transcriptSegmentsJson: segmentsFor(['SPEAKER_00', 'SPEAKER_01']),
        ),
        alsoKnown: alsoKnown,
      );
      await tester.tap(find.text('Transcript'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit speaker names'));
      await tester.pumpAndSettle();
    }

    testWidgets('names used before are offered', (tester) async {
      await openNaming(tester, alsoKnown: [earlierNamed()]);

      expect(find.widgetWithText(ActionChip, 'Sarah Chen'), findsWidgets,
          reason: 'the same colleague is SPEAKER_04 one week and SPEAKER_00 '
              'the next, so naming starts from nothing every time');
      expect(find.widgetWithText(ActionChip, 'Marcus'), findsWidgets);
    });

    testWidgets('tapping one fills that voice in', (tester) async {
      await openNaming(tester, alsoKnown: [earlierNamed()]);

      await tester.tap(find.widgetWithText(ActionChip, 'Sarah Chen').first);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, 'Sarah Chen');
    });

    testWidgets('a name taken by one voice is not offered for the other',
        (tester) async {
      await openNaming(tester, alsoKnown: [earlierNamed()]);

      await tester.tap(find.widgetWithText(ActionChip, 'Sarah Chen').first);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActionChip, 'Sarah Chen'), findsNothing,
          reason: 'one person cannot be two of the speakers in one conversation');
      expect(find.widgetWithText(ActionChip, 'Marcus'), findsWidgets,
          reason: 'the others are still on offer');
    });

    testWidgets('nothing is matched to a voice automatically', (tester) async {
      await openNaming(tester, alsoKnown: [earlierNamed()]);

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, 'SPEAKER_00',
          reason: 'the app has no idea whether this is the same person as last '
              'week, and guessing would attribute decisions to people who never '
              'made them');
    });

    testWidgets('a raw label left in place is not offered as a name later',
        (tester) async {
      final neverNamed = recordingRow(
        transcriptText: 'older',
        transcriptSegmentsJson: segmentsFor(['SPEAKER_09']),
      ).copyWith(
        id: 'r_raw',
        startedAt: DateTime(2026, 8, 1),
        // Saved without editing: the label is its own "name".
        speakerNamesJson:
            drift.Value(jsonEncode({'SPEAKER_09': 'SPEAKER_09'})),
      );

      await openNaming(tester, alsoKnown: [neverNamed]);

      expect(find.widgetWithText(ActionChip, 'SPEAKER_09'), findsNothing,
          reason: 'a value still equal to its provider label is not a name');
    });

    testWidgets('with no history there are no suggestions', (tester) async {
      await openNaming(tester);

      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('Name speakers'), findsOneWidget,
          reason: 'the dialog still opens and still works by typing');
    });
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
          ...await baseOverrides(),
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
          overrides: [
            ...await baseOverrides(),
            repositoryProvider.overrideWithValue(repo),
          ],
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
