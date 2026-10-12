import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varna/core/models/model_utils.dart';
import 'package:varna/core/models/models.dart';
import 'package:varna/features/sync/logic/cloud_store.dart';
import 'package:varna/features/sync/logic/memory_cloud_store.dart';
import 'package:varna/features/sync/logic/sync_status.dart';

import 'support/test_support.dart';

/// A store that is "available" but cannot list files.
class _BrokenListStore extends MemoryCloudStore {
  _BrokenListStore(TestClock clock) : super(clock: clock.call);

  @override
  Future<List<RemoteFile>> listFiles() {
    throw CloudException('boom');
  }
}

/// Runs [onDownload] once, just before the next download. Used to make a
/// local edit "while the sync is running".
class _HookStore extends MemoryCloudStore {
  _HookStore(TestClock clock) : super(clock: clock.call);

  Future<void> Function()? onDownload;

  @override
  Future<Uint8List> download(String name) async {
    final Future<void> Function()? hook = onDownload;
    onDownload = null;
    if (hook != null) {
      await hook();
    }
    return super.download(name);
  }
}

Map<String, Object?> cloudJson(MemoryCloudStore cloud, String name) {
  final Uint8List bytes = cloud.peek(name)!;
  return asStringMap(jsonDecode(utf8.decode(bytes)));
}

void main() {
  late TestClock clock;
  late MemoryCloudStore cloud;
  late Device a;
  late Device b;

  setUp(() async {
    clock = TestClock();
    cloud = MemoryCloudStore(clock: clock.call);
    a = await Device.create(cloud, clock);
    b = await Device.create(cloud, clock);
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  /// Device A creates a notebook with one card and syncs; device B syncs, so
  /// both hold the same data. Returns (notebook, card).
  Future<(Notebook, NoteCard)> seedBoth() async {
    final Notebook nb = await a.repo.createNotebook(title: 'Home');
    final NoteCard card = await a.repo.createCard(
      notebookId: nb.id,
      type: CardType.text,
      title: 'Milk',
      body: '2 litres',
    );
    clock.advance();
    await a.engine.sync();
    clock.advance();
    await b.engine.sync();
    clock.advance();
    return (nb, card);
  }

  group('only one side changed', () {
    test('local only: new records are uploaded once', () async {
      final Notebook nb = await a.repo.createNotebook(title: 'Home');
      final NoteCard card = await a.repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Milk',
      );

      final SyncReport first = await a.engine.sync();
      expect(first.uploaded, 2);
      expect(first.downloaded, 0);
      expect(first.conflicts, 0);
      expect(first.errors, isEmpty);
      expect(first.isOk, isTrue);
      expect(cloud.names, <String>['card_${card.id}.json', 'nb_${nb.id}.json']);
      expect(cloudJson(cloud, 'card_${card.id}.json')['title'], 'Milk');
      expect(await a.repo.countUnsynced(), 0);

      // Nothing changed: the second run does nothing at all.
      final SyncReport second = await a.engine.sync();
      expect(second.uploaded, 0);
      expect(second.downloaded, 0);
      expect(cloud.uploadLog.length, 2);
      expect(cloud.downloadLog, isEmpty);
    });

    test('local edit after a sync is uploaded', () async {
      final (Notebook nb, NoteCard card) = await seedBoth();
      await a.repo.updateCard(card.copyWith(title: 'Milk and eggs'));
      expect(await a.repo.countUnsynced(), 1);
      final SyncReport r = await a.engine.sync();
      expect(r.uploaded, 1);
      expect(r.downloaded, 0);
      expect(cloudJson(cloud, 'card_${card.id}.json')['title'], 'Milk and eggs');
      expect(nb.id, isNotEmpty);
    });

    test('remote only: a fresh device downloads everything', () async {
      final (Notebook nb, NoteCard card) = await seedBoth();
      final NoteCard? onB = await b.repo.getCard(card.id);
      expect(onB?.title, 'Milk');
      expect(onB?.body, '2 litres');
      expect((await b.repo.getNotebook(nb.id))?.title, 'Home');
      // Received records are not dirty.
      expect(await b.repo.countUnsynced(), 0);
    });

    test('remote edit is downloaded and applied', () async {
      final (Notebook nb, NoteCard card) = await seedBoth();
      await a.repo.updateCard(card.copyWith(title: 'Milk v2'));
      await a.engine.sync();
      clock.advance();

      final SyncReport r = await b.engine.sync();
      expect(r.downloaded, 1);
      expect(r.uploaded, 0);
      expect(r.conflicts, 0);
      expect((await b.repo.getCard(card.id))?.title, 'Milk v2');
      expect(await b.repo.countUnsynced(), 0);
      expect(nb.id, isNotEmpty);
    });

    test('neither side changed: skipped without downloading', () async {
      await seedBoth();
      cloud.downloadLog.clear();
      final SyncReport r = await b.engine.sync();
      expect(r.uploaded, 0);
      expect(r.downloaded, 0);
      expect(cloud.downloadLog, isEmpty);
    });

    test('files that are not records are ignored', () async {
      cloud.put('manifest.json', Uint8List.fromList(<int>[1]));
      cloud.put('readme.txt', Uint8List.fromList(<int>[2]));
      final SyncReport r = await a.engine.sync();
      expect(r.errors, isEmpty);
      expect(r.downloaded, 0);
    });
  });

  group('both sides changed', () {
    test('different content creates a conflict and overwrites nothing', () async {
      final (_, NoteCard card) = await seedBoth();

      await a.repo.updateCard(card.copyWith(title: 'From A'));
      await a.engine.sync();
      clock.advance();
      final NoteCard onB = (await b.repo.getCard(card.id))!;
      await b.repo.updateCard(onB.copyWith(title: 'From B'));
      clock.advance();
      cloud.uploadLog.clear();

      final SyncReport r = await b.engine.sync();
      expect(r.conflicts, 1);
      expect(r.uploaded, 0);
      expect(r.downloaded, 0);
      expect(cloud.uploadLog, isEmpty);

      // Local keeps B's text, the cloud keeps A's text.
      expect((await b.repo.getCard(card.id))?.title, 'From B');
      expect(cloudJson(cloud, 'card_${card.id}.json')['title'], 'From A');

      final List<SyncConflict> conflicts = await b.repo.listConflicts();
      expect(conflicts.length, 1);
      expect(conflicts.single.id, card.id);
      expect(conflicts.single.kind, RecordKind.card);
      expect(conflicts.single.localTitle, 'From B');
      expect(conflicts.single.remoteTitle, 'From A');
      expect(b.engine.status, const SyncConflicts(1));

      // Syncing again keeps the conflict and still changes nothing.
      final SyncReport again = await b.engine.sync();
      expect(again.conflicts, 1);
      expect(again.uploaded, 0);
      expect((await b.repo.getCard(card.id))?.title, 'From B');
    });

    test('identical content on both sides is not a conflict', () async {
      final (_, NoteCard card) = await seedBoth();

      await a.repo.updateCard(card.copyWith(title: 'Same'));
      await a.engine.sync();
      clock.advance();
      final NoteCard onB = (await b.repo.getCard(card.id))!;
      await b.repo.updateCard(onB.copyWith(title: 'Same'));
      clock.advance();

      final SyncReport r = await b.engine.sync();
      expect(r.conflicts, 0);
      expect(r.uploaded, 0);
      expect(r.downloaded, 0);
      expect(await b.repo.listConflicts(), isEmpty);
      // The state was brought up to date, so the record is clean.
      expect(await b.repo.countUnsynced(), 0);
      final SyncReport next = await b.engine.sync();
      expect(next.uploaded, 0);
      expect(next.downloaded, 0);
    });

    test('a stored conflict follows further remote changes', () async {
      final (_, NoteCard card) = await seedBoth();
      await a.repo.updateCard(card.copyWith(title: 'From A'));
      await a.engine.sync();
      clock.advance();
      final NoteCard onB = (await b.repo.getCard(card.id))!;
      await b.repo.updateCard(onB.copyWith(title: 'From B'));
      await b.engine.sync();
      expect((await b.repo.listConflicts()).single.remoteTitle, 'From A');

      clock.advance();
      final NoteCard onA = (await a.repo.getCard(card.id))!;
      await a.repo.updateCard(onA.copyWith(title: 'From A again'));
      await a.engine.sync();
      clock.advance();

      await b.engine.sync();
      final SyncConflict c = (await b.repo.listConflicts()).single;
      expect(c.remoteTitle, 'From A again');
      expect(c.localTitle, 'From B');
    });

    test('a conflict disappears when both sides converge', () async {
      final (_, NoteCard card) = await seedBoth();
      await a.repo.updateCard(card.copyWith(title: 'From A'));
      await a.engine.sync();
      clock.advance();
      final NoteCard onB = (await b.repo.getCard(card.id))!;
      await b.repo.updateCard(onB.copyWith(title: 'From B'));
      await b.engine.sync();
      expect(await b.repo.listConflicts(), hasLength(1));

      clock.advance();
      await b.repo.updateCard(onB.copyWith(title: 'From A'));
      final SyncReport r = await b.engine.sync();
      expect(r.conflicts, 0);
      expect(await b.repo.listConflicts(), isEmpty);
      expect(b.engine.status, isA<SyncSynced>());
    });
  });

  group('tombstones', () {
    test('a delete on device A reaches device B', () async {
      final (Notebook nb, NoteCard card) = await seedBoth();
      await a.repo.deleteCard(card.id);
      final SyncReport up = await a.engine.sync();
      expect(up.uploaded, 1);
      expect(cloudJson(cloud, 'card_${card.id}.json')['deleted'], isTrue);
      expect(cloudJson(cloud, 'card_${card.id}.json')['title'], '');
      clock.advance();

      final SyncReport down = await b.engine.sync();
      expect(down.downloaded, 1);
      expect(await b.repo.getCard(card.id), isNull);
      expect(await b.repo.listCards(nb.id), isEmpty);
      final SyncRecord tomb = (await b.repo.allSyncRecords())
          .firstWhere((SyncRecord r) => r.id == card.id);
      expect(tomb.deleted, isTrue);
    });

    test('a delete on device B reaches device A', () async {
      final (Notebook nb, NoteCard card) = await seedBoth();
      await b.repo.deleteNotebook(nb.id);
      await b.engine.sync();
      clock.advance();

      final SyncReport r = await a.engine.sync();
      expect(r.downloaded, 2); // the notebook and its card
      expect(await a.repo.getNotebook(nb.id), isNull);
      expect(await a.repo.getCard(card.id), isNull);
    });

    test('a tombstone for a record never seen locally is stored', () async {
      final (Notebook nb, NoteCard card) = await seedBoth();
      final Device c = await Device.create(cloud, clock);
      await a.repo.deleteCard(card.id);
      await a.engine.sync();
      clock.advance();
      final SyncReport r = await c.engine.sync();
      expect(r.errors, isEmpty);
      expect(await c.repo.getCard(card.id), isNull);
      expect((await c.repo.getNotebook(nb.id))?.title, 'Home');
      expect((await c.repo.allSyncRecords()).length, 2);
      await c.close();
    });

    test('delete on one side and edit on the other is a conflict', () async {
      final (_, NoteCard card) = await seedBoth();
      await a.repo.deleteCard(card.id);
      await a.engine.sync();
      clock.advance();
      final NoteCard onB = (await b.repo.getCard(card.id))!;
      await b.repo.updateCard(onB.copyWith(title: 'Edited on B'));
      clock.advance();

      final SyncReport r = await b.engine.sync();
      expect(r.conflicts, 1);
      final SyncConflict c = (await b.repo.listConflicts()).single;
      expect(c.remoteDeleted, isTrue);
      expect(c.localDeleted, isFalse);
      expect((await b.repo.getCard(card.id))?.title, 'Edited on B');
    });
  });

  group('resolving conflicts', () {
    late NoteCard card;

    /// B ends up with a conflict: B says "From B", the cloud says "From A".
    setUp(() async {
      final (_, NoteCard seeded) = await seedBoth();
      card = seeded;
      await a.repo.updateCard(card.copyWith(title: 'From A'));
      await a.engine.sync();
      clock.advance();
      final NoteCard onB = (await b.repo.getCard(card.id))!;
      await b.repo.updateCard(onB.copyWith(title: 'From B'));
      clock.advance();
      await b.engine.sync();
      clock.advance();
      expect(await b.repo.listConflicts(), hasLength(1));
    });

    test('keepLocal uploads the local version', () async {
      await b.engine.resolveConflict(card.id, ConflictResolution.keepLocal);
      expect(await b.repo.listConflicts(), isEmpty);
      expect(cloudJson(cloud, 'card_${card.id}.json')['title'], 'From B');
      expect(await b.repo.countUnsynced(), 0);
      expect(b.engine.status, isA<SyncSynced>());

      final SyncReport r = await a.engine.sync();
      expect(r.downloaded, 1);
      expect((await a.repo.getCard(card.id))?.title, 'From B');
    });

    test('keepRemote replaces the local version', () async {
      await b.engine.resolveConflict(card.id, ConflictResolution.keepRemote);
      expect(await b.repo.listConflicts(), isEmpty);
      expect((await b.repo.getCard(card.id))?.title, 'From A');
      expect(await b.repo.countUnsynced(), 0);
      expect(cloudJson(cloud, 'card_${card.id}.json')['title'], 'From A');

      cloud.uploadLog.clear();
      final SyncReport r = await b.engine.sync();
      expect(r.uploaded, 0);
      expect(r.downloaded, 0);
      expect(cloud.uploadLog, isEmpty);
    });

    test('keepBoth keeps the cloud version and saves the local one as a copy',
        () async {
      await b.engine.resolveConflict(card.id, ConflictResolution.keepBoth);
      expect(await b.repo.listConflicts(), isEmpty);

      final List<NoteCard> cards = await b.repo.listCards(card.notebookId);
      expect(cards.length, 2);
      expect(cards.firstWhere((NoteCard c) => c.id == card.id).title, 'From A');
      final NoteCard copy = cards.firstWhere((NoteCard c) => c.id != card.id);
      expect(copy.title, 'From B (copy)');
      expect(copy.body, '2 litres');

      // The copy is new and uploads on the next sync.
      expect(await b.repo.countUnsynced(), 1);
      final SyncReport r = await b.engine.sync();
      expect(r.uploaded, 1);
      expect(cloud.contains('card_${copy.id}.json'), isTrue);
      expect(cloud.names.length, 3);

      await a.engine.sync();
      expect((await a.repo.listCards(card.notebookId)).length, 2);
    });

    test('resolving an unknown id does nothing', () async {
      await b.engine.resolveConflict('nope', ConflictResolution.keepLocal);
      expect(await b.repo.listConflicts(), hasLength(1));
    });
  });

  test('keepBoth after delete-vs-edit keeps the edit as a copy', () async {
    final (_, NoteCard card) = await seedBoth();
    await a.repo.deleteCard(card.id);
    await a.engine.sync();
    clock.advance();
    final NoteCard onB = (await b.repo.getCard(card.id))!;
    await b.repo.updateCard(onB.copyWith(title: 'Edited on B'));
    clock.advance();
    await b.engine.sync();

    await b.engine.resolveConflict(card.id, ConflictResolution.keepBoth);
    final List<NoteCard> cards = await b.repo.listCards(card.notebookId);
    expect(cards.single.title, 'Edited on B (copy)');
    expect(await b.repo.getCard(card.id), isNull);
  });

  group('errors', () {
    test('a failing file is collected, the rest still syncs', () async {
      final Notebook nb = await a.repo.createNotebook(title: 'Home');
      final NoteCard bad = await a.repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'bad',
      );
      final NoteCard good = await a.repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'good',
      );
      cloud.failUploadFor.add('card_${bad.id}.json');

      final SyncReport r = await a.engine.sync();
      expect(r.errors.length, 1);
      expect(r.errors.single.name, 'card_${bad.id}.json');
      expect(r.errors.single.message, contains('upload failed'));
      expect(r.uploaded, 2);
      expect(r.isOk, isFalse);
      expect(cloud.contains('card_${good.id}.json'), isTrue);
      expect(cloud.contains('card_${bad.id}.json'), isFalse);
      expect(a.engine.status, isA<SyncError>());

      cloud.failUploadFor.clear();
      final SyncReport retry = await a.engine.sync();
      expect(retry.errors, isEmpty);
      expect(retry.uploaded, 1);
      expect(a.engine.status, isA<SyncSynced>());
    });

    test('a failing download is collected', () async {
      final (_, NoteCard card) = await seedBoth();
      await a.repo.updateCard(card.copyWith(title: 'v2'));
      await a.engine.sync();
      clock.advance();
      cloud.failDownloadFor.add('card_${card.id}.json');

      final SyncReport r = await b.engine.sync();
      expect(r.errors.single.name, 'card_${card.id}.json');
      expect(r.downloaded, 0);
      expect((await b.repo.getCard(card.id))?.title, 'Milk');
    });

    test('a corrupt remote file is reported, not thrown', () async {
      cloud.put('card_broken.json', Uint8List.fromList(utf8.encode('{not json')));
      final SyncReport r = await a.engine.sync();
      expect(r.errors.single.name, 'card_broken.json');
    });

    test('a remote file whose id does not match its name is rejected', () async {
      final Notebook nb = await a.repo.createNotebook(title: 'Home');
      final NoteCard card = await a.repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
      );
      cloud.put(
        'card_other.json',
        Uint8List.fromList(utf8.encode(jsonEncode(card.toJson()))),
      );
      final SyncReport r = await b.engine.sync();
      expect(r.errors.single.name, 'card_other.json');
    });

    test('offline: reports it and changes nothing', () async {
      await a.repo.createNotebook(title: 'Home');
      cloud.offline = true;
      final SyncReport r = await a.engine.sync();
      expect(r.offline, isTrue);
      expect(r.uploaded, 0);
      expect(r.isOk, isFalse);
      expect(a.engine.status, const SyncOffline());
      expect(await a.repo.countUnsynced(), 1);

      cloud.offline = false;
      final SyncReport back = await a.engine.sync();
      expect(back.uploaded, 1);
      expect(a.engine.status, isA<SyncSynced>());
    });

    test('signed out store counts as offline', () async {
      cloud.available = false;
      final SyncReport r = await a.engine.sync();
      expect(r.offline, isTrue);
    });

    test('listing failure aborts the run with an error status', () async {
      final _BrokenListStore broken = _BrokenListStore(clock);
      final Device d = await Device.create(broken, clock);
      await d.repo.createNotebook(title: 'x');
      final SyncReport r = await d.engine.sync();
      expect(r.aborted, isTrue);
      expect(r.errors.single.name, '(list)');
      expect(d.engine.status, const SyncError('boom'));
      await d.close();
    });
  });

  group('provider switch', () {
    test('pushes everything to the new store and makes it active', () async {
      final Notebook nb = await a.repo.createNotebook(title: 'Home');
      final NoteCard card = await a.repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Milk',
      );
      await a.engine.sync();
      clock.advance();

      final MemoryCloudStore second =
          MemoryCloudStore(clock: clock.call, displayName: 'Second');
      final SyncReport r = await a.engine.switchProvider(second);
      expect(r.uploaded, 2);
      expect(r.isOk, isTrue);
      expect(identical(a.engine.store, second), isTrue);
      expect(second.names, <String>['card_${card.id}.json', 'nb_${nb.id}.json']);

      // Later syncs go to the new store and find nothing to do.
      final SyncReport next = await a.engine.sync();
      expect(next.uploaded, 0);
      expect(next.downloaded, 0);
      await a.repo.updateCard(card.copyWith(title: 'Milk 2'));
      await a.engine.sync();
      expect(cloudJson(second, 'card_${card.id}.json')['title'], 'Milk 2');
      expect(cloudJson(cloud, 'card_${card.id}.json')['title'], 'Milk');
    });

    test('an unavailable new store changes nothing', () async {
      await a.repo.createNotebook(title: 'Home');
      await a.engine.sync();
      final MemoryCloudStore signedOut = MemoryCloudStore(clock: clock.call)
        ..available = false;
      final SyncReport r = await a.engine.switchProvider(signedOut);
      expect(r.aborted, isTrue);
      expect(identical(a.engine.store, cloud), isTrue);
      expect(signedOut.names, isEmpty);
    });

    test('a failing first sync rolls back to the old store and its state',
        () async {
      await a.repo.createNotebook(title: 'Home');
      await a.engine.sync();
      expect(await a.repo.countUnsynced(), 0);

      final SyncReport r = await a.engine.switchProvider(_BrokenListStore(clock));
      expect(r.aborted, isTrue);
      expect(identical(a.engine.store, cloud), isTrue);
      expect(await a.repo.countUnsynced(), 0);
      final SyncReport next = await a.engine.sync();
      expect(next.uploaded, 0);
    });

    test('differing records already in the new store become conflicts',
        () async {
      final (_, NoteCard card) = await seedBoth();
      final MemoryCloudStore second = MemoryCloudStore(clock: clock.call);

      await b.repo.updateCard(
        (await b.repo.getCard(card.id))!.copyWith(title: 'B edit'),
      );
      expect((await b.engine.switchProvider(second)).uploaded, 2);
      clock.advance();

      await a.repo.updateCard(card.copyWith(title: 'A edit'));
      final SyncReport r = await a.engine.switchProvider(second);
      // The notebook is identical on both; the card differs.
      expect(r.conflicts, 1);
      expect(r.uploaded, 0);
      final SyncConflict c = (await a.repo.listConflicts()).single;
      expect(c.id, card.id);
      expect(c.localTitle, 'A edit');
      expect(c.remoteTitle, 'B edit');
    });
  });

  group('attachments', () {
    final Uint8List photo = Uint8List.fromList(<int>[9, 8, 7, 6]);
    const Attachment meta = Attachment(
      id: 'photo-1',
      kind: AttachmentKind.image,
      fileName: 'photo.jpg',
      byteLength: 4,
    );

    test('blobs are uploaded and downloaded when media is included', () async {
      final Device withMedia =
          await Device.create(cloud, clock, includeMedia: true);
      final Device other = await Device.create(cloud, clock, includeMedia: true);
      final Notebook nb = await withMedia.repo.createNotebook(title: 'Pics');
      await withMedia.repo.createCard(
        notebookId: nb.id,
        type: CardType.photo,
        attachments: const <Attachment>[meta],
      );
      await withMedia.attachments.save('photo-1', photo);

      final SyncReport up = await withMedia.engine.sync();
      expect(up.mediaUploaded, 1);
      expect(cloud.contains('att_photo-1.bin'), isTrue);
      expect(cloud.peek('att_photo-1.bin'), photo);

      final SyncReport down = await other.engine.sync();
      expect(down.mediaDownloaded, 1);
      expect(await other.attachments.read('photo-1'), photo);

      // Nothing more to move.
      final SyncReport again = await other.engine.sync();
      expect(again.mediaUploaded, 0);
      expect(again.mediaDownloaded, 0);
      await withMedia.close();
      await other.close();
    });

    test('blobs stay local when media is excluded', () async {
      final Notebook nb = await a.repo.createNotebook(title: 'Pics');
      await a.repo.createCard(
        notebookId: nb.id,
        type: CardType.photo,
        attachments: const <Attachment>[meta],
      );
      await a.attachments.save('photo-1', photo);
      final SyncReport r = await a.engine.sync();
      expect(r.mediaUploaded, 0);
      expect(cloud.contains('att_photo-1.bin'), isFalse);
    });
  });

  group('races and reconnecting', () {
    test('a local edit made while the cloud copy downloads is kept', () async {
      final _HookStore hook = _HookStore(clock);
      final Device p = await Device.create(hook, clock);
      final Device q = await Device.create(hook, clock);
      addTearDown(p.close);
      addTearDown(q.close);

      final Notebook nb = await p.repo.createNotebook(title: 'Home');
      final NoteCard card = await p.repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Milk',
      );
      clock.advance();
      await p.engine.sync();
      clock.advance();
      await q.engine.sync();
      clock.advance();

      // Only the cloud copy changes (through the other device) ...
      final NoteCard onQ = (await q.repo.getCard(card.id))!;
      await q.repo.updateCard(onQ.copyWith(title: 'From Q'));
      await q.engine.sync();
      clock.advance();

      // ... but the user types on p while p is downloading it.
      hook.onDownload = () async {
        final NoteCard current = (await p.repo.getCard(card.id))!;
        await p.repo.updateCard(current.copyWith(title: 'Typed meanwhile'));
      };
      final SyncReport r = await p.engine.sync();

      expect(r.downloaded, 0);
      expect(r.conflicts, 1);
      expect((await p.repo.getCard(card.id))?.title, 'Typed meanwhile');
      final List<SyncConflict> conflicts = await p.repo.listConflicts();
      expect(conflicts.single.localTitle, 'Typed meanwhile');
      expect(conflicts.single.remoteTitle, 'From Q');
    });

    test('no sync state and identical content is simply in sync', () async {
      final (_, NoteCard card) = await seedBoth();
      // What Disconnect followed by connecting again leaves behind.
      await b.repo.clearSyncStates();
      await b.repo.clearConflicts();
      expect(await b.repo.countUnsynced(), 2);
      cloud.uploadLog.clear();

      final SyncReport r = await b.engine.sync();
      expect(r.conflicts, 0);
      expect(r.uploaded, 0);
      expect(r.downloaded, 0);
      expect(cloud.uploadLog, isEmpty);
      expect(await b.repo.listConflicts(), isEmpty);
      expect(await b.repo.countUnsynced(), 0);
      expect((await b.repo.getCard(card.id))?.title, 'Milk');
    });

    test('no sync state and different content is still a conflict', () async {
      final (_, NoteCard card) = await seedBoth();
      final NoteCard onB = (await b.repo.getCard(card.id))!;
      await b.repo.updateCard(onB.copyWith(title: 'Changed on B'));
      await b.repo.clearSyncStates();
      await b.repo.clearConflicts();

      final SyncReport r = await b.engine.sync();
      expect(r.conflicts, 1);
      expect((await b.repo.getCard(card.id))?.title, 'Changed on B');
    });
  });

  group('status stream and concurrency', () {
    test('emits syncing then synced', () async {
      await a.repo.createNotebook(title: 'Home');
      expect(a.engine.status, const SyncIdle());
      final List<SyncStatus> seen = <SyncStatus>[];
      final StreamSubscription<SyncStatus> sub =
          a.engine.statusStream.listen(seen.add);
      await a.engine.sync();
      await Future<void>.delayed(Duration.zero);
      expect(seen.first, const SyncSyncing());
      expect(seen.last, SyncSynced(clock()));
      await sub.cancel();
    });

    test('overlapping sync calls share one run', () async {
      await a.repo.createNotebook(title: 'Home');
      final Future<SyncReport> first = a.engine.sync();
      final Future<SyncReport> second = a.engine.sync();
      expect(identical(first, second), isTrue);
      expect(a.engine.isSyncing, isTrue);
      final SyncReport r = await first;
      expect(r.uploaded, 1);
      expect(cloud.uploadLog.length, 1);
      expect(a.engine.isSyncing, isFalse);
    });
  });
}
