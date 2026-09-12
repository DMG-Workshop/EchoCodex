import '../models/note_document.dart';

/// How much calendar the timeline shows at once.
enum TimelineScale {
  day(daysPerColumn: 1, label: 'Day'),
  week(daysPerColumn: 7, label: 'Week'),
  month(daysPerColumn: 30, label: 'Month');

  const TimelineScale({required this.daysPerColumn, required this.label});

  final int daysPerColumn;
  final String label;
}

/// One entry someone has deliberately placed on the chart.
///
/// The chart is built, never derived. Nothing appears on it because a model found a
/// date somewhere in the recording — only because a person decided this piece of work
/// belongs on a plan and said when it runs. That decision is the whole content of this
/// type, which is why it holds dates as [DateTime] rather than the note's nullable ISO
/// strings: an item that cannot say when it happens cannot be one.
///
/// [basis] still travels with it. A date the user typed is [DateBasis.explicit] and a
/// date carried over unedited from a model's guess is [DateBasis.inferred], because
/// accepting a form does not turn a guess into something that was said out loud.
class GanttItem {
  const GanttItem({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.basis = DateBasis.explicit,
    this.owner,
    this.workstream,
    this.percentComplete = 0,
    this.isMilestone = false,
    this.dependsOn = const [],
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final DateBasis basis;

  /// Who is doing it — a [Participant.id] where one resolves, otherwise the name as
  /// the user typed it. The chart only ever shows it, so it needs no other structure.
  final String? owner;

  /// The phase, workstream or epic this belongs to: the grouping column every Gantt
  /// has and no two teams name the same way.
  final String? workstream;

  /// 0–100. Progress is reported, never computed from the calendar — a bar whose dates
  /// have passed is late, not finished.
  final int percentComplete;

  /// A dateless event: a launch, a gate, a hand-off. Drawn as a marker on [start]
  /// rather than a bar, per the convention that a milestone has zero duration.
  final bool isMilestone;

  /// Ids of other items that must finish first. Finish-to-start, the only dependency
  /// this chart draws, because it is the only one it can draw unambiguously.
  final List<String> dependsOn;

  /// Inclusive, so a one-day item is one day long rather than zero.
  int get durationDays => end.difference(start).inDays + 1;
}

/// One task placed on the timeline.
class TimelineBar {
  const TimelineBar({
    required this.taskId,
    required this.title,
    required this.start,
    required this.end,
    required this.basis,
    required this.row,
    this.assigneeId,
    this.epic,
    this.percentComplete = 0,
  });

  final String taskId;
  final String title;
  final DateTime start;
  final DateTime end;

  /// Drives how the bar is drawn, and it is never inferred from the dates alone: a date
  /// the model derived and a date someone spoke look identical as values, and the whole
  /// point of the timeline is that they must not look identical on screen.
  final DateBasis basis;

  final int row;
  final String? assigneeId;
  final String? epic;

  /// 0–100, as reported by whoever owns the work.
  final int percentComplete;

  int get durationDays => end.difference(start).inDays + 1;
}

/// A fixed date that is not itself a task — a launch, a sprint boundary, a deadline.
class TimelineMilestone {
  const TimelineMilestone({required this.label, required this.date, this.id});
  final String label;
  final DateTime date;

  /// The [GanttItem.id] this came from, when it came from one. Null for a milestone
  /// read straight out of a note's anchors, which have no identity to carry.
  final String? id;
}

/// A stated dependency, drawn as an arrow between two bars.
class TimelineLink {
  const TimelineLink({required this.fromTaskId, required this.toTaskId});
  final String fromTaskId;
  final String toTaskId;
}

/// Everything the painter needs, computed without touching a canvas.
class TimelineLayout {
  const TimelineLayout({
    required this.bars,
    required this.milestones,
    required this.links,
    required this.rangeStart,
    required this.rangeEnd,
    required this.undated,
  });

  final List<TimelineBar> bars;
  final List<TimelineMilestone> milestones;
  final List<TimelineLink> links;

  /// The window the chart covers, padded so nothing sits flush against an edge.
  final DateTime rangeStart;
  final DateTime rangeEnd;

  /// Tasks nobody dated. They are listed beside the chart for the user to place, never
  /// given a guessed position on it.
  final List<NoteTask> undated;

  bool get isEmpty => bars.isEmpty && milestones.isEmpty;

  int get totalDays => rangeEnd.difference(rangeStart).inDays + 1;

  int get rowCount => bars.isEmpty
      ? 0
      : bars.map((b) => b.row).reduce((a, b) => a > b ? a : b) + 1;

  /// Horizontal position of [date] as a fraction of the visible range.
  double fractionFor(DateTime date) {
    if (totalDays <= 1) return 0;
    final offset = date.difference(rangeStart).inDays;
    return (offset / (totalDays - 1)).clamp(0.0, 1.0);
  }

  /// How many bars carry a date the model derived rather than heard. Surfaced so the
  /// chart can say so rather than letting the reader assume everything was spoken.
  int get inferredCount =>
      bars.where((b) => b.basis == DateBasis.inferred).length;
}

/// Turns items — or a whole note — into a timeline.
///
/// Pure and synchronous: every decision about what appears where — and what deliberately
/// does not appear — is testable without a canvas.
class TimelinePlanner {
  const TimelinePlanner({this.padDays = 2, this.defaultDurationDays = 1});

  /// Breathing room at each end so a bar never sits flush against the edge.
  final int padDays;

  /// A task with a due date but no start is drawn as a marker on its due date rather
  /// than a bar of invented length.
  final int defaultDurationDays;

  /// Lays out items the user put on the chart.
  ///
  /// [undated] is passed through untouched for the tray beside the chart: work that is
  /// not on the plan is the caller's to decide, because only the caller knows what the
  /// user has already placed.
  TimelineLayout planItems(
    List<GanttItem> items, {
    List<NoteTask> undated = const [],
    DateTime? today,
  }) {
    final dates = <DateTime>[];

    final milestones = <TimelineMilestone>[];
    for (final item in items.where((i) => i.isMilestone)) {
      milestones.add(TimelineMilestone(
        id: item.id,
        label: item.title,
        date: item.start,
      ));
      dates.add(item.start);
    }

    // Rows are assigned after filtering, never from the caller's index: a gap in the
    // rows is a blank stripe on the chart and an off-by-one between the painter's
    // height and the label column beside it.
    final placeable = items.where((i) => !i.isMilestone).toList()
      ..sort(_byStartThenTitle);

    final bars = <TimelineBar>[];
    for (var row = 0; row < placeable.length; row++) {
      final item = placeable[row];
      // A finish before its start is a slip in whatever produced it, not a bar of
      // negative length.
      final from = item.start.isAfter(item.end) ? item.end : item.start;
      final to = item.end;
      bars.add(TimelineBar(
        taskId: item.id,
        title: item.title,
        start: from,
        end: to,
        basis: item.basis,
        row: row,
        assigneeId: item.owner,
        epic: item.workstream,
        percentComplete: item.percentComplete.clamp(0, 100),
      ));
      dates
        ..add(from)
        ..add(to);
    }

    // Only dependencies between two items both on the chart: an arrow to something
    // invisible is worse than no arrow.
    final placed = {for (final bar in bars) bar.taskId};
    final links = <TimelineLink>[
      for (final item in placeable)
        if (placed.contains(item.id))
          for (final dependency in item.dependsOn)
            if (placed.contains(dependency) && dependency != item.id)
              TimelineLink(fromTaskId: dependency, toTaskId: item.id),
    ];

    final anchorDate = today ?? DateTime.now();
    final earliest = dates.isEmpty
        ? _atMidnight(anchorDate)
        : dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final latest = dates.isEmpty
        ? _atMidnight(anchorDate)
        : dates.reduce((a, b) => a.isAfter(b) ? a : b);

    return TimelineLayout(
      bars: bars,
      milestones: milestones,
      links: links,
      rangeStart: earliest.subtract(Duration(days: padDays)),
      rangeEnd: latest.add(Duration(days: padDays)),
      undated: undated,
    );
  }

  /// Lays out everything a note dates by itself.
  ///
  /// This is the chart a recording implies, not the chart the user has built — see
  /// [planItems] for that one. Kept because "what did this recording actually commit
  /// to" is a question worth being able to answer without a UI.
  TimelineLayout plan(NoteDocument note, {DateTime? today}) {
    final items = <GanttItem>[];

    // Only tasks the note actually dates. Placing an undated task would be inventing
    // the one thing this whole design refuses to invent.
    for (final task in note.tasks.where((t) => t.isSchedulable)) {
      final item = itemFromTask(task);
      if (item != null) items.add(item);
    }

    for (var i = 0; i < note.timelineAnchors.length; i++) {
      final anchor = note.timelineAnchors[i];
      final date = _parse(anchor.date);
      if (date == null) continue;
      items.add(GanttItem(
        id: 'anchor_$i',
        title: anchor.label,
        start: date,
        end: date,
        isMilestone: true,
      ));
    }

    return planItems(items, undated: note.needsDates, today: today);
  }

  /// A task's own dates as a chart item, or null when it has none this chart can use.
  ///
  /// Also the form's starting point: the user opens "add to the chart" on a task and
  /// finds whatever the recording already established filled in, rather than an empty
  /// form beside a note that plainly contains the answer.
  GanttItem? itemFromTask(NoteTask task) {
    final due = _parse(task.dueDate);
    if (due == null) return null;

    final start = _parse(task.startDate) ?? due;
    final from = start.isAfter(due) ? due : start;
    final to =
        from == due ? due.add(Duration(days: defaultDurationDays - 1)) : due;

    return GanttItem(
      id: task.id,
      title: task.title,
      start: from,
      end: to,
      basis: task.dateBasis,
      owner: task.assigneeId,
      workstream: task.epic,
      dependsOn: task.dependsOn,
    );
  }

  static int _byStartThenTitle(GanttItem a, GanttItem b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.title.compareTo(b.title);
  }

  static DateTime? _parse(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? null : _atMidnight(parsed);
  }

  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);
}
