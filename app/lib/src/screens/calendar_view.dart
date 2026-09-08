import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:transcript_core/transcript_core.dart';

import 'task_editor.dart';

class CalendarView extends ConsumerStatefulWidget {
  const CalendarView({super.key, required this.recordingId, required this.note});

  final String recordingId;
  final NoteDocument note;

  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  late DateTime _month = DateTime.now();

  List<NoteTask> _tasksFor(DateTime day) => widget.note.tasks.where((task) {
        final date = _dateFor(task);
        return date != null &&
            date.year == day.year &&
            date.month == day.month &&
            date.day == day.day;
      }).toList();

  DateTime? _dateFor(NoteTask task) {
    if (task.dateBasis == DateBasis.absent || task.dueDate == null) return null;
    return DateTime.tryParse(task.dueDate!);
  }

  void _shiftMonth(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(_month.year, _month.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final days = List.generate(42, (index) => gridStart.add(Duration(days: index)));
    final datedTasks = widget.note.tasks.where((task) => _dateFor(task) != null).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous month',
                onPressed: () => _shiftMonth(-1),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM().format(_month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.today),
                tooltip: 'Current month',
                onPressed: () => setState(() => _month = DateTime.now()),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next month',
                onPressed: () => _shiftMonth(1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final label in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                Expanded(
                  child: Center(
                    child: Text(label, style: theme.textTheme.labelSmall),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 276,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) {
              final day = days[index];
              final tasks = _tasksFor(day);
              final inMonth = day.month == _month.month;
              final today = DateUtils.isSameDay(day, DateTime.now());
              return _DayCell(
                day: day,
                tasks: tasks,
                inMonth: inMonth,
                today: today,
                onTaskTap: (task) => openTaskEditor(
                  context,
                  ref,
                  recordingId: widget.recordingId,
                  note: widget.note,
                  task: task,
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: datedTasks.isEmpty
              ? const Center(child: Text('No dated tasks in this note.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: datedTasks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final task = datedTasks[index];
                    final date = _dateFor(task)!;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        task.dateBasis == DateBasis.inferred
                            ? Icons.event_note
                            : Icons.event_available,
                        color: task.dateBasis == DateBasis.inferred
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.primary,
                      ),
                      title: Text(task.title),
                      subtitle: Text(
                        '${DateFormat.yMMMd().format(date)}'
                        '${task.dateBasis == DateBasis.inferred ? ' · inferred' : ''}',
                      ),
                      onTap: () => openTaskEditor(
                        context,
                        ref,
                        recordingId: widget.recordingId,
                        note: widget.note,
                        task: task,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.tasks,
    required this.inMonth,
    required this.today,
    required this.onTaskTap,
  });

  final DateTime day;
  final List<NoteTask> tasks;
  final bool inMonth;
  final bool today;
  final ValueChanged<NoteTask> onTaskTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: today ? theme.colorScheme.primaryContainer : null,
        border: Border.all(
          color: today ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: tasks.isEmpty ? null : () => onTaskTap(tasks.first),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${day.day}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: inMonth
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  fontWeight: today ? FontWeight.bold : null,
                ),
              ),
              for (final task in tasks.take(2))
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                    decoration: BoxDecoration(
                      color: task.dateBasis == DateBasis.inferred
                          ? theme.colorScheme.tertiaryContainer
                          : theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: task.dateBasis == DateBasis.inferred
                            ? theme.colorScheme.onTertiaryContainer
                            : theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              if (tasks.length > 2)
                Text('+${tasks.length - 2} more', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
