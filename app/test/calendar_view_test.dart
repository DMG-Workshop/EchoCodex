import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/recording/recording_controller.dart';
import 'package:echo_codex_app/src/screens/note_screen.dart';

import 'fixtures.dart';

void main() {
  Future<void> pumpCalendar(WidgetTester tester, {Map<String, dynamic>? note}) async {
    final row = recordingRow(
      overrideNote: note == null ? null : jsonEncode(note),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordingsProvider.overrideWith((ref) => Stream.value([row])),
        ],
        child: const MaterialApp(home: NoteScreen(recordingId: 'r_1')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
  }

  testWidgets('calendar shows dated tasks and month navigation', (tester) async {
    await pumpCalendar(tester);

    expect(find.text('Migrate the auth service off the legacy session store'),
        findsWidgets);
    expect(find.byTooltip('Previous month'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsOneWidget);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar marks inferred tasks', (tester) async {
    final note = noteJson();
    final task = (note['tasks'] as List<dynamic>).first as Map<String, dynamic>;
    task['dateBasis'] = 'inferred';
    task['dueDate'] = '2026-09-30';

    await pumpCalendar(tester, note: note);
    expect(find.textContaining('inferred'), findsOneWidget);
  });
}
