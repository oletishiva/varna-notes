import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:varna/core/data/attachment_store.dart';
import 'package:varna/core/data/notes_repository.dart';
import 'package:varna/core/models/models.dart';
import 'package:varna/core/providers.dart';
import 'package:varna/core/theme/varna_theme.dart';
import 'package:varna/features/search/ui/search_screen.dart';

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('SearchScreen finds a card by a word in its body',
      (WidgetTester tester) async {
    late Database db;
    late NotesRepository repo;
    await tester.runAsync(() async {
      db = await openInMemoryDatabase();
      repo = NotesRepository(db);
      final Notebook nb = await repo.createNotebook(title: 'Travel plans');
      await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Hotel call',
        body: 'Check-in is at twelve. Keep the tickets ready at the desk.',
      );
      await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Groceries',
        body: 'Milk and bread.',
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
        ],
        child: MaterialApp(
          theme: VarnaTheme.light(),
          home: const SearchScreen(),
        ),
      ),
    );
    await settle(tester);

    // Nothing typed yet: the hint is shown.
    expect(find.text('Search your cards'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tickets');
    // Wait for the 250 ms debounce, then for the search to finish.
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(find.text('Hotel call'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
    expect(find.text('1 card'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}
