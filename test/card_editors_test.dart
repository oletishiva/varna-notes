import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:varna/core/data/attachment_store.dart';
import 'package:varna/core/data/notes_repository.dart';
import 'package:varna/core/models/models.dart';
import 'package:varna/core/providers.dart';
import 'package:varna/core/services/reminder_service.dart';
import 'package:varna/core/theme/varna_theme.dart';
import 'package:varna/features/cards/ui/checklist_card_screen.dart';
import 'package:varna/features/cards/ui/widgets/markdown_format.dart';

/// Lets real asynchronous work (the in-memory database) finish and the
/// widgets rebuild. Needed because `testWidgets` runs in a fake-async zone.
Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('ChecklistCardScreen', () {
    testWidgets('shows the items and a checkbox flips in the repository',
        (WidgetTester tester) async {
      late Database db;
      late NotesRepository repo;
      late NoteCard card;
      await tester.runAsync(() async {
        db = await openInMemoryDatabase();
        repo = NotesRepository(db);
        final Notebook nb = await repo.createNotebook(title: 'Travel plans');
        card = await repo.createCard(
          notebookId: nb.id,
          type: CardType.checklist,
          title: 'Packing',
          items: const <ChecklistItem>[
            ChecklistItem(id: 'a', text: 'Sunscreen'),
            ChecklistItem(id: 'b', text: 'Walking shoes'),
          ],
        );
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          await repo.dispose();
          await db.close();
        });
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            attachmentStoreProvider.overrideWithValue(MemoryAttachmentStore()),
            reminderServiceProvider.overrideWithValue(
              const NoopReminderService(),
            ),
          ],
          child: MaterialApp(
            theme: VarnaTheme.light(),
            home: ChecklistCardScreen(cardId: card.id),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Sunscreen'), findsOneWidget);
      expect(find.text('Walking shoes'), findsOneWidget);
      expect(find.text('0 of 2'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(2));

      await tester.tap(find.byType(Checkbox).first);
      await settle(tester);

      final NoteCard? stored =
          await tester.runAsync(() => repo.getCard(card.id));
      expect(stored, isNotNull);
      expect(
        stored!.items.firstWhere((ChecklistItem i) => i.id == 'a').done,
        isTrue,
      );
      expect(
        stored.items.firstWhere((ChecklistItem i) => i.id == 'b').done,
        isFalse,
      );
      expect(find.text('1 of 2'), findsOneWidget);

      // Take the screen down before the database is closed.
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });
  });

  group('Markdown helpers', () {
    test('toggleWrap wraps and unwraps the selection', () {
      const TextEditingValue start = TextEditingValue(
        text: 'Hello World',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      final TextEditingValue bold = toggleWrap(start, '**');
      expect(bold.text, 'Hello **World**');
      expect(bold.selection.start, 8);
      expect(bold.selection.end, 13);

      final TextEditingValue plain = toggleWrap(bold, '**');
      expect(plain.text, 'Hello World');
      expect(plain.selection.start, 6);
      expect(plain.selection.end, 11);
    });

    test('toggleWrap with a cursor inserts a marker pair around it', () {
      const TextEditingValue start = TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 1),
      );
      final TextEditingValue result = toggleWrap(start, '*');
      expect(result.text, 'a**b');
      expect(result.selection.baseOffset, 2);
      expect(result.selection.extentOffset, 2);
    });

    test('togglePrefix adds and removes a bullet on the current line', () {
      const TextEditingValue start = TextEditingValue(
        text: 'one\ntwo',
        selection: TextSelection.collapsed(offset: 5),
      );
      final TextEditingValue bulleted = togglePrefix(start, '- ');
      expect(bulleted.text, 'one\n- two');
      expect(bulleted.selection.baseOffset, 7);

      final TextEditingValue plain = togglePrefix(bulleted, '- ');
      expect(plain.text, 'one\ntwo');
      expect(plain.selection.baseOffset, 5);
    });

    test('togglePrefix handles a selection over several lines', () {
      const TextEditingValue start = TextEditingValue(
        text: 'a\nb',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
      );
      final TextEditingValue result = togglePrefix(start, '- ');
      expect(result.text, '- a\n- b');
    });
  });
}
