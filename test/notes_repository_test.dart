import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:varna/core/data/attachment_store.dart';
import 'package:varna/core/data/memory_database.dart';
import 'package:varna/core/data/notes_repository.dart';
import 'package:varna/core/models/models.dart';

import 'support/test_support.dart';

void main() {
  late Database db;
  late TestClock clock;
  late MemoryAttachmentStore attachments;
  late NotesRepository repo;

  setUp(() async {
    db = await openInMemoryDatabase();
    clock = TestClock();
    attachments = MemoryAttachmentStore();
    repo = NotesRepository(db, clock: clock.call, attachments: attachments);
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  group('notebooks', () {
    test('create, get and list', () async {
      final Notebook nb =
          await repo.createNotebook(title: 'Home', colorIndex: 2, locked: true);
      expect(nb.title, 'Home');
      expect(nb.colorIndex, 2);
      expect(nb.locked, isTrue);
      expect(nb.createdAt, clock());
      expect(nb.updatedAt, clock());
      expect(await repo.getNotebook(nb.id), nb);
      expect((await repo.listNotebooks()).single, nb);
      expect(await repo.countNotebooks(), 1);
    });

    test('are listed oldest first', () async {
      final Notebook a = await repo.createNotebook(title: 'A');
      clock.advance();
      final Notebook b = await repo.createNotebook(title: 'B');
      clock.advance();
      final Notebook c = await repo.createNotebook(title: 'C');
      final List<Notebook> list = await repo.listNotebooks();
      expect(list.map((Notebook n) => n.id), <String>[a.id, b.id, c.id]);
    });

    test('update bumps updatedAt, keeps createdAt, and always increases', () async {
      final Notebook nb = await repo.createNotebook(title: 'Home');
      // The clock has not moved: updatedAt must still go up by 1 ms.
      final Notebook u1 = await repo.updateNotebook(nb.copyWith(title: 'House'));
      expect(u1.title, 'House');
      expect(u1.createdAt, nb.createdAt);
      expect(u1.updatedAt, nb.updatedAt.add(const Duration(milliseconds: 1)));
      final Notebook u2 = await repo.updateNotebook(u1.copyWith(locked: true));
      expect(u2.updatedAt.isAfter(u1.updatedAt), isTrue);
      clock.advance(const Duration(hours: 1));
      final Notebook u3 = await repo.updateNotebook(u2.copyWith(title: 'X'));
      expect(u3.updatedAt, clock());
    });

    test('delete is soft, cascades to cards and blanks content', () async {
      final Notebook nb = await repo.createNotebook(title: 'Home');
      final Notebook other = await repo.createNotebook(title: 'Other');
      await repo.createCard(notebookId: nb.id, type: CardType.text, title: 'a');
      await repo.createCard(notebookId: nb.id, type: CardType.text, title: 'b');
      final NoteCard keep = await repo.createCard(
        notebookId: other.id,
        type: CardType.text,
        title: 'c',
      );
      clock.advance();
      await repo.deleteNotebook(nb.id);

      expect(await repo.getNotebook(nb.id), isNull);
      expect((await repo.listNotebooks()).single.id, other.id);
      expect(await repo.listCards(nb.id), isEmpty);
      expect((await repo.listCards(other.id)).single, keep);

      final List<SyncRecord> all = await repo.allSyncRecords();
      expect(all.length, 5);
      final SyncRecord tomb = all.firstWhere((SyncRecord r) => r.id == nb.id);
      expect(tomb.deleted, isTrue);
      expect(tomb.json['title'], '');
      expect(tomb.updatedAt, clock());
      expect(all.where((SyncRecord r) => r.deleted).length, 3);
    });
  });

  group('cards', () {
    test('create, get, update and soft delete', () async {
      final Notebook nb = await repo.createNotebook(title: 'Home');
      final NoteCard card = await repo.createCard(
        notebookId: nb.id,
        type: CardType.checklist,
        title: 'Shopping',
        items: const <ChecklistItem>[ChecklistItem(id: 'i1', text: 'milk')],
        expiryDate: DateTime.utc(2026, 12, 1),
        paperFolder: 'Bills',
      );
      expect(card.type, CardType.checklist);
      expect(await repo.getCard(card.id), card);

      clock.advance();
      final NoteCard updated = await repo.updateCard(
        card.copyWith(title: 'Groceries', favourite: true),
      );
      expect(updated.title, 'Groceries');
      expect(updated.createdAt, card.createdAt);
      expect(updated.updatedAt, clock());
      expect(await repo.getCard(card.id), updated);

      await repo.deleteCard(card.id);
      expect(await repo.getCard(card.id), isNull);
      expect(await repo.listCards(nb.id), isEmpty);
      final SyncRecord tomb = (await repo.allSyncRecords())
          .firstWhere((SyncRecord r) => r.id == card.id);
      expect(tomb.deleted, isTrue);
      expect(tomb.json['title'], '');
      expect(tomb.json['items'], isEmpty);
    });

    test('deleting a card removes its attachment bytes', () async {
      final Notebook nb = await repo.createNotebook(title: 'Home');
      await attachments.save('att1', _bytes(<int>[1, 2, 3]));
      final NoteCard card = await repo.createCard(
        notebookId: nb.id,
        type: CardType.photo,
        attachments: const <Attachment>[
          Attachment(
            id: 'att1',
            kind: AttachmentKind.image,
            fileName: 'p.jpg',
            byteLength: 3,
          ),
        ],
      );
      expect(await attachments.exists('att1'), isTrue);
      await repo.deleteCard(card.id);
      expect(await attachments.exists('att1'), isFalse);
    });

    test('cards of a notebook are listed newest change first', () async {
      final Notebook nb = await repo.createNotebook(title: 'Home');
      final NoteCard a =
          await repo.createCard(notebookId: nb.id, type: CardType.text, title: 'a');
      clock.advance();
      final NoteCard b =
          await repo.createCard(notebookId: nb.id, type: CardType.text, title: 'b');
      clock.advance();
      await repo.updateCard(a.copyWith(title: 'a2'));
      final List<NoteCard> list = await repo.listCards(nb.id);
      expect(list.map((NoteCard c) => c.id), <String>[a.id, b.id]);
    });

    test('favourites and upcoming renewals', () async {
      final Notebook nb = await repo.createNotebook(title: 'Papers');
      await repo.createCard(notebookId: nb.id, type: CardType.text, title: 'plain');
      final NoteCard fav = await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'fav',
        favourite: true,
      );
      final NoteCard later = await repo.createCard(
        notebookId: nb.id,
        type: CardType.scan,
        title: 'late',
        expiryDate: DateTime.utc(2027, 5, 1),
      );
      final NoteCard soon = await repo.createCard(
        notebookId: nb.id,
        type: CardType.scan,
        title: 'soon',
        expiryDate: DateTime.utc(2026, 11, 1),
      );
      expect((await repo.listFavourites()).single.id, fav.id);
      expect((await repo.watchFavourites().first).single.id, fav.id);
      final List<NoteCard> renewals = await repo.listUpcomingRenewals();
      expect(renewals.map((NoteCard c) => c.id), <String>[soon.id, later.id]);
      final List<NoteCard> watched = await repo.watchUpcomingRenewals().first;
      expect(watched.map((NoteCard c) => c.id), <String>[soon.id, later.id]);
      await repo.deleteCard(soon.id);
      expect((await repo.listUpcomingRenewals()).single.id, later.id);
    });
  });

  group('watch streams', () {
    test('watchNotebooks emits the current list, then changes', () async {
      final List<List<Notebook>> emissions = <List<Notebook>>[];
      final sub = repo.watchNotebooks().listen(emissions.add);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);
      final Notebook nb = await repo.createNotebook(title: 'Home');
      await pumpEventQueue();
      expect(emissions.last.single, nb);
      await repo.deleteNotebook(nb.id);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);
      await sub.cancel();
    });

    test('watchCards only reports the given notebook', () async {
      final Notebook a = await repo.createNotebook(title: 'A');
      final Notebook b = await repo.createNotebook(title: 'B');
      final List<List<NoteCard>> emissions = <List<NoteCard>>[];
      final sub = repo.watchCards(a.id).listen(emissions.add);
      await pumpEventQueue();
      await repo.createCard(notebookId: b.id, type: CardType.text, title: 'in b');
      final NoteCard inA =
          await repo.createCard(notebookId: a.id, type: CardType.text, title: 'in a');
      await pumpEventQueue();
      expect(emissions.last.map((NoteCard c) => c.id), <String>[inA.id]);
      await sub.cancel();
    });

    test('watchCard reports updates and null after delete', () async {
      final Notebook nb = await repo.createNotebook(title: 'A');
      final NoteCard card =
          await repo.createCard(notebookId: nb.id, type: CardType.text, title: 'one');
      final List<NoteCard?> emissions = <NoteCard?>[];
      final sub = repo.watchCard(card.id).listen(emissions.add);
      await pumpEventQueue();
      expect(emissions.last?.title, 'one');
      await repo.updateCard(card.copyWith(title: 'two'));
      await pumpEventQueue();
      expect(emissions.last?.title, 'two');
      await repo.deleteCard(card.id);
      await pumpEventQueue();
      expect(emissions.last, isNull);
      await sub.cancel();
    });

    test('changes fires for local writes only', () async {
      int fired = 0;
      final sub = repo.changes.listen((_) => fired++);
      final Notebook nb = await repo.createNotebook(title: 'A');
      await repo.createCard(notebookId: nb.id, type: CardType.text);
      await pumpEventQueue();
      expect(fired, 2);
      final SyncRecord r = (await repo.allSyncRecords()).first;
      await repo.applyRemoteRecord(r);
      await pumpEventQueue();
      expect(fired, 2);
      await sub.cancel();
    });
  });

  group('dirty tracking', () {
    test('a record is dirty until its sync state matches updatedAt', () async {
      final Notebook nb = await repo.createNotebook(title: 'A');
      expect(await repo.countUnsynced(), 1);

      await repo.putSyncState(SyncState(
        key: 'nb_${nb.id}',
        lastSyncedLocalUpdatedAt: nb.updatedAt,
        lastSyncedRemoteModified: clock(),
      ));
      expect(await repo.countUnsynced(), 0);

      await repo.updateNotebook(nb.copyWith(title: 'B'));
      expect(await repo.countUnsynced(), 1);
    });

    test('applyRemoteRecord does not bump updatedAt', () async {
      final DateTime stamp = DateTime.utc(2020, 5, 5, 5);
      final Notebook remote = Notebook(
        id: 'remote-1',
        title: 'From cloud',
        createdAt: stamp,
        updatedAt: stamp,
      );
      await repo.applyRemoteRecord(SyncRecord.fromNotebook(remote));
      expect(await repo.getNotebook('remote-1'), remote);
    });

    test('touchRecord and duplicateRecord', () async {
      final Notebook nb = await repo.createNotebook(title: 'A');
      final NoteCard card = await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Milk',
      );
      clock.advance();
      final SyncRecord? touched = await repo.touchRecord(RecordKind.card, card.id);
      expect(touched?.updatedAt, clock());
      expect(touched?.json['title'], 'Milk');
      expect(await repo.touchRecord(RecordKind.card, 'missing'), isNull);

      final String copyId = await repo.duplicateRecord(touched!);
      final NoteCard? copy = await repo.getCard(copyId);
      expect(copy?.title, 'Milk (copy)');
      expect(copyId, isNot(card.id));
    });
  });

  group('search', () {
    late Notebook nb;
    late NoteCard grocery;
    late NoteCard checklist;
    late NoteCard policy;
    late NoteCard voice;

    setUp(() async {
      nb = await repo.createNotebook(title: 'Everything');
      grocery = await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Grocery list',
        body: 'milk, eggs',
      );
      clock.advance();
      checklist = await repo.createCard(
        notebookId: nb.id,
        type: CardType.checklist,
        title: 'Errands',
        items: const <ChecklistItem>[
          ChecklistItem(id: 'a', text: 'Buy Milk'),
          ChecklistItem(id: 'b', text: 'Call Anil'),
        ],
      );
      clock.advance();
      policy = await repo.createCard(
        notebookId: nb.id,
        type: CardType.scan,
        title: 'Car policy',
        ocrText: 'POLICY NUMBER 12345 expiry 18/10/2026',
      );
      clock.advance();
      voice = await repo.createCard(
        notebookId: nb.id,
        type: CardType.voice,
        title: 'Memo',
        transcript: 'remember to renew the INSURANCE',
      );
      final NoteCard gone = await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        body: 'milk in a deleted card',
      );
      await repo.deleteCard(gone.id);
    });

    test('is case-insensitive and reports where it matched', () async {
      final List<SearchHit> hits = await repo.search('MILK');
      // Body matches rank before checklist-item matches.
      expect(hits.map((SearchHit h) => h.card.id),
          <String>[grocery.id, checklist.id]);
      expect(hits[0].matchedIn, SearchField.body);
      expect(hits[0].snippet, 'milk, eggs');
      expect(hits[1].matchedIn, SearchField.items);
      // Snippet keeps the original casing and joins lines.
      expect(hits[1].snippet, 'Buy Milk Call Anil');
    });

    test('finds OCR text and transcripts', () async {
      final List<SearchHit> ocr = await repo.search('number 12345');
      expect(ocr.single.card.id, policy.id);
      expect(ocr.single.matchedIn, SearchField.ocrText);
      expect(ocr.single.snippet, 'POLICY NUMBER 12345 expiry 18/10/2026');

      final List<SearchHit> spoken = await repo.search('insurance');
      expect(spoken.single.card.id, voice.id);
      expect(spoken.single.matchedIn, SearchField.transcript);
      expect(spoken.single.snippet, 'remember to renew the INSURANCE');
    });

    test('title matches rank first and list every matching field', () async {
      final NoteCard both = await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Milk run',
        body: 'oat milk',
      );
      final List<SearchHit> hits = await repo.search('milk');
      expect(hits.first.card.id, both.id);
      expect(hits.first.matchedIn, SearchField.title);
      expect(hits.first.matchedFields,
          <SearchField>[SearchField.title, SearchField.body]);
      expect(hits.first.snippet, 'Milk run');
    });

    test('type filter, empty query, no match and limit', () async {
      final List<SearchHit> onlyLists =
          await repo.search('milk', type: CardType.checklist);
      expect(onlyLists.single.card.id, checklist.id);
      expect(await repo.search('   '), isEmpty);
      expect(await repo.search('zzz-not-there'), isEmpty);
      expect((await repo.search('milk', limit: 1)).length, 1);
    });

    test('every word must be present', () async {
      expect((await repo.search('milk anil')).single.card.id, checklist.id);
      expect(await repo.search('milk insurance'), isEmpty);
    });

    test('long text is cut with ellipses around the match', () async {
      final String body = '${'x' * 100} needle ${'y' * 100}';
      await repo.createCard(notebookId: nb.id, type: CardType.text, body: body);
      final SearchHit hit = (await repo.search('needle')).single;
      expect(hit.snippet.startsWith('...'), isTrue);
      expect(hit.snippet.endsWith('...'), isTrue);
      expect(hit.snippet.contains('needle'), isTrue);
      // 3 + 28 chars before + 6 + 72 chars after + 3 = 112 at most.
      expect(hit.snippet.length <= 112, isTrue);
    });

    test('works for Telugu text', () async {
      await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        body: 'పాలు కావాలి',
      );
      final List<SearchHit> hits = await repo.search('పాలు');
      expect(hits.single.snippet, 'పాలు కావాలి');
    });

    test('makeSnippet handles out-of-range indexes', () {
      expect(NotesRepository.makeSnippet('abc', 99, 2), 'abc');
      expect(NotesRepository.makeSnippet('', 0, 0), '');
    });
  });
}

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);
