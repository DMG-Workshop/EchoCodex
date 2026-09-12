import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

import 'fixtures.dart';

void main() {
  Map<String, dynamic> task(
    String id, {
    String? start,
    String? due,
    String basis = 'explicit',
    List<String> dependsOn = const [],
    String? epic,
  }) =>
      {
        'id': id,
        'title': 'Task $id',
        'detail': null,
        'assigneeId': null,
        'assigneeRaw': null,
        'status': 'todo',
        'priority': 'medium',
        'estimate': null,
        'startDate': start,
        'dueDate': due,
        'dateBasis': basis,
        'dependsOn': dependsOn,
        'epic': epic,
        'sourceRef': {
          'startMs': 0,
          'endMs': 1,
          'quote': 'a quote from the meeting'
        },
      };

  Map<String, dynamic> anchor(String label, String date) => {
        'label': label,
        'date': date,
        'sourceRef': {
          'startMs': 0,
          'endMs': 1,
          'quote': 'a quote from the meeting'
        },
      };

  NoteDocument docWith({
    List<Map<String, dynamic>> tasks = const [],
    List<Map<String, dynamic>> anchors = const [],
  }) =>
      NoteDocument.fromJson(validNoteJson()
        ..['tasks'] = tasks
        ..['timelineAnchors'] = anchors);

  const planner = TimelinePlanner();

  group('what gets placed', () {
    test('a task with a spoken due date becomes a bar', () {
      final layout = planner.plan(docWith(tasks: [
        task('a', start: '2026-09-10', due: '2026-09-18'),
      ]));

      expect(layout.bars, hasLength(1));
      expect(layout.bars.single.durationDays, 9);
      expect(layout.bars.single.basis, DateBasis.explicit);
    });

    test('an undated task is never placed, only listed', () {
      final layout = planner.plan(docWith(tasks: [
        task('dated', due: '2026-09-18'),
        task('undated', basis: 'absent'),
      ]));

      expect(layout.bars.map((b) => b.taskId), ['dated']);
      expect(layout.undated.map((t) => t.id), ['undated'],
          reason:
              'placing it would invent the one thing this design refuses to invent');
    });

    test('an inferred date is placed but stays marked as inferred', () {
      final layout = planner.plan(docWith(tasks: [
        task('a', due: '2026-09-30', basis: 'inferred'),
      ]));

      expect(layout.bars.single.basis, DateBasis.inferred);
      expect(layout.inferredCount, 1,
          reason: 'the chart has to be able to say how much of it was derived');
    });

    test(
        'a due date with no start becomes a short marker, not an invented span',
        () {
      final layout =
          planner.plan(docWith(tasks: [task('a', due: '2026-09-18')]));

      expect(layout.bars.single.durationDays, 1);
      expect(layout.bars.single.start, DateTime(2026, 9, 18));
    });

    test('a start after its due date is treated as a slip, not a negative bar',
        () {
      final layout = planner.plan(docWith(tasks: [
        task('a', start: '2026-09-20', due: '2026-09-18'),
      ]));

      expect(layout.bars.single.durationDays, greaterThan(0));
      expect(layout.bars.single.start.isAfter(layout.bars.single.end), isFalse);
    });

    test('an unparseable date is skipped rather than crashing the chart', () {
      final layout = planner.plan(docWith(tasks: [
        task('bad', due: 'next Thursday'),
        task('good', due: '2026-09-18'),
      ]));

      expect(layout.bars.map((b) => b.taskId), ['good']);
    });

    test('bars are ordered by when the work starts', () {
      final layout = planner.plan(docWith(tasks: [
        task('late', start: '2026-10-01', due: '2026-10-05'),
        task('early', start: '2026-09-01', due: '2026-09-05'),
        task('middle', start: '2026-09-15', due: '2026-09-20'),
      ]));

      expect(layout.bars.map((b) => b.taskId), ['early', 'middle', 'late']);
      expect(layout.bars.map((b) => b.row), [0, 1, 2]);
    });
  });

  group('milestones', () {
    test('anchors become markers and widen the range', () {
      final layout = planner.plan(docWith(
        tasks: [task('a', due: '2026-09-18')],
        anchors: [anchor('Launch', '2026-10-01')],
      ));

      expect(layout.milestones.single.label, 'Launch');
      expect(layout.rangeEnd.isAfter(DateTime(2026, 10, 1)), isTrue);
    });

    test('an anchor with an unusable date is dropped', () {
      final layout = planner.plan(docWith(
        tasks: [task('a', due: '2026-09-18')],
        anchors: [anchor('Someday', 'when we are ready')],
      ));
      expect(layout.milestones, isEmpty);
    });
  });

  group('dependencies', () {
    test('a stated dependency between two placed tasks becomes a link', () {
      final layout = planner.plan(docWith(tasks: [
        task('qa', due: '2026-09-10'),
        task('rollout', due: '2026-09-20', dependsOn: ['qa']),
      ]));

      expect(layout.links, hasLength(1));
      expect(layout.links.single.fromTaskId, 'qa');
      expect(layout.links.single.toTaskId, 'rollout');
    });

    test('a dependency on something not on the chart is dropped', () {
      final layout = planner.plan(docWith(tasks: [
        task('rollout', due: '2026-09-20', dependsOn: ['undated_thing']),
        task('undated_thing', basis: 'absent'),
      ]));

      expect(layout.links, isEmpty,
          reason: 'an arrow pointing at nothing is worse than no arrow');
    });

    test('no dependencies means no arrows — none are inferred from order', () {
      final layout = planner.plan(docWith(tasks: [
        task('a', due: '2026-09-10'),
        task('b', due: '2026-09-20'),
      ]));
      expect(layout.links, isEmpty);
    });
  });

  group('range and positioning', () {
    test('the range is padded so nothing sits flush against an edge', () {
      final layout =
          planner.plan(docWith(tasks: [task('a', due: '2026-09-18')]));

      expect(layout.rangeStart.isBefore(DateTime(2026, 9, 18)), isTrue);
      expect(layout.rangeEnd.isAfter(DateTime(2026, 9, 18)), isTrue);
    });

    test('positions map dates onto 0..1 across the range', () {
      final layout = planner.plan(docWith(tasks: [
        task('a', start: '2026-09-01', due: '2026-09-30'),
      ]));

      expect(layout.fractionFor(layout.rangeStart), 0.0);
      expect(layout.fractionFor(layout.rangeEnd), 1.0);
      expect(layout.fractionFor(DateTime(2026, 9, 15)), closeTo(0.5, 0.1));
    });

    test('a date outside the range is clamped rather than drawn off-chart', () {
      final layout =
          planner.plan(docWith(tasks: [task('a', due: '2026-09-18')]));

      expect(layout.fractionFor(DateTime(2020, 1, 1)), 0.0);
      expect(layout.fractionFor(DateTime(2030, 1, 1)), 1.0);
    });
  });

  group('empty and degenerate notes', () {
    test('a note with nothing dated produces an empty chart, not a crash', () {
      final layout = planner.plan(
        docWith(tasks: [task('a', basis: 'absent')]),
        today: DateTime(2026, 9, 5),
      );

      expect(layout.isEmpty, isTrue);
      expect(layout.rowCount, 0);
      expect(layout.undated, hasLength(1));
      expect(layout.totalDays, greaterThan(0),
          reason: 'the axis still has to render');
    });

    test('a note with no tasks at all is safe', () {
      final layout = planner.plan(docWith(), today: DateTime(2026, 9, 5));
      expect(layout.isEmpty, isTrue);
      expect(layout.bars, isEmpty);
    });
  });

  group('a chart the user built', () {
    GanttItem item(
      String id, {
      required String start,
      required String end,
      bool milestone = false,
      List<String> dependsOn = const [],
      int percent = 0,
      DateBasis basis = DateBasis.explicit,
      String? title,
    }) =>
        GanttItem(
          id: id,
          title: title ?? 'Item $id',
          start: DateTime.parse(start),
          end: DateTime.parse(end),
          isMilestone: milestone,
          dependsOn: dependsOn,
          percentComplete: percent,
          basis: basis,
        );

    test('nothing is on the chart until something is put on it', () {
      final layout = planner.planItems(const [], today: DateTime(2026, 9, 5));

      expect(layout.isEmpty, isTrue);
      expect(layout.bars, isEmpty);
      expect(layout.totalDays, greaterThan(0),
          reason: 'the axis still has to render');
    });

    test('a task the note dated is not on the chart until it is added', () {
      final note = docWith(tasks: [task('a', due: '2026-09-18')]);

      expect(planner.planItems(const []).bars, isEmpty,
          reason: 'a date the model found is a suggestion, not a placement');
      expect(planner.plan(note).bars, hasLength(1),
          reason: 'the note-derived chart is still available to ask about');
    });

    test('an added item becomes a bar spanning its own dates', () {
      final layout = planner
          .planItems([item('a', start: '2026-09-10', end: '2026-09-18')]);

      expect(layout.bars.single.taskId, 'a');
      expect(layout.bars.single.durationDays, 9);
      expect(layout.bars.single.basis, DateBasis.explicit,
          reason: 'a date the user typed is known, not inferred');
    });

    test('a date carried over from a guess stays marked as a guess', () {
      final layout = planner.planItems([
        item('a',
            start: '2026-09-10', end: '2026-09-18', basis: DateBasis.inferred),
      ]);

      expect(layout.inferredCount, 1,
          reason:
              'accepting a form does not turn a guess into something spoken');
    });

    test('a milestone is a marker on one date, never a bar', () {
      final layout = planner.planItems([
        item('launch', start: '2026-10-01', end: '2026-10-01', milestone: true),
      ]);

      expect(layout.bars, isEmpty);
      expect(layout.milestones.single.label, 'Item launch');
      expect(layout.milestones.single.id, 'launch',
          reason: 'the user has to be able to edit the one they placed');
      expect(layout.isEmpty, isFalse);
    });

    test('rows are dense, so no bar is drawn into a gap', () {
      final layout = planner.planItems([
        item('late', start: '2026-10-01', end: '2026-10-05'),
        item('gate', start: '2026-09-20', end: '2026-09-20', milestone: true),
        item('early', start: '2026-09-01', end: '2026-09-05'),
      ]);

      expect(layout.bars.map((b) => b.taskId), ['early', 'late']);
      expect(layout.bars.map((b) => b.row), [0, 1]);
      expect(layout.rowCount, layout.bars.length,
          reason: 'a gap in the rows is a blank stripe and an off-by-one');
    });

    test('a finish before its start is a slip, not a negative bar', () {
      final layout = planner
          .planItems([item('a', start: '2026-09-20', end: '2026-09-18')]);

      expect(layout.bars.single.start.isAfter(layout.bars.single.end), isFalse);
      expect(layout.bars.single.durationDays, greaterThan(0));
    });

    test('progress is reported, never read off the calendar', () {
      final layout = planner.planItems([
        item('a', start: '2020-01-01', end: '2020-01-05', percent: 20),
      ]);

      expect(layout.bars.single.percentComplete, 20,
          reason: 'a bar whose dates have passed is late, not finished');
    });

    test('progress outside 0-100 is clamped rather than drawn off the bar', () {
      final layout = planner.planItems([
        item('a', start: '2026-09-01', end: '2026-09-05', percent: 140),
        item('b', start: '2026-09-06', end: '2026-09-08', percent: -10),
      ]);

      expect(layout.bars.map((b) => b.percentComplete), [100, 0]);
    });

    test('a dependency between two placed items becomes an arrow', () {
      final layout = planner.planItems([
        item('qa', start: '2026-09-01', end: '2026-09-10'),
        item('rollout',
            start: '2026-09-11', end: '2026-09-20', dependsOn: ['qa']),
      ]);

      expect(layout.links.single.fromTaskId, 'qa');
      expect(layout.links.single.toTaskId, 'rollout');
    });

    test('a dependency on something not on the chart is dropped', () {
      final layout = planner.planItems([
        item('rollout',
            start: '2026-09-11', end: '2026-09-20', dependsOn: ['never_added']),
      ]);

      expect(layout.links, isEmpty,
          reason: 'an arrow pointing at nothing is worse than no arrow');
    });

    test('an item cannot depend on itself', () {
      final layout = planner.planItems([
        item('a', start: '2026-09-11', end: '2026-09-20', dependsOn: ['a']),
      ]);

      expect(layout.links, isEmpty);
    });

    test('undated work is passed through for the tray, never placed', () {
      final note = docWith(tasks: [task('undated', basis: 'absent')]);
      final layout = planner.planItems(
        [item('a', start: '2026-09-01', end: '2026-09-05')],
        undated: note.needsDates,
      );

      expect(layout.bars, hasLength(1));
      expect(layout.undated.map((t) => t.id), ['undated']);
    });

    test('the range covers milestones as well as bars', () {
      final layout = planner.planItems([
        item('a', start: '2026-09-01', end: '2026-09-05'),
        item('launch', start: '2026-10-01', end: '2026-10-01', milestone: true),
      ]);

      expect(layout.rangeEnd.isAfter(DateTime(2026, 10, 1)), isTrue);
      expect(layout.rangeStart.isBefore(DateTime(2026, 9, 1)), isTrue);
    });
  });

  group('filling the form in from a task', () {
    test('a dated task offers its dates, owner and workstream', () {
      final note = docWith(tasks: [
        task('a', start: '2026-09-10', due: '2026-09-18', epic: 'Migration'),
      ]);

      final filled = planner.itemFromTask(note.tasks.single)!;

      expect(filled.start, DateTime(2026, 9, 10));
      expect(filled.end, DateTime(2026, 9, 18));
      expect(filled.workstream, 'Migration');
      expect(filled.basis, DateBasis.explicit);
    });

    test('a due date with no start offers a short item, not an invented span',
        () {
      final note = docWith(tasks: [task('a', due: '2026-09-18')]);

      final filled = planner.itemFromTask(note.tasks.single)!;

      expect(filled.durationDays, 1);
      expect(filled.start, DateTime(2026, 9, 18));
    });

    test('a task with nothing usable offers nothing rather than today', () {
      final note = docWith(tasks: [
        task('absent', basis: 'absent'),
        task('unparseable', due: 'next Thursday'),
      ]);

      for (final t in note.tasks) {
        expect(planner.itemFromTask(t), isNull,
            reason: 'an empty form beats a fabricated date');
      }
    });
  });

  test('scales describe how much calendar a column covers', () {
    expect(TimelineScale.day.daysPerColumn, 1);
    expect(TimelineScale.week.daysPerColumn, 7);
    expect(TimelineScale.month.daysPerColumn, 30);
    expect(TimelineScale.values.map((s) => s.label),
        containsAll(['Day', 'Week', 'Month']));
  });
}
