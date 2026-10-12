# Varna

Card-based notes for Android, iOS and web. Notes live on the device first and
sync to the user's own Google Drive (hidden app folder) or iCloud. There is no
Varna server for notes.

Package id: `com.qavedik.varna`. Free plan with an optional Plus plan
(see `lib/app_config.dart` for limits and price).

## Features and honest status

Working (no accounts needed):
- Notebooks and cards: text, checklist, voice note, photo, scan, link
- Colours, favourites, search across title, body, checklist items, OCR text and transcripts
- Offline-first local storage (sembast; IndexedDB on web)
- Papers and renewals: expiry date detection from scanned text, folders, "due in N days"
- Sync engine with conflict detection and a conflict screen (tested against an in-memory cloud)
- Wi-Fi-only sync setting (enforced on Android/iOS; web cannot tell and always syncs)
- Share, notebook lock with biometrics (mobile)
- Reminders (Android/iOS, inexact alarms)

Works only after you set up your accounts (see `docs/SETUP.md`):
- Google Drive sync (Google Cloud project and OAuth clients)
- iCloud sync (Apple Developer account, iCloud container, Xcode capability)

Not in v1:
- Store billing: Plus is a local debug toggle in Settings
- Voice-to-text and "Ask your notes": need a server-side AI key; the app shows "not available in this build"
- Live camera scanning: scanning uses the system camera one page at a time
- Telugu text recognition: ML Kit has no Telugu model, so Telugu scans are stored but not searchable
- Dark theme

## Run

```
flutter pub get
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

Google sign-in needs OAuth client ids passed at build time, for example:

```
flutter run -d chrome --dart-define=GOOGLE_WEB_CLIENT_ID=<web client id>
```

See `docs/SETUP.md` for all define names.

## Tests

```
flutter analyze
flutter test
```

## CI

`.github/workflows/ci.yml` runs pub get, analyze, test and a web build on every
push. After each push to `main` the last 500 lines of every log and a
`RESULT.txt` summary are force-pushed to the `ci-logs` branch, so results can
be read with plain git.

## More

- `docs/SETUP.md` - everything you must set up yourself
- `docs/CORE_API.md` - providers, repositories, sync controller and models
- `docs/DECISIONS.md` - one line per technical decision
- `SPEC.md` - original build spec
