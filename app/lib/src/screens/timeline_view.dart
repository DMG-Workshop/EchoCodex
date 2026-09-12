import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transcript_core/transcript_core.dart';

import '../data/database.dart' as db;
import 'gantt_controller.dart';
import 'gantt_entry_sheet.dart';

/// The Gantt chart, which the user builds rather than the app derives.
///
/// Nothing lands here because a model found a date in the recording. A note's dates are
/// a suggestion; a plan is a set of commitments somebody made on purpose, one form at a
/// time. So the chart starts empty and fills from the tray below it and the "add to
/// Gantt" button beside each line of notes — the same deliberate gesture that puts a
/// line in the Codex.
///
/// What the recording did establish is still carried, not discarded: a date someone
/// spoke arrives prefilled, and a date the model worked out arrives prefilled *and*
/// marked. `dateBasis` survives all the way onto the canvas, because a derived date and
/// a spoken one are identical as values and must never be identical on screen.
class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key, required this.recordingId, required this.note});

  final String recordingId;
  final NoteDocument note;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  TimelineScale _scale = TimelineScale.week;

  static const double rowHeight = 40;
  static const double labelWidth = 150;

  double get _pixelsPerDay => switch (_scale) {
        TimelineScale.day => 44,
        TimelineScale.week => 14,
        TimelineScale.month => 5,
      };

  Future<void> _open({db.GanttEntry? entry, NoteTask? task}) =>
      openGanttEntrySheet(
        context,
        ref,
        recordingId: widget.recordingId,
        note: widget.note,
        entry: entry,
        task: task,
      );

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(ganttEntriesProvider(widget.recordingId));

    return entries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Could not open the chart.\n$e',
              textAlign: TextAlign.center),
        ),
      ),
      data: _chart,
    );
  }

  Widget _chart(List<db.GanttEntry> entries) {
    final theme = Theme.of(context);
    final layout = const TimelinePlanner()
        .planItems([for (final entry in entries) ganttItemOf(entry)]);
    // Everything the recording produced that is not on the chart yet — the list the
    // user checks off. Computed here rather than carried through the layout, because
    // what is missing from a plan is a fact about this screen, not about the geometry.
    final offChart = tasksNotOnChart(widget.note, entries);
    final byId = {for (final entry in entries) entry.id: entry};

    if (layout.isEmpty) {
      return _EmptyChart(
        offChart: offChart,
        onAdd: () => _open(),
        onAddTask: (task) => _open(task: task),
      );
    }

    final chartWidth = layout.totalDays * _pixelsPerDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScaleBar(
          scale: _scale,
          inferredCount: layout.inferredCount,
          onChanged: (s) => setState(() => _scale = s),
          onAdd: () => _open(),
        ),
        if (layout.milestones.isNotEmpty)
          _MilestoneStrip(
            milestones: layout.milestones,
            onTap: (id) {
              final entry = byId[id];
              if (entry != null) _open(entry: entry);
            },
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Labels stay put while the chart scrolls; a bar with no visible name
                // is not worth drawing.
                SizedBox(
                  width: labelWidth,
                  child: Column(
                    children: [
                      const SizedBox(height: 28),
                      for (final bar in layout.bars)
                        SizedBox(
                          height: rowHeight,
                          child: InkWell(
                            onTap: () {
                              final entry = byId[bar.taskId];
                              if (entry != null) _open(entry: entry);
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(left: 16, right: 8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bar.title,
                                    maxLines: _subtitleOf(bar) == null ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  if (_subtitleOf(bar) case final subtitle?)
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: chartWidth,
                      height: 28 + layout.bars.length * rowHeight,
                      child: CustomPaint(
                        painter: TimelinePainter(
                          layout: layout,
                          pixelsPerDay: _pixelsPerDay,
                          rowHeight: rowHeight,
                          scheme: theme.colorScheme,
                          textDirection: Directionality.of(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (offChart.isNotEmpty)
          _OffChartTray(tasks: offChart, onTap: (task) => _open(task: task)),
      ],
    );
  }

  /// Owner and workstream under the name — the two columns every Gantt carries beside
  /// its bars. Shown only because the form asks for them: a field the chart never
  /// displays has no business being on the form.
  static String? _subtitleOf(TimelineBar bar) {
    final parts = [
      if (bar.assigneeId case final owner? when owner.isNotEmpty) owner,
      if (bar.epic case final epic? when epic.isNotEmpty) epic,
      if (bar.percentComplete > 0) '${bar.percentComplete}%',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _ScaleBar extends StatelessWidget {
  const _ScaleBar({
    required this.scale,
    required this.inferredCount,
    required this.onChanged,
    required this.onAdd,
  });

  final TimelineScale scale;
  final int inferredCount;
  final ValueChanged<TimelineScale> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          SegmentedButton<TimelineScale>(
            segments: [
              for (final s in TimelineScale.values)
                ButtonSegment(value: s, label: Text(s.label)),
            ],
            selected: {scale},
            showSelectedIcon: false,
            onSelectionChanged: (set) => onChanged(set.first),
          ),
          const Spacer(),
          if (inferredCount > 0)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 14, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '$inferredCount inferred',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.tertiary),
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add_chart),
            tooltip: 'Add to Gantt',
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// Draws the chart. Split out so the geometry is one object with one job.
class TimelinePainter extends CustomPainter {
  TimelinePainter({
    required this.layout,
    required this.pixelsPerDay,
    required this.rowHeight,
    required this.scheme,
    required this.textDirection,
  });

  final TimelineLayout layout;
  final double pixelsPerDay;
  final double rowHeight;
  final ColorScheme scheme;
  final TextDirection textDirection;

  static const double headerHeight = 28;
  static const double barHeight = 20;

  @override
  void paint(Canvas canvas, Size size) {
    _paintMonthGrid(canvas, size);
    _paintMilestones(canvas, size);
    _paintLinks(canvas);
    _paintBars(canvas);
  }

  double _x(DateTime date) =>
      date.difference(layout.rangeStart).inDays * pixelsPerDay;

  double _rowCentre(int row) =>
      headerHeight + row * rowHeight + rowHeight / 2;

  void _paintMonthGrid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    var cursor = DateTime(layout.rangeStart.year, layout.rangeStart.month, 1);
    while (cursor.isBefore(layout.rangeEnd)) {
      final x = _x(cursor);
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(Offset(x, headerHeight), Offset(x, size.height), line);
        _label(canvas, _monthName(cursor), Offset(x + 4, 8), scheme.onSurfaceVariant, 10);
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
  }

  void _paintMilestones(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = scheme.error
      ..strokeWidth = 1.5;

    for (final milestone in layout.milestones) {
      final x = _x(milestone.date);
      canvas.drawLine(Offset(x, headerHeight), Offset(x, size.height), paint);
      // A small diamond, so a milestone reads differently from a task at a glance.
      final path = Path()
        ..moveTo(x, headerHeight - 6)
        ..lineTo(x + 5, headerHeight)
        ..lineTo(x, headerHeight + 6)
        ..lineTo(x - 5, headerHeight)
        ..close();
      canvas.drawPath(path, Paint()..color = scheme.error);
      _label(canvas, milestone.label, Offset(x + 8, headerHeight - 6), scheme.error, 10);
    }
  }

  void _paintLinks(Canvas canvas) {
    final byId = {for (final bar in layout.bars) bar.taskId: bar};
    final paint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final link in layout.links) {
      final from = byId[link.fromTaskId];
      final to = byId[link.toTaskId];
      if (from == null || to == null) continue;

      final startX = _x(from.end) + pixelsPerDay;
      final startY = _rowCentre(from.row);
      final endX = _x(to.start);
      final endY = _rowCentre(to.row);

      // An elbow rather than a diagonal: it stays readable when rows are close together.
      final midX = startX + 8;
      canvas.drawPath(
        Path()
          ..moveTo(startX, startY)
          ..lineTo(midX, startY)
          ..lineTo(midX, endY)
          ..lineTo(endX, endY),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(endX, endY)
          ..lineTo(endX - 5, endY - 3)
          ..lineTo(endX - 5, endY + 3)
          ..close(),
        Paint()..color = scheme.onSurfaceVariant.withValues(alpha: 0.6),
      );
    }
  }

  void _paintBars(Canvas canvas) {
    for (final bar in layout.bars) {
      final left = _x(bar.start);
      final width = (bar.durationDays * pixelsPerDay).clamp(6.0, double.infinity);
      final top = _rowCentre(bar.row) - barHeight / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, barHeight),
        const Radius.circular(4),
      );

      switch (bar.basis) {
        case DateBasis.explicit:
          // Solid: this date is known — spoken in the recording, or chosen by the
          // person who put it on the chart.
          canvas.drawRRect(rect, Paint()..color = scheme.primary);
        case DateBasis.inferred:
          // Hatched and outlined: derived from the recording, not stated.
          canvas.drawRRect(
            rect,
            Paint()..color = scheme.tertiary.withValues(alpha: 0.18),
          );
          _hatch(canvas, rect, scheme.tertiary);
          canvas.drawRRect(
            rect,
            Paint()
              ..color = scheme.tertiary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        case DateBasis.absent:
          // Never drawn — an undated task has no honest position on a chart.
          break;
      }

      _paintProgress(canvas, rect, bar);
    }
  }

  /// Reported progress, as a darker fill from the left edge of the bar.
  ///
  /// Deliberately clipped to the bar rather than drawn as a second bar beside it: the
  /// claim being made is "this much of *this* work is done", and a separate shape
  /// invites reading it as its own span of time.
  void _paintProgress(Canvas canvas, RRect rect, TimelineBar bar) {
    if (bar.percentComplete <= 0 || bar.basis == DateBasis.absent) return;
    final fraction = (bar.percentComplete / 100).clamp(0.0, 1.0);
    canvas.save();
    canvas.clipRRect(rect);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width * fraction, rect.height),
      Paint()
        ..color = bar.basis == DateBasis.explicit
            ? scheme.onPrimary.withValues(alpha: 0.45)
            : scheme.tertiary.withValues(alpha: 0.45),
    );
    canvas.restore();
  }

  /// Diagonal hatching, clipped to the bar.
  void _hatch(Canvas canvas, RRect rect, Color color) {
    canvas.save();
    canvas.clipRRect(rect);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var x = rect.left - rect.height; x < rect.right; x += 5) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + rect.height, rect.top),
        paint,
      );
    }
    canvas.restore();
  }

  void _label(Canvas canvas, String text, Offset at, Color color, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    painter.paint(canvas, at);
  }

  static String _monthName(DateTime d) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][d.month - 1];

  @override
  bool shouldRepaint(TimelinePainter old) =>
      old.pixelsPerDay != pixelsPerDay ||
      old.layout != layout ||
      old.scheme != scheme;
}

/// Everything the recording produced that is not on the chart yet.
///
/// This is the list the user checks off. Tasks the note already dated appear here too:
/// a date the model found is a suggestion, and the chart is for things somebody decided
/// on. Tapping one opens the form with whatever is already known filled in.
class _OffChartTray extends StatelessWidget {
  const _OffChartTray({required this.tasks, required this.onTap});

  final List<NoteTask> tasks;
  final ValueChanged<NoteTask> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Not on the chart yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            'Nothing is placed for you and no dates have been guessed. '
            'Tap one to put it on the chart.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final task in tasks)
                ActionChip(
                  // Two icons, because the form behind them differs: one opens with
                  // dates to confirm, the other with nothing but the name.
                  avatar: Icon(
                    task.isSchedulable ? Icons.event_available : Icons.event_busy,
                    size: 15,
                  ),
                  label: Text(task.title, overflow: TextOverflow.ellipsis),
                  onPressed: () => onTap(task),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Milestones sit on the axis rather than in the label column, so this strip is the
/// only way to get back to one and change it.
class _MilestoneStrip extends StatelessWidget {
  const _MilestoneStrip({required this.milestones, required this.onTap});

  final List<TimelineMilestone> milestones;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final milestone in milestones)
            if (milestone.id case final id?)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.flag_outlined,
                    size: 15, color: theme.colorScheme.error),
                label: Text(milestone.label, overflow: TextOverflow.ellipsis),
                onPressed: () => onTap(id),
              ),
        ],
      ),
    );
  }
}

/// What the chart says before anything is on it.
///
/// Not an error and not a failure to load: an empty chart is the correct state for a
/// plan nobody has built yet, and saying so is better than a blank canvas the user
/// reads as broken.
class _EmptyChart extends StatelessWidget {
  const _EmptyChart({
    required this.offChart,
    required this.onAdd,
    required this.onAddTask,
  });

  final List<NoteTask> offChart;
  final VoidCallback onAdd;
  final ValueChanged<NoteTask> onAddTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_chart,
                        size: 40, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 14),
                    Text('Nothing on the chart yet',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      offChart.isEmpty
                          ? 'The chart is built by hand. Add an item and say when it '
                              'runs, and it will appear here.'
                          : 'The chart is built by hand — nothing from the recording '
                              'is placed on it for you. Pick something below, or add '
                              'an item of your own.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add an item'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (offChart.isNotEmpty)
          _OffChartTray(tasks: offChart, onTap: onAddTask),
      ],
    );
  }
}
