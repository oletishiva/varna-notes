import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:varna/core/models/model_utils.dart';
import 'package:varna/core/models/models.dart';

NoteCard fullCard() {
  return NoteCard(
    id: 'c1',
    notebookId: 'n1',
    type: CardType.scan,
    title: 'Car insurance',
    body: 'Policy with ACME',
    colorIndex: 3,
    items: const <ChecklistItem>[
      ChecklistItem(id: 'i1', text: 'Call agent', done: true),
      ChecklistItem(id: 'i2', text: 'Pay premium'),
    ],
    attachments: const <Attachment>[
      Attachment(
        id: 'a1',
        kind: AttachmentKind.image,
        fileName: 'scan.jpg',
        byteLength: 2048,
      ),
      Attachment(
        id: 'a2',
        kind: AttachmentKind.audio,
        fileName: 'memo.m4a',
        byteLength: 4096,
        durationMs: 12500,
      ),
    ],
    ocrText: 'EXPIRY 18/10/2026',
    transcript: 'remember to renew',
    favourite: true,
    reminderAt: DateTime.utc(2026, 10, 11, 4, 30, 15, 123),
    expiryDate: DateTime.utc(2026, 10, 18),
    paperFolder: 'Insurance',
    createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7),
    updatedAt: DateTime.utc(2026, 10, 12, 10, 30),
  );
}

NoteCard roundTrip(NoteCard card) {
  final String text = jsonEncode(card.toJson());
  return NoteCard.fromJson(asStringMap(jsonDecode(text)));
}

void main() {
  group('Notebook', () {
    test('JSON round-trip keeps every field', () {
      final Notebook nb = Notebook(
        id: 'n1',
        title: 'Home',
        colorIndex: 2,
        locked: true,
        createdAt: DateTime.utc(2026, 1, 1, 8),
        updatedAt: DateTime.utc(2026, 2, 3, 9, 10, 11, 12),
        deleted: true,
      );
      final Notebook back = Notebook.fromJson(
        asStringMap(jsonDecode(jsonEncode(nb.toJson()))),
      );
      expect(back, nb);
      expect(back.hashCode, nb.hashCode);
    });

    test('writes UTC ISO-8601 times', () {
      final Notebook nb = Notebook(
        id: 'n1',
        title: 'Home',
        createdAt: DateTime.utc(2026, 1, 1, 8),
        updatedAt: DateTime.utc(2026, 1, 1, 8),
      );
      // 2026-01-01 08:00:00 UTC is written with a trailing Z.
      expect(nb.toJson()['createdAt'], '2026-01-01T08:00:00.000Z');
    });

    test('fromJson applies defaults for missing optional fields', () {
      final Notebook nb = Notebook.fromJson(<String, Object?>{
        'id': 'n1',
        'createdAt': '2026-01-01T08:00:00.000Z',
        'updatedAt': '2026-01-01T08:00:00.000Z',
      });
      expect(nb.title, '');
      expect(nb.colorIndex, 0);
      expect(nb.locked, isFalse);
      expect(nb.deleted, isFalse);
    });

    test('copyWith changes only the given fields', () {
      final Notebook nb = Notebook(
        id: 'n1',
        title: 'Home',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final Notebook next = nb.copyWith(title: 'Work', locked: true);
      expect(next.title, 'Work');
      expect(next.locked, isTrue);
      expect(next.id, 'n1');
      expect(nb.title, 'Home');
    });
  });

  group('NoteCard', () {
    test('JSON round-trip keeps every field', () {
      final NoteCard card = fullCard();
      final NoteCard back = roundTrip(card);
      expect(back, card);
      expect(back.hashCode, card.hashCode);
      expect(back.items.length, 2);
      expect(back.attachments[1].durationMs, 12500);
      expect(back.expiryDate, DateTime.utc(2026, 10, 18));
    });

    test('expiry date is written as a plain calendar date', () {
      expect(fullCard().toJson()['expiryDate'], '2026-10-18');
    });

    test('JSON round-trip with all nullable fields empty', () {
      final NoteCard card = NoteCard(
        id: 'c2',
        notebookId: 'n1',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final NoteCard back = roundTrip(card);
      expect(back, card);
      expect(back.ocrText, isNull);
      expect(back.reminderAt, isNull);
      expect(back.expiryDate, isNull);
      expect(back.paperFolder, isNull);
      expect(back.type, CardType.text);
    });

    test('copyWith keeps nullable fields unless null is passed', () {
      final NoteCard card = fullCard();
      expect(card.copyWith(title: 'x').ocrText, 'EXPIRY 18/10/2026');
      expect(card.copyWith(ocrText: null).ocrText, isNull);
      expect(card.copyWith(expiryDate: null).expiryDate, isNull);
      expect(card.copyWith(reminderAt: null).reminderAt, isNull);
      expect(card.copyWith(paperFolder: null).paperFolder, isNull);
      expect(card.copyWith(transcript: null).transcript, isNull);
      final DateTime later = DateTime.utc(2027, 3, 4);
      expect(card.copyWith(expiryDate: later).expiryDate, later);
    });

    test('equality compares lists by value', () {
      expect(fullCard(), fullCard());
      expect(
        fullCard().copyWith(
          items: const <ChecklistItem>[ChecklistItem(id: 'i1', text: 'other')],
        ),
        isNot(fullCard()),
      );
    });

    test('doneCount counts completed items', () {
      expect(fullCard().doneCount, 1);
    });

    test('unknown card type falls back to text', () {
      expect(CardType.fromName('hologram'), CardType.text);
      expect(CardType.fromName(null), CardType.text);
      expect(CardType.fromName('voice'), CardType.voice);
    });
  });

  group('Attachment and ChecklistItem', () {
    test('Attachment round-trips', () {
      const Attachment a = Attachment(
        id: 'a2',
        kind: AttachmentKind.audio,
        fileName: 'memo.m4a',
        byteLength: 10,
        durationMs: 99,
      );
      expect(Attachment.fromJson(asStringMap(jsonDecode(jsonEncode(a.toJson())))), a);
      expect(a.copyWith(durationMs: null).durationMs, isNull);
      expect(a.copyWith(fileName: 'x').durationMs, 99);
    });

    test('ChecklistItem round-trips', () {
      const ChecklistItem i = ChecklistItem(id: 'i', text: 'milk', done: true);
      expect(
        ChecklistItem.fromJson(asStringMap(jsonDecode(jsonEncode(i.toJson())))),
        i,
      );
      expect(i.copyWith(done: false).done, isFalse);
    });
  });

  group('Sync models', () {
    test('SyncState round-trips', () {
      final SyncState s = SyncState(
        key: 'card_c1',
        lastSyncedLocalUpdatedAt: DateTime.utc(2026, 10, 12, 1, 2, 3),
        lastSyncedRemoteModified: DateTime.utc(2026, 10, 12, 1, 2, 4),
        lastSyncedRemoteEtag: 'v7',
      );
      final SyncState back =
          SyncState.fromJson(asStringMap(jsonDecode(jsonEncode(s.toJson()))));
      expect(back, s);
    });

    test('SyncRecord file names', () {
      final NoteCard card = fullCard();
      final SyncRecord r = SyncRecord.fromCard(card);
      expect(r.key, 'card_c1');
      expect(r.fileName, 'card_c1.json');
      final ({RecordKind kind, String id})? parsed =
          SyncRecord.parseFileName('card_c1.json');
      expect(parsed?.kind, RecordKind.card);
      expect(parsed?.id, 'c1');
      expect(SyncRecord.parseFileName('nb_abc-123.json')?.kind,
          RecordKind.notebook);
      expect(SyncRecord.parseFileName('att_a1.bin'), isNull);
      expect(SyncRecord.parseFileName('manifest.json'), isNull);
    });

    test('contentEquals ignores updatedAt but not content', () {
      final NoteCard card = fullCard();
      final SyncRecord a = SyncRecord.fromCard(card);
      final SyncRecord b = SyncRecord.fromCard(
        card.copyWith(updatedAt: DateTime.utc(2030)),
      );
      final SyncRecord c = SyncRecord.fromCard(card.copyWith(title: 'other'));
      expect(a.contentEquals(b), isTrue);
      expect(a.contentEquals(c), isFalse);
    });

    test('two tombstones are always equal', () {
      final NoteCard dead = NoteCard(
        id: 'c1',
        notebookId: 'n1',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        deleted: true,
      );
      final SyncRecord a = SyncRecord.fromCard(dead);
      final SyncRecord b = SyncRecord.fromCard(dead.copyWith(title: 'x'));
      expect(a.contentEquals(b), isTrue);
      expect(a.contentEquals(SyncRecord.fromCard(fullCard())), isFalse);
    });

    test('SyncConflict round-trips and exposes typed views', () {
      final NoteCard local = fullCard();
      final NoteCard remote = local.copyWith(title: 'Remote title');
      final SyncConflict c = SyncConflict(
        kind: RecordKind.card,
        id: 'c1',
        local: local.toJson(),
        remote: remote.toJson(),
        detectedAt: DateTime.utc(2026, 10, 12, 11),
        remoteModified: DateTime.utc(2026, 10, 12, 10, 59),
        remoteEtag: 'v3',
      );
      final SyncConflict back = SyncConflict.fromJson(
        asStringMap(jsonDecode(jsonEncode(c.toJson()))),
      );
      expect(back, c);
      expect(back.key, 'card_c1');
      expect(back.localTitle, 'Car insurance');
      expect(back.remoteTitle, 'Remote title');
      expect(back.remoteCard.title, 'Remote title');
      expect(back.localDeleted, isFalse);
    });

    test('canonicalJson ignores key order', () {
      expect(
        canonicalJson(<String, Object?>{'b': 1, 'a': <String, Object?>{'y': 2, 'x': 1}}),
        canonicalJson(<String, Object?>{'a': <String, Object?>{'x': 1, 'y': 2}, 'b': 1}),
      );
    });

    test('SyncProviderId parses names', () {
      expect(SyncProviderId.fromName('icloud'), SyncProviderId.icloud);
      expect(SyncProviderId.fromName('nope'), isNull);
      expect(SyncProviderId.googleDrive.displayName, 'Google Drive');
    });
  });
}
