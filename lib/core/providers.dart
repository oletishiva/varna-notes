import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import '../features/papers/logic/renewals_logic.dart';
import '../features/sync/data/sync_controller.dart';
import '../features/sync/logic/sync_status.dart';
import 'clock.dart';
import 'data/attachment_store.dart';
import 'data/attachment_store_factory.dart';
import 'data/notes_repository.dart';
import 'data/settings_repository.dart';
import 'models/models.dart';
import 'services/ai_service.dart';
import 'services/entitlements.dart';
import 'services/ocr_service.dart';
import 'services/ocr_service_factory.dart';
import 'services/reminder_service.dart';
import 'services/reminder_service_factory.dart';
import 'services/usage_limits.dart';

// Re-exported so `main.dart` and tests only need this one import.
export 'data/database_opener.dart' show openAppDatabase;
export 'data/memory_database.dart' show openInMemoryDatabase;

// ---------------------------------------------------------------- foundation

/// The open sembast database. There is no default: override it before use.
///
/// ```dart
/// final db = await openAppDatabase();            // or openInMemoryDatabase()
/// runApp(ProviderScope(
///   overrides: [databaseProvider.overrideWithValue(db)],
///   child: const VarnaApp(),
/// ));
/// ```
final databaseProvider = Provider<Database>(
  (ref) => throw UnimplementedError(
    'databaseProvider must be overridden with an open Database '
    '(openAppDatabase() in the app, openInMemoryDatabase() in tests).',
  ),
);

/// "Now". Override in tests with a fixed or controllable clock.
final clockProvider = Provider<Clock>((ref) => systemClock);

// ------------------------------------------------------------------- storage

final attachmentStoreProvider =
    Provider<AttachmentStore>(
  (ref) => createAttachmentStore(ref.watch(databaseProvider)),
);

final notesRepositoryProvider =
    Provider<NotesRepository>((ref) {
  final NotesRepository repository = NotesRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
    attachments: ref.watch(attachmentStoreProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final settingsRepositoryProvider =
    Provider<SettingsRepository>(
  (ref) => SettingsRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// All settings and this month's usage; emits on every change.
final settingsProvider =
    StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

// ------------------------------------------------------------------ services

final ocrServiceProvider =
    Provider<OcrService>((ref) => createOcrService());

final reminderServiceProvider =
    Provider<ReminderService>((ref) => createReminderService());

/// v1: always the unconfigured service (`isConfigured == false`).
final aiServiceProvider =
    Provider<AiService>((ref) => const UnconfiguredAiService());

final entitlementsProvider = Provider<Entitlements>(
  (ref) => DebugToggleEntitlements(ref.watch(settingsRepositoryProvider)),
);

/// True when the user has Plus; emits on change.
final isPlusProvider = StreamProvider<bool>(
  (ref) => ref.watch(entitlementsProvider).watchIsPlus(),
);

final usageLimitsProvider = Provider<UsageLimits>(
  (ref) => UsageLimits(
    notes: ref.watch(notesRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    entitlements: ref.watch(entitlementsProvider),
  ),
);

// ---------------------------------------------------------------------- sync

/// How cloud stores are created. Override in tests with a factory that
/// returns a `MemoryCloudStore`.
final cloudStoreFactoryProvider =
    Provider<CloudStoreFactory>((ref) => defaultCloudStoreFactory);

/// The sync controller. Creating it also calls `init()` (restores the saved
/// connection).
final syncControllerProvider =
    Provider<SyncController>((ref) {
  final SyncController controller = SyncController(
    repository: ref.watch(notesRepositoryProvider),
    attachments: ref.watch(attachmentStoreProvider),
    settings: ref.watch(settingsRepositoryProvider),
    storeFactory: ref.watch(cloudStoreFactoryProvider),
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(controller.dispose);
  unawaited(controller.init().catchError((Object _) {}));
  return controller;
});

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncControllerProvider).watchStatus(),
);

final conflictsProvider =
    StreamProvider<List<SyncConflict>>(
  (ref) => ref.watch(syncControllerProvider).watchConflicts(),
);

/// One conflict by notebook/card id (null when none).
final conflictProvider =
    FutureProvider.autoDispose.family<SyncConflict?, String>(
  (ref, id) => ref.watch(syncControllerProvider).getConflict(id),
);

// --------------------------------------------------------------------- notes

/// Live notebooks (createdAt ascending).
final notebooksProvider =
    StreamProvider<List<Notebook>>(
  (ref) => ref.watch(notesRepositoryProvider).watchNotebooks(),
);

final notebookProvider =
    StreamProvider.autoDispose.family<Notebook?, String>(
  (ref, id) => ref.watch(notesRepositoryProvider).watchNotebook(id),
);

/// Cards of a notebook (newest change first), keyed by notebook id.
final cardsProvider =
    StreamProvider.autoDispose.family<List<NoteCard>, String>(
  (ref, notebookId) =>
      ref.watch(notesRepositoryProvider).watchCards(notebookId),
);

/// One card by id (null when missing or deleted).
final cardProvider =
    StreamProvider.autoDispose.family<NoteCard?, String>(
  (ref, id) => ref.watch(notesRepositoryProvider).watchCard(id),
);

final favouritesProvider =
    StreamProvider<List<NoteCard>>(
  (ref) => ref.watch(notesRepositoryProvider).watchFavourites(),
);

/// Cards that have an expiry date, soonest first.
final renewalCardsProvider =
    StreamProvider<List<NoteCard>>(
  (ref) => ref.watch(notesRepositoryProvider).watchUpcomingRenewals(),
);

/// Renewal rows with labels, built from [renewalCardsProvider] and the clock.
final renewalItemsProvider =
    Provider<AsyncValue<List<RenewalItem>>>((ref) {
  final Clock clock = ref.watch(clockProvider);
  return ref.watch(renewalCardsProvider).whenData(
        (List<NoteCard> cards) => RenewalsLogic.upcoming(cards, clock()),
      );
});

/// Arguments of [searchProvider].
class SearchQuery {
  const SearchQuery(this.text, {this.type});

  final String text;
  final CardType? type;

  @override
  bool operator ==(Object other) =>
      other is SearchQuery && other.text == text && other.type == type;

  @override
  int get hashCode => Object.hash(text, type);
}

/// Search results for a query; re-run by watching with a new [SearchQuery].
final searchProvider =
    FutureProvider.autoDispose.family<List<SearchHit>, SearchQuery>(
  (ref, query) =>
      ref.watch(notesRepositoryProvider).search(query.text, type: query.type),
);
