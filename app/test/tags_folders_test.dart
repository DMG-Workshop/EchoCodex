import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/data/database.dart';
import 'package:echo_codex_app/src/data/repository.dart';

/// Two ways to sort a library, against the real database rather than a stand-in,
/// because the behaviour worth testing here lives in SQL: a unique index on the
/// normalized name, cascades from both sides of the join, "every tag" rather than "any
/// tag", and a prefix rename that must not catch a folder whose name merely starts the
/// same way.
void main() {
  late TranscriptDatabase db;
  late RecordingRepository repository;

  setUp(() {
    db = TranscriptDatabase.forTesting(NativeDatabase.memory());
    repository = RecordingRepository(db);
  });

  tearDown(() => db.close());

  Future<void> addRecording(String id, {String? folder, int day = 1}) =>
      db.into(db.recordings).insert(RecordingsCompanion.insert(
            id: id,
            startedAt: DateTime.utc(2026, 10, day),
            folder: Value(folder),
          ));

  group('naming a tag', () {
    test('one spelling, however it was typed', () async {
      await addRecording('r1');
      await addRecording('r2');

      final first = await repository.tagRecording('r1', 'Work');
      final second = await repository.tagRecording('r2', '  work  ');

      expect(second.id, first.id,
          reason: 'a filter that splits across three spellings of one word makes '
              'the missing recordings look deleted');
      expect(await db.select(db.tags).get(), hasLength(1));
    });

    test('keeps the spelling it was first given', () async {
      await addRecording('r1');
      await addRecording('r2');

      await repository.tagRecording('r1', 'Hiring');
      await repository.tagRecording('r2', 'hiring');

      expect((await db.select(db.tags).get()).single.name, 'Hiring',
          reason: 'the display name is what someone chose, not what they last typed');
    });

    test('collapses inner whitespace too', () async {
      expect(RecordingRepository.normalizeTag('  Weekly   Standup '),
          'weekly standup');
    });

    test('a tag needs a name', () async {
      await addRecording('r1');
      expect(() => repository.tagRecording('r1', '   '), throwsArgumentError);
    });
  });

  group('tagging and untagging', () {
    test('a recording can carry several at once', () async {
      await addRecording('r1');
      await repository.tagRecording('r1', 'work');
      await repository.tagRecording('r1', 'weekly');

      final tags = await repository.watchTagsFor('r1').first;
      expect(tags.map((t) => t.name), ['weekly', 'work'],
          reason: 'alphabetical, so the chips do not reorder as they are added');
    });

    test('the same tag twice is still once', () async {
      await addRecording('r1');
      await repository.tagRecording('r1', 'work');
      await repository.tagRecording('r1', 'Work');

      expect(await repository.watchTagsFor('r1').first, hasLength(1));
    });

    test('removing it from one recording leaves it on the others', () async {
      await addRecording('r1');
      await addRecording('r2');
      final tag = await repository.tagRecording('r1', 'work');
      await repository.tagRecording('r2', 'work');

      await repository.untagRecording('r1', tag.id);

      expect(await repository.watchTagsFor('r1').first, isEmpty);
      expect(await repository.watchTagsFor('r2').first, hasLength(1));
      expect(await db.select(db.tags).get(), hasLength(1),
          reason: 'taking a tag off one recording must not delete the tag');
    });

    test('deleting a recording takes its tag rows with it', () async {
      await addRecording('r1');
      await repository.tagRecording('r1', 'work');

      await (db.delete(db.recordings)..where((r) => r.id.equals('r1'))).go();

      expect(await db.select(db.recordingTags).get(), isEmpty,
          reason: 'rows pointing at a recording that no longer exists would be '
              'counted by every tag filter');
    });

    test('deleting a tag takes it off everything', () async {
      await addRecording('r1');
      final tag = await repository.tagRecording('r1', 'work');

      await repository.deleteTag(tag.id);

      expect(await db.select(db.recordingTags).get(), isEmpty);
      expect(await repository.watchTagsFor('r1').first, isEmpty);
    });
  });

  group('the tag list', () {
    test('says how many recordings carry each', () async {
      await addRecording('r1');
      await addRecording('r2');
      await repository.tagRecording('r1', 'work');
      await repository.tagRecording('r2', 'work');
      await repository.tagRecording('r1', 'hiring');

      final tags = await repository.watchTags().first;

      expect(tags.map((t) => t.tag.name), ['hiring', 'work']);
      expect(tags.map((t) => t.count), [1, 2],
          reason: 'a filter row of forty tags is unreadable; the count is what '
              'says which ones are worth showing first');
    });

    test('a tag on nothing is still listed, at zero', () async {
      await repository.ensureTag('unused');

      final tags = await repository.watchTags().first;

      expect(tags.single.count, 0,
          reason: 'it exists and can be renamed or deleted, so hiding it would '
              'leave something unreachable');
    });
  });

  group('renaming a tag', () {
    test('keeps it on everything it was on', () async {
      await addRecording('r1');
      final tag = await repository.tagRecording('r1', 'wrk');

      await repository.renameTag(tag.id, 'Work');

      final tags = await repository.watchTagsFor('r1').first;
      expect(tags.single.name, 'Work');
      expect(tags.single.id, tag.id);
    });

    test('renaming onto an existing tag merges them', () async {
      await addRecording('r1');
      await addRecording('r2');
      final wrk = await repository.tagRecording('r1', 'wrk');
      final work = await repository.tagRecording('r2', 'work');

      final result = await repository.renameTag(wrk.id, 'Work');

      expect(result.id, work.id);
      expect(await db.select(db.tags).get(), hasLength(1),
          reason: 'the alternative is a unique-index failure the user cannot act on');
      expect((await repository.watchTagsFor('r1').first).single.id, work.id,
          reason: 'the recording follows its tag through the merge');
    });

    test('a merge survives a recording that already had both', () async {
      await addRecording('r1');
      final wrk = await repository.tagRecording('r1', 'wrk');
      await repository.tagRecording('r1', 'work');

      await repository.renameTag(wrk.id, 'work');

      expect(await repository.watchTagsFor('r1').first, hasLength(1),
          reason: 'both rows collapse to one rather than failing the primary key');
    });
  });

  group('the tag index', () {
    test('says which tags are on which recordings', () async {
      await addRecording('r1');
      await addRecording('r2');
      final work = await repository.tagRecording('r1', 'work');
      final hiring = await repository.tagRecording('r1', 'hiring');
      await repository.tagRecording('r2', 'work');

      final index = await repository.watchTagIndex().first;

      expect(index['r1'], {work.id, hiring.id});
      expect(index['r2'], {work.id});
      expect(index.containsKey('r3'), isFalse,
          reason: 'an untagged recording is absent rather than an empty set, so '
              'the filter asks one question instead of two');
    });

    test('a removed tag leaves the index', () async {
      await addRecording('r1');
      final work = await repository.tagRecording('r1', 'work');
      await repository.untagRecording('r1', work.id);

      expect(await repository.watchTagIndex().first, isEmpty);
    });
  });

  group('folders', () {
    test('are whatever recordings are filed in', () async {
      await addRecording('r1', folder: 'Work');
      await addRecording('r2', folder: 'Personal');
      await addRecording('r3');

      expect(await repository.watchFolders().first, ['Personal', 'Work'],
          reason: 'derived, so there is no empty folder to clean up and no '
              'second place for the truth to live');
    });

    test('filing and unfiling', () async {
      await addRecording('r1');

      await repository.setFolder('r1', '  Work/Standups  ');
      expect((await repository.byId('r1'))!.folder, 'Work/Standups');

      await repository.setFolder('r1', null);
      expect((await repository.byId('r1'))!.folder, isNull);
    });

    test('an empty name unfiles rather than creating a nameless folder',
        () async {
      await addRecording('r1', folder: 'Work');

      await repository.setFolder('r1', '   ');

      expect((await repository.byId('r1'))!.folder, isNull);
    });

    test('a rename takes the nested folders with it', () async {
      await addRecording('top', folder: 'Work');
      await addRecording('nested', folder: 'Work/Standups');

      final moved = await repository.renameFolder('Work', 'Clients');

      expect(moved, 2);
      expect((await repository.byId('top'))!.folder, 'Clients');
      expect((await repository.byId('nested'))!.folder, 'Clients/Standups');
    });

    test('a rename does not catch a folder that merely starts the same', () async {
      await addRecording('work', folder: 'Work');
      await addRecording('workshop', folder: 'Workshop');

      await repository.renameFolder('Work', 'Clients');

      expect((await repository.byId('workshop'))!.folder, 'Workshop',
          reason: 'the separator is what makes this a path rename and not a '
              'string replace');
    });

    test('a folder needs a name to be renamed to', () async {
      await addRecording('r1', folder: 'Work');
      expect(() => repository.renameFolder('Work', '  '), throwsArgumentError);
    });
  });
}
