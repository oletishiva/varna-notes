# Core API reference

Everything the UI needs is exported from `lib/core/providers.dart` and
`lib/core/models/models.dart`. Signatures are copied from the code.
All times are `DateTime`; JSON uses UTC ISO-8601 (`expiryDate` is date-only).

## Providers (`lib/core/providers.dart`)

Foundation
```
databaseProvider            Provider<Database>            // MUST be overridden (openAppDatabase() / openInMemoryDatabase())
clockProvider               Provider<Clock>               // Clock = DateTime Function(); default systemClock
```
Storage
```
attachmentStoreProvider     Provider<AttachmentStore>
notesRepositoryProvider     Provider<NotesRepository>
settingsRepositoryProvider  Provider<SettingsRepository>
settingsProvider            StreamProvider<AppSettings>
```
Services
```
ocrServiceProvider          Provider<OcrService>          // NoopOcrService on web
reminderServiceProvider     Provider<ReminderService>     // NoopReminderService on web
aiServiceProvider           Provider<AiService>           // UnconfiguredAiService (isConfigured == false)
entitlementsProvider        Provider<Entitlements>        // DebugToggleEntitlements
isPlusProvider              StreamProvider<bool>
usageLimitsProvider         Provider<UsageLimits>
```
Sync
```
cloudStoreFactoryProvider   Provider<CloudStoreFactory>   // CloudStore Function(SyncProviderId); override in tests
isOnWifiProvider            Provider<Future<bool> Function()>   // defaultIsOnWifi
syncControllerProvider      Provider<SyncController>      // calls init() on creation
syncStatusProvider          StreamProvider<SyncStatus>
conflictsProvider           StreamProvider<List<SyncConflict>>
conflictProvider            FutureProvider.autoDispose.family<SyncConflict?, String>
```
Notes
```
notebooksProvider           StreamProvider<List<Notebook>>                       // createdAt ascending
notebookProvider            StreamProvider.autoDispose.family<Notebook?, String>
cardsProvider               StreamProvider.autoDispose.family<List<NoteCard>, String>   // key: notebookId; newest change first
cardProvider                StreamProvider.autoDispose.family<NoteCard?, String>
favouritesProvider          StreamProvider<List<NoteCard>>
renewalCardsProvider        StreamProvider<List<NoteCard>>                       // cards with expiryDate, soonest first
renewalItemsProvider        Provider<AsyncValue<List<RenewalItem>>>
searchProvider              FutureProvider.autoDispose.family<List<SearchHit>, SearchQuery>
```
Other exports: `openAppDatabase()`, `openInMemoryDatabase()`, `defaultIsOnWifi()`,
`class SearchQuery { const SearchQuery(String text, {CardType? type}) }` (value equality).

`defaultIsOnWifi`: true on web, true when wifi or ethernet is reported, false only when
mobile data is reported without wifi/ethernet, true if the probe throws.

## NotesRepository (`lib/core/data/notes_repository.dart`)

```
NotesRepository(Database db, {Clock? clock, Uuid? uuid, AttachmentStore? attachments})
Stream<void> get changes                       // fires after every local write
Future<void> dispose()
```
Notebooks
```
Stream<List<Notebook>> watchNotebooks()
Stream<Notebook?> watchNotebook(String id)
Future<List<Notebook>> listNotebooks()
Future<int> countNotebooks()
Future<Notebook?> getNotebook(String id)
Future<Notebook> createNotebook({required String title, int colorIndex = 0, bool locked = false})
Future<Notebook> updateNotebook(Notebook notebook)    // keeps createdAt, bumps updatedAt
Future<void> deleteNotebook(String id)                // soft delete incl. its cards (tombstones)
```
Cards
```
Stream<List<NoteCard>> watchCards(String notebookId)
Stream<List<NoteCard>> watchFavourites()
Stream<List<NoteCard>> watchUpcomingRenewals()
Stream<NoteCard?> watchCard(String id)
Future<List<NoteCard>> listCards(String notebookId)
Future<List<NoteCard>> listFavourites()
Future<List<NoteCard>> listUpcomingRenewals()
Future<List<NoteCard>> listAllCards()
Future<NoteCard?> getCard(String id)
Future<NoteCard> createCard({
  required String notebookId, required CardType type,
  String title = '', String body = '', int colorIndex = 0,
  List<ChecklistItem> items = const [], List<Attachment> attachments = const [],
  String? ocrText, String? transcript, bool favourite = false,
  DateTime? reminderAt, DateTime? expiryDate, String? paperFolder,
})
Future<NoteCard> updateCard(NoteCard card)            // use card.copyWith(...)
Future<void> deleteCard(String id)                    // soft delete, removes attachment bytes
```
Search
```
Future<List<SearchHit>> search(String query, {CardType? type, int limit = 100})
static String makeSnippet(String text, int index, int matchLength)
```
Sync support (used by SyncEngine / SyncController)
```
Future<List<SyncRecord>> allSyncRecords()             // incl. tombstones
Future<SyncRecord?> getSyncRecord(RecordKind kind, String id)
Future<void> applyRemoteRecord(SyncRecord record)     // no updatedAt bump, not dirty
Future<SyncRecord?> touchRecord(RecordKind kind, String id)
Future<String> duplicateRecord(SyncRecord record)     // returns new id, title "<title> (copy)"
Future<int> countUnsynced()
Future<SyncState?> getSyncState(String key)
Future<void> putSyncState(SyncState state)
Future<List<SyncState>> allSyncStates()
Future<void> clearSyncStates()
Future<void> replaceSyncStates(List<SyncState> states)
Future<List<SyncConflict>> listConflicts()
Stream<List<SyncConflict>> watchConflicts()
Future<SyncConflict?> getConflict(String id)
Future<void> putConflict(SyncConflict conflict)
Future<void> removeConflict(String id)
Future<void> clearConflicts()
```

## SettingsRepository (`lib/core/data/settings_repository.dart`)

```
SettingsRepository(Database db, {Clock? clock})
String currentMonthKey()
Future<AppSettings> load()
Stream<AppSettings> watch()
Future<SyncProviderId?> getSyncProvider()     Future<void> setSyncProvider(SyncProviderId? provider)
Future<bool> getWifiOnly()                    Future<void> setWifiOnly(bool value)
Future<bool> getIncludeMedia()                Future<void> setIncludeMedia(bool value)
Future<bool> getOnboardingDone()              Future<void> setOnboardingDone(bool value)
Future<bool> getPlusDebug()                   Future<void> setPlusDebug(bool value)
Future<DateTime?> getLastSyncAt()             Future<void> setLastSyncAt(DateTime? value)
Future<UsageSnapshot> getUsage()
Future<UsageSnapshot> incrementScans([int by = 1])
Future<UsageSnapshot> incrementTranscripts([int by = 1])
Future<void> resetUsage()
```

## SyncController (`lib/features/sync/data/sync_controller.dart`)

```
SyncController({
  required NotesRepository repository, required AttachmentStore attachments,
  required SettingsRepository settings, CloudStoreFactory? storeFactory, Clock? clock,
  Duration? autoSyncDelay = const Duration(seconds: 5), Future<bool> Function()? isOnWifi,
})
typedef CloudStoreFactory = CloudStore Function(SyncProviderId provider);

SyncStatus get status
Stream<SyncStatus> watchStatus()               // current value first, then changes
SyncProviderId? get activeProvider
bool get isConnected
String? get accountLabel
bool isProviderSupported(SyncProviderId provider)   // iCloud only on iOS/macOS
Future<int> pendingChanges()

Future<void> init({bool syncAfterRestore = false})   // restores saved connection; the provider calls it with true (one silent sync)
Future<SyncReport> syncNow({bool manual = true})     // never throws; honours Wi-Fi only via isOnWifi
Future<SyncReport?> onAppResumed()             // silent sync, at most once per resumeThrottle (60 s); null when skipped
Future<SyncReport> connect(SyncProviderId provider)   // never throws
Future<void> disconnect()                      // keeps local notes

Stream<List<SyncConflict>> watchConflicts()
Future<List<SyncConflict>> listConflicts()
Future<SyncConflict?> getConflict(String id)
Future<void> resolveConflict(String id, ConflictResolution resolution)  // throws StateError if not connected; CloudException if keepLocal cannot upload
Future<void> dispose()
```
Auto sync runs `autoSyncDelay` after the last local edit when a cloud is connected.
`syncNow` with Wi-Fi only on and the probe returning false sets `SyncOffline()` and
returns `SyncReport(offline: true)`.
When the store is not available (signed out), a manual `syncNow` tries `signIn()` once;
if that fails it sets `SyncError(kSignInAgainMessage)` and returns an aborted report.
`syncNow(manual: false)` (timer, launch, resume) never prompts and only sets that error.
Edits made while a sync runs cause exactly one follow-up sync afterwards.

### Sync types (`lib/features/sync/logic`)
```
sealed class SyncStatus: SyncIdle(), SyncSyncing(), SyncSynced(DateTime at),
  SyncOffline(), SyncError(String message), SyncConflicts(int count)
SyncFileError(String name, String message)
SyncReport({int uploaded = 0, int downloaded = 0, int conflicts = 0,
  List<SyncFileError> errors = const [], int mediaUploaded = 0, int mediaDownloaded = 0,
  bool offline = false, bool aborted = false});  bool get isOk
RemoteFile({required String name, required DateTime modified, String? etag})
abstract class CloudStore {
  String get displayName;  String? get accountLabel;
  Future<bool> isAvailable();  Future<bool> signIn();  Future<void> signOut();
  Future<List<RemoteFile>> listFiles();
  Future<Uint8List> download(String name);
  Future<RemoteFile> upload(String name, Uint8List bytes);
  Future<void> delete(String name);
}
CloudException(message) > CloudOfflineException, CloudAuthException
```
Implementations: `GoogleDriveStore` (scope drive.appdata), `ICloudStore` (iOS/macOS),
`MemoryCloudStore` (tests). Remote files: `nb_<id>.json`, `card_<id>.json`, `att_<id>.bin`.

## Services (`lib/core/services`)

```
abstract class OcrService { bool get isSupported; Future<OcrResult> recognizeFile(String imagePath); }
OcrResult(String text); bool get isEmpty        OcrUnsupportedException

abstract class ReminderService {
  bool get isSupported;  Future<bool> requestPermission();
  Future<void> schedule({required String cardId, required String title, String? body, required DateTime when});
  Future<void> cancel(String cardId);
}

abstract class AiService {
  bool get isConfigured;
  Future<String> transcribe(Uint8List audio, {String languageCode = 'en'});
  Future<String> ask(String question, {required List<String> context});
}   // AiNotConfiguredException when unconfigured

abstract class Entitlements {
  Future<bool> isPlus();  Stream<bool> watchIsPlus();
  bool get supportsDebugToggle;  Future<void> setDebugPlus(bool value);
}   // DebugToggleEntitlements(SettingsRepository), FixedEntitlements(plus)

UsageLimits({required NotesRepository notes, required SettingsRepository settings, required Entitlements entitlements})
Future<LimitCheck> canCreateNotebook()   Future<LimitCheck> canScan()   Future<LimitCheck> canTranscribe()
Future<UsageSnapshot> recordScan()       Future<UsageSnapshot> recordTranscript()
LimitCheck({required bool allowed, required int used, required int? limit, LimitReason? reason, String message = ''}); int? get remaining
enum LimitReason { notebookLimit, scanLimit, transcriptLimit }

abstract class AttachmentStore {
  Future<void> save(String id, Uint8List bytes);  Future<Uint8List?> read(String id);
  Future<bool> exists(String id);  Future<void> delete(String id);  Future<String?> localPath(String id);
}
```

## Papers (`lib/features/papers/logic`)

```
enum RenewalUrgency { overdue, soon, upcoming, later }
RenewalItem({required NoteCard card, required DateTime dueDate, required int daysLeft,
  required RenewalUrgency urgency, required String label, required String folder})
RenewalsLogic.folders                                  // = AppConfig.paperFolders
RenewalsLogic.normalizeFolder(String? folder) -> String
RenewalsLogic.daysUntil(DateTime expiry, DateTime now) -> int
RenewalsLogic.dueLabel(int daysLeft) -> String
RenewalsLogic.urgencyFor(int daysLeft) -> RenewalUrgency
RenewalsLogic.upcoming(Iterable<NoteCard> cards, DateTime now, {int? withinDays, bool includeOverdue = true}) -> List<RenewalItem>
RenewalsLogic.groupByFolder(Iterable<RenewalItem> items) -> Map<String, List<RenewalItem>>
```

## Models (`lib/core/models`)

Models are immutable. Most have `copyWith`, `toJson()` / `fromJson(Map<String, Object?>)` and
value equality (not SearchHit, SyncRecord). In `copyWith`, nullable fields use the `kUnset` sentinel so `null` can be passed.

```
Notebook { String id, String title, int colorIndex = 0, bool locked = false,
           DateTime createdAt, DateTime updatedAt, bool deleted = false }

NoteCard { String id, String notebookId, CardType type = text, String title = '', String body = '',
           int colorIndex = 0, List<ChecklistItem> items = [], List<Attachment> attachments = [],
           String? ocrText, String? transcript, bool favourite = false,
           DateTime? reminderAt, DateTime? expiryDate (date only), String? paperFolder,
           DateTime createdAt, DateTime updatedAt, bool deleted = false;  int get doneCount }

enum CardType { text, checklist, voice, photo, scan, link }       // CardType.fromName(String?)
ChecklistItem { String id, String text, bool done = false }
enum AttachmentKind { audio, image }
Attachment { String id, AttachmentKind kind, String fileName, int byteLength, int? durationMs }

AppSettings { SyncProviderId? syncProvider, bool wifiOnly = false, bool includeMedia = true,
              bool onboardingDone = false, bool plusDebug = false, DateTime? lastSyncAt, UsageSnapshot usage }
UsageSnapshot { String monthKey, int scans, int transcripts }

enum SearchField { title, body, items, ocrText, transcript }
SearchHit { NoteCard card, SearchField matchedIn, List<SearchField> matchedFields, String snippet }

enum SyncProviderId { googleDrive, icloud }     // displayName, SyncProviderId.fromName
enum ConflictResolution { keepLocal, keepRemote, keepBoth }
enum RecordKind { notebook, card }              // prefix: 'nb' | 'card'
SyncRecord { RecordKind kind, String id, DateTime updatedAt, bool deleted, Map<String, Object?> json }
  // fromNotebook, fromCard, fromJson(kind, json), key, fileName, keyFor, parseFileName, contentEquals
SyncState { String key, DateTime lastSyncedLocalUpdatedAt, DateTime? lastSyncedRemoteModified, String? lastSyncedRemoteEtag }
SyncConflict { RecordKind kind, String id, Map<String, Object?> local, Map<String, Object?> remote,
               DateTime detectedAt, DateTime? remoteModified, String? remoteEtag }
  // getters: key, localNotebook, remoteNotebook, localCard, remoteCard, localDeleted, remoteDeleted,
  //          localUpdatedAt, remoteUpdatedAt, localTitle, remoteTitle
```
Deletes are tombstones (`deleted: true`, content blanked) so they sync.
