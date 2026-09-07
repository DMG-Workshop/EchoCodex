import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transcript_app/src/recording/recording_controller.dart';
import 'package:transcript_app/src/screens/library_screen.dart';

import 'fixtures.dart';

void main() {
  late FakeRecordingRepository repo;

  Future<void> pumpLibrary(WidgetTester tester) async {
    repo = FakeRecordingRepository([recordingRow()]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

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
