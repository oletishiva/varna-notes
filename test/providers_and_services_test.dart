import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:varna/app_config.dart';
import 'package:varna/core/data/attachment_store.dart';
import 'package:varna/core/models/models.dart';
import 'package:varna/core/providers.dart';
import 'package:varna/core/services/ai_service.dart';
import 'package:varna/core/services/ocr_service.dart';
import 'package:varna/core/services/reminder_service.dart';
import 'package:varna/core/theme/varna_colors.dart';
import 'package:varna/core/theme/varna_theme.dart';
import 'package:varna/features/papers/logic/renewals_logic.dart';
import 'package:varna/features/sync/logic/memory_cloud_store.dart';
import 'package:varna/features/sync/logic/sync_status.dart';

void main() {
  group('providers with an in-memory database', () {
    late Database db;
    late ProviderContainer container;

    setUp(() async {
      db = await openInMemoryDatabase();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          attachmentStoreProvider.overrideWithValue(MemoryAttachmentStore()),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 12, 9)),
          cloudStoreFactoryProvider.overrideWithValue(
            (SyncProviderId id) => MemoryCloudStore(),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('notebooks flow through the repository and the stream provider',
        () async {
      final repo = container.read(notesRepositoryProvider);
      expect(await container.read(notebooksProvider.future), isEmpty);
      final Notebook nb = await repo.createNotebook(title: 'Home');
      await pumpEventQueue();
      expect(container.read(notebooksProvider).value, <Notebook>[nb]);
    });

    test('family providers are keyed by id', () async {
      final repo = container.read(notesRepositoryProvider);
      final Notebook nb = await repo.createNotebook(title: 'Home');
      final NoteCard card = await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Milk',
      );
      // Auto-dispose providers need a listener to stay alive.
      final ProviderSubscription<AsyncValue<NoteCard?>> s1 =
          container.listen(cardProvider(card.id), (previous, next) {});
      final ProviderSubscription<AsyncValue<List<NoteCard>>> s2 =
          container.listen(cardsProvider(nb.id), (previous, next) {});
      final ProviderSubscription<AsyncValue<Notebook?>> s3 =
          container.listen(notebookProvider(nb.id), (previous, next) {});
      final NoteCard? loaded = await container.read(cardProvider(card.id).future);
      expect(loaded?.title, 'Milk');
      final List<NoteCard> cards =
          await container.read(cardsProvider(nb.id).future);
      expect(cards.single.id, card.id);
      final Notebook? book = await container.read(notebookProvider(nb.id).future);
      expect(book?.title, 'Home');
      s1.close();
      s2.close();
      s3.close();
    });

    test('search provider uses SearchQuery equality', () async {
      final repo = container.read(notesRepositoryProvider);
      final Notebook nb = await repo.createNotebook(title: 'Home');
      await repo.createCard(
        notebookId: nb.id,
        type: CardType.text,
        title: 'Milk',
      );
      final ProviderSubscription<AsyncValue<List<SearchHit>>> sub =
          container.listen(
        searchProvider(const SearchQuery('milk')),
        (previous, next) {},
      );
      final List<SearchHit> hits =
          await container.read(searchProvider(const SearchQuery('milk')).future);
      expect(hits.single.matchedIn, SearchField.title);
      sub.close();
      expect(const SearchQuery('a', type: CardType.scan),
          const SearchQuery('a', type: CardType.scan));
      expect(const SearchQuery('a'), isNot(const SearchQuery('b')));
    });

    test('renewal items are labelled with the injected clock', () async {
      final repo = container.read(notesRepositoryProvider);
      final Notebook nb = await repo.createNotebook(title: 'Papers');
      await repo.createCard(
        notebookId: nb.id,
        type: CardType.scan,
        title: 'Car insurance',
        expiryDate: DateTime.utc(2026, 10, 18),
        paperFolder: 'Insurance',
      );
      await container.read(renewalCardsProvider.future);
      final List<RenewalItem>? items = container.read(renewalItemsProvider).value;
      expect(items?.single.label, 'Due in 6 days');
      expect(items?.single.folder, 'Insurance');
    });

    test('settings, entitlements and limits are wired together', () async {
      final entitlements = container.read(entitlementsProvider);
      expect(await entitlements.isPlus(), isFalse);
      await entitlements.setDebugPlus(true);
      expect(await container.read(entitlementsProvider).isPlus(), isTrue);
      final limits = container.read(usageLimitsProvider);
      expect((await limits.canCreateNotebook()).limit, isNull);
      final settings = container.read(settingsRepositoryProvider);
      await settings.incrementScans();
      expect((await settings.getUsage()).monthKey, '2026-10');
    });

    test('services default to safe implementations', () {
      expect(container.read(aiServiceProvider).isConfigured, isFalse);
      // Desktop test hosts: OCR and reminders are unsupported there.
      expect(container.read(ocrServiceProvider).isSupported, isFalse);
      expect(container.read(reminderServiceProvider).isSupported, isFalse);
    });

    test('the sync controller starts disconnected', () async {
      final status = await container.read(syncStatusProvider.future);
      expect(status, isA<SyncIdle>());
      expect(container.read(syncControllerProvider).isConnected, isFalse);
    });
  });

  group('services', () {
    test('NoopOcrService refuses to recognise', () {
      const NoopOcrService ocr = NoopOcrService();
      expect(ocr.isSupported, isFalse);
      expect(() => ocr.recognizeFile('x.jpg'),
          throwsA(isA<OcrUnsupportedException>()));
      expect(const OcrResult('  \n').isEmpty, isTrue);
      expect(const OcrResult('hi').isEmpty, isFalse);
    });

    test('NoopReminderService does nothing', () async {
      const NoopReminderService svc = NoopReminderService();
      expect(svc.isSupported, isFalse);
      expect(await svc.requestPermission(), isFalse);
      await svc.schedule(cardId: 'c', title: 't', when: DateTime.utc(2030));
      await svc.cancel('c');
    });

    test('reminder ids are stable, positive and differ per card', () {
      // Hash: start 7; for each code unit h = h * 31 + unit.
      // 'a' (97): 7 * 31 + 97 = 314.
      expect(reminderNotificationId('a'), 314);
      // 'ab': 314 * 31 + 98 = 9832.
      expect(reminderNotificationId('ab'), 9832);
      expect(reminderNotificationId('card-1'), isNot(reminderNotificationId('card-2')));
      expect(reminderNotificationId('0a1b2c3d-1111-2222-3333-444455556666'),
          inInclusiveRange(0, 0x7FFFFFFF));
    });

    test('the unconfigured AI service never fakes results', () {
      const UnconfiguredAiService ai = UnconfiguredAiService();
      expect(ai.isConfigured, isFalse);
      expect(() => ai.transcribe(Uint8List(0)),
          throwsA(isA<AiNotConfiguredException>()));
      expect(() => ai.ask('why?', context: <String>['x']),
          throwsA(isA<AiNotConfiguredException>()));
    });
  });

  group('AppConfig', () {
    test('holds the agreed limits, prices and ids', () {
      expect(AppConfig.appName, 'Varna');
      expect(AppConfig.packageId, 'com.qavedik.varna');
      expect(AppConfig.iCloudContainerId, 'iCloud.com.qavedik.varna');
      expect(AppConfig.freeNotebookLimit, 5);
      expect(AppConfig.freeScansPerMonth, 10);
      expect(AppConfig.freeTranscriptsPerMonth, 5);
      expect(AppConfig.plusPrice, '₹299/year');
      expect(AppConfig.trialDays, 7);
      expect(AppConfig.paperFolders.last, 'Other');
    });
  });

  group('theme', () {
    test('card colours match the design tokens and wrap around', () {
      const VarnaColors c = VarnaColors.light;
      expect(c.cardColor(0), const Color(0xFFFFD45C));
      expect(c.cardColor(1), const Color(0xFFBFD6FF));
      expect(c.cardColor(2), const Color(0xFFBDE8CF));
      expect(c.cardColor(3), const Color(0xFFFFC2B0));
      expect(c.cardColor(4), const Color(0xFFD9CCFF));
      expect(c.cardColor(5), c.cardColor(0));
      expect(c.cardColor(-1), c.cardColor(4));
      expect(c.ground, const Color(0xFFF3F4F8));
      expect(c.ink, const Color(0xFF171A2E));
    });

    test('lerp and copyWith', () {
      const VarnaColors a = VarnaColors.light;
      final VarnaColors b = a.copyWith(ink: const Color(0xFF000000));
      expect(b.ink, const Color(0xFF000000));
      expect(b.ground, a.ground);
      expect(a.lerp(b, 0).ink, a.ink);
      expect(a.lerp(b, 1).ink, const Color(0xFF000000));
      expect(a.lerp(null, 0.5), a);
    });

    test('ThemeData is Material 3 and carries the extension', () {
      final ThemeData theme = VarnaTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.extension<VarnaColors>(), isNotNull);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F4F8));
      expect(theme.textTheme.titleLarge?.fontFamily, VarnaFonts.display);
      expect(theme.textTheme.bodyMedium?.fontFamily, VarnaFonts.body);
    });
  });
}
