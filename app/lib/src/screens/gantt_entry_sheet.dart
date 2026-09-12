import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:transcript_core/transcript_core.dart';

import '../data/database.dart' as db;
import '../recording/recording_controller.dart';
import 'gantt_controller.dart';

/// Opens the form that puts one item on the Gantt chart.
///
/// Everything a bar needs is asked for here and nothing is filled in behind the user's
/// back: this form is the moment a line of notes becomes a commitment, and the app has
/// no business deciding when a piece of work runs. Where the recording already
/// established something — a date someone said out loud, an owner, a workstream — it
/// arrives prefilled and clearly marked, for the user to accept or correct.
///
/// Returns true when something was saved.
Future<bool> openGanttEntrySheet(
  BuildContext context,
  WidgetRef ref, {
  required String recordingId,
  required NoteDocument note,
  String? initialTitle,
  NoteTask? task,
  db.GanttEntry? entry,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => GanttEntrySheet(
      recordingId: recordingId,
      note: note,
      initialTitle: initialTitle,
      task: task,
      entry: entry,
    ),
  );
  return saved ?? false;
}

/// The form behind [openGanttEntrySheet].
class GanttEntrySheet extends ConsumerStatefulWidget {
  const GanttEntrySheet({
    super.key,
    required this.recordingId,
    required this.note,
    this.initialTitle,
    this.task,
    this.entry,
  });

  final String recordingId;
  final NoteDocument note;

  /// A line of notes the user chose to plan, when the form was opened from one.
  final String? initialTitle;

  /// The task this is being placed from, when it was opened from one.
  final NoteTask? task;

  /// The item being edited, when the form was opened from the chart.
  final db.GanttEntry? entry;

  @override
  ConsumerState<GanttEntrySheet> createState() => _GanttEntrySheetState();
}

class _GanttEntrySheetState extends ConsumerState<GanttEntrySheet> {
  late final TextEditingController _title;
  late final TextEditingController _owner;
  late final TextEditingController _workstream;

  late DateTime _start;
  late DateTime _end;
  late bool _milestone;
  late int _percent;
  late Set<String> _dependsOn;

  /// Carried, not decided here. A date this form prefilled from a model's guess is
  /// still a guess until the user changes it, and the chart draws the two differently.
  late DateBasis _basis;

  bool _saving = false;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    // Prefer whatever the recording already established over an empty form, but never
    // invent a date: an item with nothing to go on starts today, which is the one date
    // that is plainly the user's own default rather than a claim about the meeting.
    final prefill = entry == null && widget.task != null
        ? const TimelinePlanner().itemFromTask(widget.task!)
        : null;
    final today = DateUtils.dateOnly(DateTime.now());

    _title = TextEditingController(
      text: entry?.title ?? widget.task?.title ?? widget.initialTitle ?? '',
    );
    _owner = TextEditingController(
      text: entry?.owner ?? _ownerOf(widget.task) ?? '',
    );
    _workstream = TextEditingController(
      text: entry?.workstream ?? prefill?.workstream ?? widget.task?.epic ?? '',
    );

    _start = DateUtils.dateOnly(entry?.startDate ?? prefill?.start ?? today);
    _end = DateUtils.dateOnly(entry?.endDate ?? prefill?.end ?? _start);
    _milestone = entry?.milestone ?? false;
    _percent = entry?.percentComplete ?? 0;
    _dependsOn = {
      if (entry != null) ...dependenciesOf(entry),
    };
    _basis = entry == null
        ? (prefill?.basis ?? DateBasis.explicit)
        : (DateBasis.values
                .where((b) => b.name == entry.dateBasis)
                .firstOrNull ??
            DateBasis.explicit);
  }

  /// The owner as a person would write it: a participant's name where the id resolves,
  /// otherwise whatever was actually said.
  String? _ownerOf(NoteTask? task) {
    if (task == null) return null;
    final id = task.assigneeId;
    if (id != null) {
      final person =
          widget.note.participants.where((p) => p.id == id).firstOrNull;
      if (person != null) return person.displayName;
    }
    return task.assigneeRaw;
  }

  @override
  void dispose() {
    _title.dispose();
    _owner.dispose();
    _workstream.dispose();
    super.dispose();
  }

  int get _durationDays => _end.difference(_start).inDays + 1;

  /// The one rule the form enforces, because a chart cannot draw its way around it.
  bool get _endsBeforeItStarts => !_milestone && _end.isBefore(_start);

  /// Every other item on this chart, as candidate predecessors. The item being edited
  /// is not among them: a bar that waits for itself can never start.
  List<db.GanttEntry> get _candidates => (ref
              .watch(ganttEntriesProvider(widget.recordingId))
              .valueOrNull ??
          const <db.GanttEntry>[])
      .where((e) => e.id != widget.entry?.id)
      .toList();

  Future<void> _pick({required bool start}) async {
    final initial = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final day = DateUtils.dateOnly(picked);
      if (start) {
        // Moving the start drags the finish with it rather than silently inverting the
        // bar; the length the user already chose is what they meant to keep.
        final length = _end.difference(_start).inDays;
        _start = day;
        if (length >= 0) _end = day.add(Duration(days: length));
      } else {
        _end = day;
      }
      // A date the user chose is known, whatever it was before they touched it.
      _basis = DateBasis.explicit;
    });
  }

  /// Takes the item off the chart. The note it came from is untouched: the plan and
  /// the record of the meeting are separate things, and removing one has never been a
  /// reason to edit the other.
  Future<void> _remove() async {
    final entry = widget.entry;
    if (entry == null || _saving) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    await ref.read(repositoryProvider).deleteGanttEntry(entry.id);
    navigator.pop(true);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _endsBeforeItStarts || _saving) return;

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final owner = _owner.text.trim();
    final workstream = _workstream.text.trim();

    await ref.read(repositoryProvider).saveGanttEntry(
          id: widget.entry?.id,
          recordingId: widget.recordingId,
          title: title,
          startDate: _start,
          endDate: _milestone ? _start : _end,
          owner: owner.isEmpty ? null : owner,
          workstream: workstream.isEmpty ? null : workstream,
          percentComplete: _milestone ? 0 : _percent,
          milestone: _milestone,
          dependsOn: _dependsOn.toList(),
          dateBasis: _basis,
          sourceTaskId: widget.entry?.sourceTaskId ?? widget.task?.id,
        );
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat.yMMMd();
    // Wide enough to read on a desktop, never wider than the phone it is on.
    final width =
        math.min(420.0, math.max(240.0, MediaQuery.of(context).size.width - 80));

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(_isEdit ? 'Edit chart item' : 'Add to Gantt'),
          ),
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove from chart',
              onPressed: _saving ? null : _remove,
            ),
        ],
      ),
      scrollable: true,
      content: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'What goes on the chart',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _milestone,
              title: const Text('Milestone'),
              subtitle: const Text('A single dated event, with no duration'),
              onChanged: (on) => setState(() => _milestone = on),
            ),
            const SizedBox(height: 4),
            _Label(_milestone ? 'Date' : 'Start'),
            _DateButton(
              label: format.format(_start),
              semanticLabel: _milestone
                  ? 'Milestone date ${format.format(_start)}'
                  : 'Start ${format.format(_start)}',
              onPressed: () => _pick(start: true),
            ),
            if (!_milestone) ...[
              const SizedBox(height: 12),
              _Label('Finish'),
              _DateButton(
                label: format.format(_end),
                semanticLabel: 'Finish ${format.format(_end)}',
                onPressed: () => _pick(start: false),
              ),
              const SizedBox(height: 6),
              if (_endsBeforeItStarts)
                Text(
                  'The finish is before the start. Nothing can be drawn from that.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                )
              else
                Text(
                  '$_durationDays ${_durationDays == 1 ? 'day' : 'days'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
            if (_basis == DateBasis.inferred)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'These dates were worked out from the recording, not stated '
                  'outright. Pick them yourself to confirm them.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.tertiary),
                ),
              ),
            const SizedBox(height: 16),
            _Label('Owner'),
            TextField(
              controller: _owner,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Who is doing it',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (widget.note.participants.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final person in widget.note.participants)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(person.displayName),
                      onPressed: () => setState(
                          () => _owner.text = person.displayName),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _Label('Workstream'),
            TextField(
              controller: _workstream,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Phase, epic or swimlane',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (!_milestone) ...[
              const SizedBox(height: 16),
              _Label('Progress — $_percent%'),
              Semantics(
                label: 'Percent complete',
                value: '$_percent%',
                child: Slider(
                  value: _percent.toDouble(),
                  max: 100,
                  divisions: 20,
                  label: '$_percent%',
                  onChanged: (v) => setState(() => _percent = v.round()),
                ),
              ),
              Text(
                'Reported, never read off the calendar: a bar whose dates have '
                'passed is late, not finished.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (_candidates.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Label('Waits for'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final candidate in _candidates)
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        candidate.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: _dependsOn.contains(candidate.id),
                      onSelected: (on) => setState(() => on
                          ? _dependsOn.add(candidate.id)
                          : _dependsOn.remove(candidate.id)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _title.text.trim().isEmpty || _endsBeforeItStarts || _saving
              ? null
              : _save,
          child: Text(_isEdit ? 'Save' : 'Add to chart'),
        ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.event, size: 18),
          label: Text(label),
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Semantics(
          header: true,
          child: Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
}
