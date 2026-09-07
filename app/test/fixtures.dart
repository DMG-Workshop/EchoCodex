import 'dart:async';
import 'dart:convert';

import 'package:transcript_app/src/data/database.dart' as db;
import 'package:transcript_app/src/data/repository.dart';
import 'package:transcript_core/transcript_core.dart';

/// A note with one dated task, one undated task, a decision and an unclear-audio flag —
/// enough to exercise every branch the note screen renders.
Map<String, dynamic> noteJson() => {
      'meta': {
        'title': 'Auth migration kickoff',
        'summary': 'The team agreed to retire the legacy session store before launch.',
        'recordingType': 'meeting',
        'language': 'en-US',
        'extractionConfidence': 'high',
      },
      'participants': [
        {'id': 'p_priya', 'displayName': 'Priya', 'aliases': <String>[], 'role': null},
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

db.Recording recordingRow({bool structured = true, String? overrideNote}) =>
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
    );

/// A [RecordingRepository] stand-in for widget tests that need real delete behaviour
/// (an item leaving the list, a repeat delete being a no-op) without a real drift
/// database — a live `watch()` stream left dangling timers that flutter_test's teardown
/// invariants then tripped over.
class FakeRecordingRepository implements RecordingRepository {
  FakeRecordingRepository(List<db.Recording> initial)
      : _rows = List.of(initial),
        _controller = StreamController<List<db.Recording>>.broadcast();

  List<db.Recording> _rows;
  final StreamController<List<db.Recording>> _controller;
  final List<String> deletedIds = [];

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    _rows = _rows.where((r) => r.id != id).toList();
    _controller.add(List.unmodifiable(_rows));
  }

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

  @override
  Future<db.Recording?> byId(String id) async =>
      _rows.where((r) => r.id == id).firstOrNull;

  @override
  Future<String> createRecording({
    required String path,
    required Duration duration,
    required String transcriptionProviderId,
    required String structuringProviderId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> saveTranscript(String recordingId, Transcript transcript) =>
      throw UnimplementedError();

  @override
  Future<void> saveNote(String recordingId, StructureOutcome outcome) =>
      throw UnimplementedError();

  @override
  Future<void> updateNote(String recordingId, NoteDocument document) =>
      throw UnimplementedError();
}
