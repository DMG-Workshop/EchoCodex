import 'package:test/test.dart';
import 'package:transcript_core/transcript_core.dart';

import 'fixtures.dart';

/// The merge that runs when no two partial documents fit one prompt — which on a local
/// server with an unstated context window is any recording past about half an hour.
///
/// Everything here is deterministic and offline, so these are the tests that say what a
/// merge *means*: what counts as the same task in two windows, what happens to the ids two
/// windows both chose, and what the finished document promises.
/// The items at [key], typed, so an assertion is not a dynamic call.
List<Map<String, dynamic>> itemsOf(Map<String, dynamic> doc, String key) =>
    (doc[key] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> only(Map<String, dynamic> doc, String key) =>
    itemsOf(doc, key).single;

Map<String, dynamic> metaOf(Map<String, dynamic> doc) =>
    doc['meta'] as Map<String, dynamic>;

void main() {
  /// A partial with only the fields a test is about, over a schema-valid base.
  Map<String, dynamic> partial({
    Map<String, dynamic>? meta,
    List<Map<String, dynamic>>? participants,
    List<Map<String, dynamic>>? sections,
    List<Map<String, dynamic>>? tasks,
    List<Map<String, dynamic>>? decisions,
    List<Map<String, dynamic>>? timelineAnchors,
    Object? keyConcepts = _unset,
  }) {
    final note = validNoteJson();
    if (meta != null) {
      note['meta'] = {...note['meta'] as Map<String, dynamic>, ...meta};
    }
    if (participants != null) note['participants'] = participants;
    if (sections != null) note['sections'] = sections;
    if (tasks != null) note['tasks'] = tasks;
    if (decisions != null) note['decisions'] = decisions;
    if (timelineAnchors != null) note['timelineAnchors'] = timelineAnchors;
    if (keyConcepts != _unset) note['keyConcepts'] = keyConcepts;
    return note;
  }

  Map<String, dynamic> task({
    required String id,
    required String title,
    String status = 'todo',
    String priority = 'medium',
    String dateBasis = 'absent',
    String? dueDate,
    String? assigneeId,
    String? detail,
    List<String> dependsOn = const [],
  }) =>
      {
        'id': id,
        'title': title,
        'detail': detail,
        'assigneeId': assigneeId,
        'assigneeRaw': null,
        'status': status,
        'priority': priority,
        'estimate': null,
        'startDate': null,
        'dueDate': dueDate,
        'dateBasis': dateBasis,
        'dependsOn': dependsOn,
        'epic': null,
        'sourceRef': {'startMs': 0, 'endMs': 1, 'quote': 'they said so'},
      };

  Map<String, dynamic> section(String heading, List<String> bullets) => {
        'heading': heading,
        'bullets': bullets,
        'sourceRef': {'startMs': 0, 'endMs': 1, 'quote': 'they said so'},
      };

  Map<String, dynamic> person(String id, String name,
          {List<String> aliases = const [], String? role}) =>
      {'id': id, 'displayName': name, 'aliases': aliases, 'role': role};

  group('stitching', () {
    test('nothing to stitch is a programming error, not an empty note', () {
      expect(() => stitchNoteDocuments(const []), throwsArgumentError);
    });

    test('one partial is itself', () {
      final only = validNoteJson();
      expect(stitchNoteDocuments([only]), same(only));
    });

    test('the result still validates against the note schema', () {
      final stitched = stitchNoteDocuments([
        partial(tasks: [task(id: 't1', title: 'First')]),
        partial(tasks: [task(id: 't1', title: 'Second')]),
      ]);

      expect(SchemaValidator(noteDocumentSchema).validate(stitched), isEmpty,
          reason: 'a merge produces the same shape it consumes');
    });

    test('sections stay in the order the recording produced them', () {
      final stitched = stitchNoteDocuments([
        partial(sections: [
          section('Opening', ['a'])
        ]),
        partial(sections: [
          section('Middle', ['b'])
        ]),
        partial(sections: [
          section('Close', ['c'])
        ]),
      ]);

      expect(
        itemsOf(stitched, 'sections').map((s) => s['heading']),
        orderedEquals(['Opening', 'Middle', 'Close']),
      );
    });

    test('one topic discussed twice is one section, not two', () {
      final stitched = stitchNoteDocuments([
        partial(sections: [
          section('Release planning', ['Cut is Friday.'])
        ]),
        partial(sections: [
          section('release planning!', ['Cut is Friday.', 'QA needs two days.'])
        ]),
      ]);

      final sections = itemsOf(stitched, 'sections');
      expect(sections, hasLength(1),
          reason: 'two sections with one heading reads as a glitch');
      expect(
          sections.first['bullets'], ['Cut is Friday.', 'QA needs two days.'],
          reason: 'the repeat is dropped, the new point is kept');
    });
  });

  group('identity across windows', () {
    test('two windows that numbered a different task t1 keep two tasks', () {
      final stitched = stitchNoteDocuments([
        partial(tasks: [task(id: 't1', title: 'Send the deck')]),
        partial(tasks: [task(id: 't1', title: 'Fix the build')]),
      ]);

      final tasks = itemsOf(stitched, 'tasks');
      expect(tasks, hasLength(2));
      expect(tasks.map((t) => t['id']).toSet(), hasLength(2),
          reason: 'two cards with one id is a duplicate key on the board');
    });

    test('a renamed task takes its dependencies with it', () {
      final stitched = stitchNoteDocuments([
        partial(tasks: [task(id: 't1', title: 'Ship the API')]),
        partial(tasks: [
          task(id: 't1', title: 'Write the client'),
          task(id: 't2', title: 'Announce it', dependsOn: ['t1']),
        ]),
      ]);

      final tasks = itemsOf(stitched, 'tasks');
      final client =
          tasks.firstWhere((t) => t['title'] == 'Write the client')['id'];
      final announce = tasks.firstWhere((t) => t['title'] == 'Announce it');
      expect(announce['dependsOn'], [client],
          reason:
              'it depended on its own window\'s t1, not the first window\'s');
    });

    test('one commitment made twice is one task', () {
      final stitched = stitchNoteDocuments([
        partial(tasks: [task(id: 't1', title: 'Send Priya the deck')]),
        partial(tasks: [task(id: 't7', title: 'send priya the deck.')]),
      ]);

      expect(stitched['tasks'], hasLength(1));
    });

    test('a task reported finished later is finished', () {
      final stitched = stitchNoteDocuments([
        partial(tasks: [task(id: 't1', title: 'Rotate the keys')]),
        partial(
            tasks: [task(id: 't1', title: 'Rotate the keys', status: 'done')]),
      ]);

      expect(only(stitched, 'tasks')['status'], 'done');
    });

    test('a task never walks backwards', () {
      final stitched = stitchNoteDocuments([
        partial(tasks: [
          task(
              id: 't1',
              title: 'Rotate the keys',
              status: 'done',
              priority: 'critical')
        ]),
        partial(tasks: [task(id: 't1', title: 'Rotate the keys')]),
      ]);

      final merged = only(stitched, 'tasks');
      expect(merged['status'], 'done');
      expect(merged['priority'], 'critical');
    });

    test('a date that was actually said beats one that was guessed', () {
      final stitched = stitchNoteDocuments([
        partial(tasks: [
          task(
              id: 't1',
              title: 'Land the migration',
              dateBasis: 'inferred',
              dueDate: '2026-09-30')
        ]),
        partial(tasks: [
          task(
              id: 't1',
              title: 'Land the migration',
              dateBasis: 'explicit',
              dueDate: '2026-09-18')
        ]),
      ]);

      final merged = (stitched['tasks'] as List).single as Map;
      expect(merged['dateBasis'], 'explicit');
      expect(merged['dueDate'], '2026-09-18');
    });

    test('a guess never overwrites what was said', () {
      final stitched = stitchNoteDocuments([
        partial(tasks: [
          task(
              id: 't1',
              title: 'Land the migration',
              dateBasis: 'explicit',
              dueDate: '2026-09-18')
        ]),
        partial(tasks: [
          task(
              id: 't1',
              title: 'Land the migration',
              dateBasis: 'inferred',
              dueDate: '2026-09-30')
        ]),
      ]);

      final merged = (stitched['tasks'] as List).single as Map;
      expect(merged['dateBasis'], 'explicit');
      expect(merged['dueDate'], '2026-09-18');
    });

    test('detail heard in one window survives a window that had none', () {
      final stitched = stitchNoteDocuments([
        partial(tasks: [task(id: 't1', title: 'Rotate the keys')]),
        partial(tasks: [
          task(id: 't1', title: 'Rotate the keys', detail: 'Before the audit.')
        ]),
      ]);

      expect(only(stitched, 'tasks')['detail'], 'Before the audit.');
    });
  });

  group('the roster', () {
    test('one person named in three windows is one participant', () {
      final stitched = stitchNoteDocuments([
        partial(participants: [person('p1', 'Sarah Chen')]),
        partial(participants: [person('p_sarah', 'sarah chen')]),
        partial(participants: [person('p2', 'Sarah Chen', role: 'PM')]),
      ]);

      final people = itemsOf(stitched, 'participants');
      expect(people, hasLength(1));
      expect(people.single['role'], 'PM',
          reason: 'a role stated in any window is stated');
    });

    test('every form a person was heard as is kept', () {
      final stitched = stitchNoteDocuments([
        partial(participants: [
          person('p1', 'Sarah', aliases: ['SPEAKER_02'])
        ]),
        partial(participants: [
          person('p1', 'Sarah', aliases: ['Sara'])
        ]),
      ]);

      expect(stitched['participants'], hasLength(1));
      expect(only(stitched, 'participants')['aliases'],
          containsAll(['SPEAKER_02', 'Sara']),
          reason: 'aliases are what let the next recording recognise them');
    });

    test('two different people who shared an id stay two people', () {
      final stitched = stitchNoteDocuments([
        partial(participants: [person('p1', 'Sarah')]),
        partial(participants: [person('p1', 'Tom')]),
      ]);

      expect(stitched['participants'], hasLength(2));
      expect(itemsOf(stitched, 'participants').map((p) => p['id']).toSet(),
          hasLength(2));
    });

    test('an assignee follows the participant whose id was renamed', () {
      final stitched = stitchNoteDocuments([
        partial(participants: [person('p1', 'Sarah')], tasks: const []),
        partial(
          participants: [person('p1', 'Tom')],
          tasks: [task(id: 't9', title: 'Draft the brief', assigneeId: 'p1')],
        ),
      ]);

      final tom = itemsOf(stitched, 'participants')
          .firstWhere((p) => p['displayName'] == 'Tom')['id'];
      expect(only(stitched, 'tasks')['assigneeId'], tom,
          reason: 'the brief is Tom\'s, and reassigning it to Sarah is a bug '
              'nobody would think to look for');
    });

    test('a decision follows its decider', () {
      final stitched = stitchNoteDocuments([
        partial(participants: [person('p1', 'Sarah')], decisions: const []),
        partial(
          participants: [person('p1', 'Tom')],
          decisions: [
            {
              'id': 'd1',
              'statement': 'Ship on the 18th.',
              'rationale': null,
              'decidedBy': 'p1',
              'sourceRef': {'startMs': 0, 'endMs': 1, 'quote': 'ship on the'},
            }
          ],
        ),
      ]);

      final tom = itemsOf(stitched, 'participants')
          .firstWhere((p) => p['displayName'] == 'Tom')['id'];
      expect(only(stitched, 'decisions')['decidedBy'], tom);
    });
  });

  group('the whole-recording fields', () {
    test('confidence is the lowest any window reported', () {
      final stitched = stitchNoteDocuments([
        partial(meta: {'extractionConfidence': 'high'}),
        partial(meta: {'extractionConfidence': 'low'}),
        partial(meta: {'extractionConfidence': 'medium'}),
      ]);

      expect(metaOf(stitched)['extractionConfidence'], 'low');
    });

    test('the recording type is what most windows said', () {
      final stitched = stitchNoteDocuments([
        partial(meta: {'recordingType': 'lecture'}),
        partial(meta: {'recordingType': 'meeting'}),
        partial(meta: {'recordingType': 'lecture'}),
      ]);

      expect(metaOf(stitched)['recordingType'], 'lecture',
          reason: 'one conversational stretch does not relabel a lecture');
    });

    test('the summary joins the sections, without repeating one', () {
      final stitched = stitchNoteDocuments([
        partial(meta: {'summary': 'Auth came up.'}),
        partial(meta: {'summary': 'Auth came up.'}),
        partial(meta: {'summary': 'Then launch dates.'}),
      ]);

      expect(metaOf(stitched)['summary'], 'Auth came up. Then launch dates.');
    });

    test('a milestone mentioned in every window is one milestone', () {
      final anchor = {
        'label': 'Launch',
        'date': '2026-10-01',
        'sourceRef': {'startMs': 0, 'endMs': 1, 'quote': 'launch is the'},
      };
      final stitched = stitchNoteDocuments([
        partial(timelineAnchors: [anchor]),
        partial(timelineAnchors: [anchor]),
      ]);

      expect(stitched['timelineAnchors'], hasLength(1));
    });

    test('study aids nobody asked for stay off', () {
      final stitched = stitchNoteDocuments([
        partial(keyConcepts: null),
        partial(keyConcepts: null),
      ]);

      expect((stitched)['keyConcepts'], isNull,
          reason: 'null is "not asked for"; [] would turn the study tab on');
    });

    test('study aids asked for and deduped', () {
      final stitched = stitchNoteDocuments([
        partial(keyConcepts: [
          {'term': 'OIDC', 'explanation': 'An identity layer over OAuth 2.'}
        ]),
        partial(keyConcepts: [
          {'term': 'oidc', 'explanation': 'An identity layer over OAuth 2.'},
          {'term': 'JWK', 'explanation': 'A JSON key.'},
        ]),
      ]);

      expect(itemsOf(stitched, 'keyConcepts').map((c) => c['term']),
          ['OIDC', 'JWK']);
    });
  });
}

/// Distinguishes "the test did not mention keyConcepts" from "the test passed null".
const Object _unset = Object();
