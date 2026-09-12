import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transcript_core/transcript_core.dart';

import '../data/database.dart' as db;
import '../recording/recording_controller.dart';

/// What one recording's chart currently holds.
///
/// A stream rather than a snapshot: the form writes straight to storage and the chart
/// redraws from the row, so there is never a moment where the chart on screen and the
/// plan on disk disagree.
final ganttEntriesProvider =
    StreamProvider.family<List<db.GanttEntry>, String>(
  (ref, recordingId) =>
      ref.watch(repositoryProvider).watchGanttEntries(recordingId),
);

/// Turns a stored row into something the planner can lay out.
GanttItem ganttItemOf(db.GanttEntry entry) => GanttItem(
      id: entry.id,
      title: entry.title,
      start: entry.startDate,
      end: entry.endDate,
      basis: DateBasis.values
          .where((b) => b.name == entry.dateBasis)
          .firstOrNull ??
          DateBasis.explicit,
      owner: entry.owner,
      workstream: entry.workstream,
      percentComplete: entry.percentComplete,
      isMilestone: entry.milestone,
      dependsOn: dependenciesOf(entry),
    );

/// The ids this entry waits on. Stored as JSON, so a row written by an older build — or
/// corrupted by a failed migration — degrades to "no dependencies" rather than taking
/// the whole chart down with it.
List<String> dependenciesOf(db.GanttEntry entry) {
  final raw = entry.dependsOnJson;
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final id in decoded)
        if (id is String && id.isNotEmpty) id,
    ];
  } on FormatException {
    return const [];
  }
}

/// The note's own tasks that are not on the chart yet.
///
/// This is the list the user checks off: everything the recording produced, dated or
/// not, offered once each. A task already placed drops out of it, so the tray shrinks
/// as the plan fills in rather than inviting the same item onto the chart twice.
List<NoteTask> tasksNotOnChart(NoteDocument note, List<db.GanttEntry> entries) {
  final placed = {
    for (final entry in entries)
      if (entry.sourceTaskId != null) entry.sourceTaskId!,
  };
  return [
    for (final task in note.tasks)
      if (!placed.contains(task.id)) task,
  ];
}
