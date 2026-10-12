# Varna — build spec (v1)

Card-based notes app. Flutter, one codebase: Android, iOS, web. Offline-first; the user's
own Google Drive or iCloud is the only "server". Package id `com.qavedik.varna`.

IMPORTANT build constraint: Flutter/Dart is NOT installed in the authoring environment and
pub.dev is unreachable from the shell. Code is compiled only later, by GitHub Actions. So:
write conservative, well-known APIs; no code generation (no build_runner, freezed, drift,
riverpod_generator, json_serializable); hand-written `toJson/fromJson`; double-check every
import and every named parameter. Prefer fewer plugins. Check package versions/APIs with
WebFetch on pub.dev pages if unsure (the shell cannot reach pub.dev, WebFetch may).

## Stack
- flutter_riverpod (plain providers/Notifiers, no codegen), go_router, Material 3.
- Storage: `sembast` (+ `sembast_web` on web) for records; binary attachments (audio, images)
  as files under app documents dir on mobile (`path_provider`); on web attachments are kept
  as bytes in sembast (base64) — hide that behind `AttachmentStore`.
- Feature-first layout: `lib/features/<f>/{ui,logic,data}`. Pure-Dart logic in `logic/`
  (no flutter imports) with unit tests in `test/`.
- Name, tagline, ids, free limits and price live ONLY in `lib/app_config.dart`.
- Fonts bundled in `assets/fonts` (Bricolage Grotesque for display, Figtree for body,
  Noto Sans Telugu fallback). Never downloaded at runtime.
- No secrets, signing keys, OAuth client ids in the repo; read via `--dart-define`.

## Data model (lib/core/models)
- `Notebook { id, title, colorIndex, locked, createdAt, updatedAt, deleted }`
- `NoteCard { id, notebookId, type, title, body, colorIndex, items[], attachments[],
   ocrText, transcript, favourite, reminderAt, expiryDate, paperFolder, createdAt,
   updatedAt, deleted }`
  - `type`: text | checklist | voice | photo | scan | link
  - `items`: `ChecklistItem { id, text, done }`
  - `attachments`: `Attachment { id, kind(audio|image), fileName, bytes length, durationMs }`
  - `deleted` is a tombstone so deletes sync.
- Ids are UUID v4 strings. Times are UTC ISO-8601 in JSON.

## Repositories (lib/core/data)
- `NotesRepository`: watch/list notebooks, cards by notebook, favourites, upcoming renewals;
  create/update/soft-delete; `search(query, {type})` across title, body, checklist items,
  ocrText, transcript (case-insensitive, returns match snippet + where it matched).
  Every write bumps `updatedAt` and marks the record dirty for sync.
- `AttachmentStore`: save/read/delete bytes by attachment id.
- `SettingsRepository`: chosen sync provider, wifi-only, include-media, onboarding done,
  entitlement (debug toggle), monthly usage counters (scans, transcripts) with month reset.

## Sync (lib/features/sync)
- `CloudStore` interface (pure Dart): `listFiles() -> [RemoteFile{name, modified, etag}]`,
  `download(name) -> bytes`, `upload(name, bytes)`, `delete(name)`, `isAvailable()`,
  `signIn()`, `signOut()`, `accountLabel`.
  - `GoogleDriveStore`: `google_sign_in` + `googleapis` Drive v3, scope `drive.appdata`,
    files in `appDataFolder`. Works on Android, iOS, web.
  - `ICloudStore`: `icloud_storage` plugin, container id from app_config; iOS/macOS only.
    On other platforms `isAvailable()` is false and the UI hides the option.
  - `MemoryCloudStore`: in-memory fake for tests.
- Remote layout: one JSON file per record — `nb_<id>.json`, `card_<id>.json`; attachments
  `att_<id>.bin`. Plus `manifest.json` is NOT used; listing is the source of truth.
- `SyncEngine` (pure Dart, heavily unit-tested with MemoryCloudStore):
  - Keeps per-record `SyncState { lastSyncedRemoteModified, lastSyncedLocalUpdatedAt }`.
  - For each record: only local changed → upload; only remote changed → download+apply;
    both changed and content differs → create a `SyncConflict { local, remote }` and do NOT
    overwrite either; neither → skip. Tombstones propagate deletes.
  - `resolveConflict(id, keepLocal | keepRemote | keepBoth)`; keepBoth duplicates as new card.
  - Returns `SyncReport { uploaded, downloaded, conflicts, errors }`. Never throws for a
    single-file failure; collects errors.
  - Status stream: idle | syncing | synced(at) | offline | error(message) | conflicts(n).
- Switching provider: push everything to the new store, then mark it active. Disconnect keeps
  local data.

## Papers and renewals (lib/features/papers)
- `ExpiryDateParser` (pure Dart, unit-tested): from OCR text find the most likely expiry /
  due / valid-until date. Handle `18/10/2026`, `18-10-2026`, `18 Oct 2026`,
  `October 18, 2026`, `2026-10-18`; day-first for numeric forms (India). Prefer dates next
  to keywords: expiry, expires, valid till/until/upto, due date, renewal, policy period "to".
  Return null when nothing confident. Each test cites the hand-worked expected value.
- `RenewalsLogic`: upcoming list sorted by date, "due in N days" labels, folders
  (Insurance, Vehicle, Warranties, Bills, Other).
- OCR: `google_mlkit_text_recognition` on Android/iOS only, behind `OcrService` interface
  with a no-op implementation for web. Note: ML Kit has no Telugu script model.
- Reminders: `flutter_local_notifications` behind `ReminderService` interface (no-op on web).

## Plus / monetisation
- `Entitlements` interface: `isPlus`. v1 implementation is a local debug toggle in Settings;
  real store billing is NOT wired (documented in README as a TODO needing store accounts).
- Free: all card types, sync, lock, PDF/text share, up to `freeNotebookLimit` (5) notebooks,
  `freeScansPerMonth` (10), `freeTranscriptsPerMonth` (5).
- Plus (₹299/yr, 7-day trial copy): renewal reminders from scans, searchable scan text,
  voice-to-text, Ask your notes, unlimited notebooks/scans.
- `AiService` interface (`transcribe(audio, lang)`, `ask(question, context)`) with NO real
  implementation in v1 — it needs a server-side key. The UI for transcript/Ask shows a clear
  "not available in this build" state when `AiService` is the unconfigured one. Do not fake
  answers.

## Screens (lib/features/*/ui) — follow the HTML design artboards exactly for layout,
copy, colours and spacing (paths given in the task). Routes:
`/welcome`, `/sync-setup`, `/` (notebooks), `/notebook/:id`, `/card/:id` (dispatches by
type: text, checklist, voice, photo/scan viewer), `/new-card/:notebookId` (bottom sheet),
`/search`, `/papers`, `/ask`, `/settings`, `/settings/sync`, `/conflict/:id`, `/paywall`.
Bottom bar: Notebooks, Papers, (+), Reminders, Settings.

## Design tokens (lib/core/theme)
- ground `#F3F4F8`, ink `#171A2E`, muted text `#4A4F66`, hairline `#E3E5EC`, white surfaces.
- Card colours (index 0..4): sun `#FFD45C`, sky `#BFD6FF`, mint `#BDE8CF`, coral `#FFC2B0`,
  lilac `#D9CCFF`. Success chip bg `#DDF3E6` / text `#14532D`. Danger `#B3261E`. Link `#2447C9`.
- Radius: cards 20, sheets 28, buttons 16, pills 22. Min touch target 44. Primary button =
  ink background, white text, 56 high.
- Display font for titles (700, tight letter-spacing), body font for the rest.
- Light theme only in v1, but build colours through a `VarnaColors` ThemeExtension so dark
  can be added. Must work at 320dp width and 1.3x text scale (scroll, never overflow).
- Strings in English via a simple `lib/l10n/strings.dart` class for now (Telugu later).

## Quality bar
- `flutter analyze` 0 issues, `flutter test` green (run by CI, not locally).
- Unit tests: SyncEngine (all branches incl. conflicts, tombstones, keepBoth), search,
  ExpiryDateParser, usage counters/month reset, model JSON round-trips.
- One widget smoke test: app boots to Welcome, then to Notebooks after onboarding.
