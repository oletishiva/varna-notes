import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:varna/core/data/memory_database.dart';
import 'package:varna/core/data/notes_repository.dart';
import 'package:varna/core/models/models.dart';
import 'package:varna/features/cards/ui/widgets/card_actions.dart';
import 'package:varna/features/cards/ui/widgets/card_saver.dart';
import 'package:varna/features/papers/ui/renewal_actions.dart';

void main() {
  group('clampPickerDate', () {
    final DateTime first = DateTime(2000);
    final DateTime last = DateTime(2056, 12, 31);

    test('keeps a date that is inside the range', () {
      final DateTime inside = DateTime(2026, 10, 18);
      expect(clampPickerDate(inside, first, last), inside);
    });

    test('moves a too early date up to the first date', () {
      expect(clampPickerDate(DateTime(1995, 3, 4), first, last), first);
    });

    test('moves a too late date down to the last date', () {
      expect(clampPickerDate(DateTime(2099, 1, 1), first, last), last);
    });

    test('accepts the edges of the range', () {
      expect(clampPickerDate(first, first, last), first);
      expect(clampPickerDate(last, first, last), last);
    });
  });

  group('Autosaver', () {
    test('cancel drops pending edits, dispose then saves nothing', () async {
      int saves = 0;
      final Autosaver autosaver = Autosaver(
        onSave: () async {
          saves++;
        },
        delay: const Duration(milliseconds: 20),
      );
      autosaver.markChanged();
      expect(autosaver.hasPendingChanges, isTrue);
      expect(autosaver.status.value, SaveStatus.saving);

      autosaver.cancel();
      expect(autosaver.hasPendingChanges, isFalse);
      expect(autosaver.status.value, SaveStatus.saved);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(saves, 0);
      autosaver.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(saves, 0);
    });

    test('without cancel, dispose still saves pending edits', () async {
      int saves = 0;
      final Autosaver autosaver = Autosaver(
        onSave: () async {
          saves++;
        },
        delay: const Duration(seconds: 5),
      );
      autosaver.markChanged();
      autosaver.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(saves, 1);
    });
  });

  group('CardSaver.deleteIfEmpty', () {
    late Database db;
    late NotesRepository repo;
    late Notebook notebook;

    setUp(() async {
      db = await openInMemoryDatabase();
      repo = NotesRepository(db);
      notebook = await repo.createNotebook(title: 'Inbox');
    });

    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    test('deletes an empty text card', () async {
      final NoteCard card =
          await repo.createCard(notebookId: notebook.id, type: CardType.text);
      final CardSaver saver = CardSaver(repo, card.id);
      expect(await saver.deleteIfEmpty(isEmptyTextCard), isTrue);
      expect(await repo.getCard(card.id), isNull);
    });

    test('keeps a card that has a title', () async {
      final NoteCard card = await repo.createCard(
        notebookId: notebook.id,
        type: CardType.text,
        title: 'Plan',
      );
      final CardSaver saver = CardSaver(repo, card.id);
      expect(await saver.deleteIfEmpty(isEmptyTextCard), isFalse);
      expect(await repo.getCard(card.id), isNotNull);
    });

    test('an edit that is still queued is applied first', () async {
      final NoteCard card =
          await repo.createCard(notebookId: notebook.id, type: CardType.text);
      final CardSaver saver = CardSaver(repo, card.id);
      final Future<NoteCard?> edit =
          saver.update((NoteCard c) => c.copyWith(body: 'Typed just now'));
      final bool deleted = await saver.deleteIfEmpty(isEmptyTextCard);
      await edit;
      expect(deleted, isFalse);
      expect((await repo.getCard(card.id))?.body, 'Typed just now');
    });

    test('checklists: empty is deleted, with items is kept', () async {
      final NoteCard empty = await repo.createCard(
        notebookId: notebook.id,
        type: CardType.checklist,
      );
      final NoteCard filled = await repo.createCard(
        notebookId: notebook.id,
        type: CardType.checklist,
        items: const <ChecklistItem>[ChecklistItem(id: 'a', text: 'Milk')],
      );
      expect(
        await CardSaver(repo, empty.id).deleteIfEmpty(isEmptyChecklistCard),
        isTrue,
      );
      expect(
        await CardSaver(repo, filled.id).deleteIfEmpty(isEmptyChecklistCard),
        isFalse,
      );
      expect(await repo.getCard(empty.id), isNull);
      expect(await repo.getCard(filled.id), isNotNull);
    });

    test('a card with a reminder is not empty', () async {
      final NoteCard card = await repo.createCard(
        notebookId: notebook.id,
        type: CardType.text,
        reminderAt: DateTime.utc(2030),
      );
      expect(
        await CardSaver(repo, card.id).deleteIfEmpty(isEmptyTextCard),
        isFalse,
      );
    });

    test('a card that is already gone is left alone', () async {
      final NoteCard card =
          await repo.createCard(notebookId: notebook.id, type: CardType.text);
      await repo.deleteCard(card.id);
      expect(
        await CardSaver(repo, card.id).deleteIfEmpty(isEmptyTextCard),
        isFalse,
      );
    });
  });
}
