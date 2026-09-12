import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:echo_codex_app/src/data/database.dart' as db;
import 'package:echo_codex_app/src/data/repository.dart';
import 'package:transcript_core/transcript_core.dart';

/// A note with one dated task, one undated task, a decision and an unclear-audio flag —
/// enough to exercise every branch the note screen renders.
Map<String, dynamic> noteJson() => {
      'meta': {
        'title': 'Auth migration kickoff',
        'summary':
            'The team agreed to retire the legacy session store before launch.',
        'recordingType': 'meeting',
        'language': 'en-US',
        'extractionConfidence': 'high',
      },
      'participants': [
        {
          'id': 'p_priya',
          'displayName': 'Priya',
          'aliases': <String>[],
          'role': null
        },
      ],
      'sections': [
        {
          'heading': 'Auth migration',
          'bullets': [
            'The legacy session store is being retired before launch.',
            'Priya owns the migration.',
          ],
          'sourceRef': {
            'startMs': 12000,
            'endMs': 30000,
            'quote': 'we need to get off the legacy session store',
          },
        },
      ],
      'decisions': [
        {
          'id': 'd_retire',
          'statement': 'Retire the legacy session store before launch.',
          'rationale': null,
          'decidedBy': 'p_priya',
          'sourceRef': {
            'startMs': 30000,
            'endMs': 42000,
            'quote': 'we are retiring it before launch, agreed',
          },
        },
      ],
      'openQuestions': [],
      'tasks': [
        {
          'id': 't_migrate',
          'title': 'Migrate the auth service off the legacy session store',
          'detail': null,
          'assigneeId': 'p_priya',
          'assigneeRaw': null,
          'status': 'todo',
          'priority': 'high',
          'estimate': null,
          'startDate': null,
          'dueDate': '2026-09-18',
          'dateBasis': 'explicit',
          'dependsOn': <String>[],
          'epic': null,
          'sourceRef': {
            'startMs': 45000,
            'endMs': 58000,
            'quote': 'it has to be done by the eighteenth',
          },
        },
        {
          'id': 't_runbook',
          'title': 'Update the runbook',
          'detail': null,
          'assigneeId': null,
          'assigneeRaw': null,
          'status': 'todo',
          'priority': 'medium',
          'estimate': null,
          'startDate': null,
          'dueDate': null,
          'dateBasis': 'absent',
          'dependsOn': <String>[],
          'epic': null,
          'sourceRef': {
            'startMs': 70000,
            'endMs': 76000,
            'quote': 'somebody should update the runbook at some point',
          },
        },
      ],
      'risks': [],
      'timelineAnchors': [],
    };

db.Recording recordingRow({
  bool structured = true,
  String? overrideNote,
  String? transcriptText,
  String? transcriptSegmentsJson,
  String? speakerNamesJson,
  String? cleanedTranscriptText,
  bool priority = false,
}) =>
    db.Recording(
      id: 'r_1',
      title: 'Auth migration kickoff',
      startedAt: DateTime(2026, 9, 5, 10, 30),
      durationMs: 95000,
      audioPath: '/tmp/rec.wav',
      transcriptionProviderId: 'on-device',
      structuringProviderId: 'anthropic',
      structuringModel: 'claude-opus-5',
      noteJson: structured ? (overrideNote ?? jsonEncode(noteJson())) : null,
      noteSchemaVersion: 'note-document/v1',
      promptVersion: 'structuring/2026-09-05',
      inputTokens: 1840,
      outputTokens: 610,
      transcriptText: transcriptText,
      transcriptSegmentsJson: transcriptSegmentsJson,
      speakerNamesJson: speakerNamesJson,
      cleanedTranscriptText: cleanedTranscriptText,
      priority: priority,
      localOnly: false,
      templateId: null,
    );

db.CodexNote codexNoteRow({
  String id = 'codex_1',
  String body = 'Kella took an arrow but shook it off.',
  String? sourceRecordingId,
  String? sourceRecordingTitle,
}) =>
    db.CodexNote(
      id: id,
      body: body,
      createdAt: DateTime(2026, 9, 5, 10, 30),
      updatedAt: DateTime(2026, 9, 5, 10, 30),
      sourceRecordingId: sourceRecordingId,
      sourceRecordingTitle: sourceRecordingTitle,
    );

/// A [RecordingRepository] stand-in for widget tests that need real delete behaviour
/// (an item leaving the list, a repeat delete being a no-op) without a real drift
/// database — a live `watch()` stream left dangling timers that flutter_test's teardown
/// invariants then tripped over.
class FakeRecordingRepository implements RecordingRepository {
  FakeRecordingRepository(List<db.Recording> initial,
      {List<db.CodexNote> codexNotes = const []})
      : _rows = List.of(initial),
        _controller = StreamController<List<db.Recording>>.broadcast(),
        _codexNotes = List.of(codexNotes);

  List<db.Recording> _rows;
  final StreamController<List<db.Recording>> _controller;
  final List<String> deletedIds = [];

  List<db.CodexNote> _codexNotes = [];
  final StreamController<List<db.CodexNote>> _codexController =
      StreamController<List<db.CodexNote>>.broadcast();
  final List<String> deletedCodexNoteIds = [];

  List<db.GanttEntry> _ganttEntries = [];
  final StreamController<List<db.GanttEntry>> _ganttController =
      StreamController<List<db.GanttEntry>>.broadcast();
  final List<String> deletedGanttEntryIds = [];

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    _rows = _rows.where((r) => r.id != id).toList();
    _controller.add(List.unmodifiable(_rows));
  }

  @override
  Future<void> deleteSourceAudio(String id) async {}

  @override
  Future<void> recordPrivacyAudit(String action, String detail) async {}

  @override
  Future<List<db.PrivacyAudit>> privacyAudits() async => const [];

  @override
  Future<void> restoreBackupRecording(
    Map<String, dynamic> data, {
    List<int>? audioBytes,
    String? audioExtension,
  }) async {}

  // A broadcast stream drops any event fired before a listener subscribes, and the
  // widget subscribes only once it builds — so a plain `_controller.stream` would leave
  // the provider stuck in `loading` forever. Yielding the current snapshot first, then
  // forwarding later updates, gives every new subscriber the same behaviour drift's
  // `watch()` has: an immediate value, then live changes.
  @override
  Stream<List<db.Recording>> watchAll() async* {
    yield List.unmodifiable(_rows);
    yield* _controller.stream;
  }

  @override
  Future<List<db.Recording>> all() async => List.of(_rows);

  // Same immediate-snapshot-then-live-updates shape as watchAll, so a Codex-search
  // test behaves the same as the recordings one it sits next to.
  @override
  Stream<List<db.CodexNote>> watchCodexNotes() async* {
    yield List.unmodifiable(_codexNotes);
    yield* _codexController.stream;
  }

  @override
  Future<List<db.CodexNote>> codexNotes() async => List.of(_codexNotes);

  @override
  Future<String> createCodexNote(
    String body, {
    String? sourceRecordingId,
    String? sourceRecordingTitle,
  }) async {
    final now = DateTime.now();
    final id = 'codex_${_codexNotes.length}_${now.microsecondsSinceEpoch}';
    _codexNotes = [
      ..._codexNotes,
      db.CodexNote(
        id: id,
        body: body,
        createdAt: now,
        updatedAt: now,
        sourceRecordingId: sourceRecordingId,
        sourceRecordingTitle: sourceRecordingTitle,
      ),
    ];
    _codexController.add(List.unmodifiable(_codexNotes));
    return id;
  }

  @override
  Future<void> updateCodexNote(String id, String body) async {
    _codexNotes = [
      for (final n in _codexNotes)
        if (n.id == id) n.copyWith(body: body, updatedAt: DateTime.now()) else n,
    ];
    _codexController.add(List.unmodifiable(_codexNotes));
  }

  @override
  Future<void> deleteCodexNote(String id) async {
    deletedCodexNoteIds.add(id);
    _codexNotes = _codexNotes.where((n) => n.id != id).toList();
    _codexController.add(List.unmodifiable(_codexNotes));
  }

  // Same immediate-snapshot-then-live-updates shape again, so a test can add an item
  // to the chart and watch it appear exactly as it would on a device.
  @override
  Stream<List<db.GanttEntry>> watchGanttEntries(String recordingId) async* {
    yield _ganttFor(recordingId);
    yield* _ganttController.stream.map((_) => _ganttFor(recordingId));
  }

  @override
  Future<List<db.GanttEntry>> ganttEntries(String recordingId) async =>
      _ganttFor(recordingId);

  /// What is actually on the chart, for a test to assert against directly rather than
  /// inferring it from pixels.
  List<db.GanttEntry> ganttFor(String recordingId) => _ganttFor(recordingId);

  List<db.GanttEntry> _ganttFor(String recordingId) {
    final rows = <db.GanttEntry>[
      for (final e in _ganttEntries)
        if (e.recordingId == recordingId) e,
    ]..sort((a, b) => a.startDate.compareTo(b.startDate));
    return List.unmodifiable(rows);
  }

  @override
  Future<String> saveGanttEntry({
    required String recordingId,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    String? id,
    String? owner,
    String? workstream,
    int percentComplete = 0,
    bool milestone = false,
    List<String> dependsOn = const [],
    DateBasis dateBasis = DateBasis.explicit,
    String? sourceTaskId,
  }) async {
    final now = DateTime.now();
    final entryId = id ?? 'gantt_${_ganttEntries.length}_${now.microsecondsSinceEpoch}';
    final from = startDate.isAfter(endDate) ? endDate : startDate;
    final row = db.GanttEntry(
      id: entryId,
      recordingId: recordingId,
      title: title,
      startDate: milestone ? startDate : from,
      endDate: milestone ? startDate : endDate,
      owner: owner,
      workstream: workstream,
      percentComplete: percentComplete.clamp(0, 100),
      milestone: milestone,
      dependsOnJson: dependsOn.isEmpty ? null : jsonEncode(dependsOn),
      dateBasis: dateBasis.name,
      sourceTaskId: sourceTaskId,
      createdAt: now,
      updatedAt: now,
    );
    _ganttEntries = [
      for (final e in _ganttEntries)
        if (e.id != entryId) e,
      row,
    ];
    _ganttController.add(List.unmodifiable(_ganttEntries));
    return entryId;
  }

  @override
  Future<void> deleteGanttEntry(String id) async {
    deletedGanttEntryIds.add(id);
    _ganttEntries = _ganttEntries.where((e) => e.id != id).toList();
    _ganttController.add(List.unmodifiable(_ganttEntries));
  }

  @override
  Future<db.Recording?> byId(String id) async =>
      _rows.where((r) => r.id == id).firstOrNull;

  @override
  Future<String> createRecording({
    required String path,
    required Duration duration,
    required String transcriptionProviderId,
    required String structuringProviderId,
    String? title,
    bool localOnly = false,
    String? templateId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setLocalOnly(String recordingId, bool localOnly) =>
      throw UnimplementedError();

  @override
  Future<void> setLanguage(String recordingId, String? language) async {
    _rows = [
      for (final row in _rows)
        if (row.id == recordingId)
          row.copyWith(language: Value(language))
        else
          row,
    ];
    _controller.add(List.unmodifiable(_rows));
  }

  @override
  Future<void> deleteReminder(String recordingId, String taskId) async {}

  @override
  Future<void> saveSpeakerNames(
      String recordingId, Map<String, String> names) async {
    _rows = [
      for (final row in _rows)
        if (row.id == recordingId)
          row.copyWith(speakerNamesJson: Value(jsonEncode(names)))
        else
          row,
    ];
    _controller.add(List.unmodifiable(_rows));
  }

  @override
  Future<void> updateTranscriptSegment(
      String recordingId, int index, String text) async {
    _rows = [
      for (final row in _rows)
        if (row.id == recordingId && row.transcriptSegmentsJson != null)
          () {
            final decoded =
                jsonDecode(row.transcriptSegmentsJson!) as List<dynamic>;
            final segments = decoded
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            if (index < 0 || index >= segments.length) return row;
            segments[index]['text'] = text;
            return row.copyWith(
              transcriptSegmentsJson: Value(jsonEncode(segments)),
              transcriptText: Value(
                segments.map((s) => s['text'] as String? ?? '').join(' '),
              ),
            );
          }()
        else
          row,
    ];
    _controller.add(List.unmodifiable(_rows));
  }

  @override
  Future<List<ProcessingQueueItem>> processingQueue() async => const [];

  @override
  Future<void> retryRecording(String recordingId) async {}

  @override
  Future<List<db.NoteTemplate>> templates() async => const [];

  @override
  Future<void> saveTemplate({
    required String id,
    required String name,
    required String instructions,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteTemplate(String id) => throw UnimplementedError();

  @override
  Future<void> saveReminder({
    required String recordingId,
    required String taskId,
    required String title,
    required DateTime remindAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<db.ActionReminder>> reminders({bool pendingOnly = false}) async =>
      const [];

  @override
  Future<void> completeReminder(String id, bool completed) =>
      throw UnimplementedError();

  @override
  Future<void> saveTranscript(
    String recordingId,
    Transcript transcript, {
    String? cleaned,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setPriority(String recordingId, bool priority) async {
    _rows = [
      for (final r in _rows)
        if (r.id == recordingId) r.copyWith(priority: priority) else r,
    ];
    _controller.add(List.unmodifiable(_rows));
  }

  @override
  Future<void> saveNote(String recordingId, StructureOutcome outcome) =>
      throw UnimplementedError();

  @override
  Future<void> updateNote(String recordingId, NoteDocument document) =>
      throw UnimplementedError();
}
