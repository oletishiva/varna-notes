# Setup you must do yourself

Nothing secret is committed. OAuth client ids are passed with `--dart-define`.

## 1. Google Drive sync (all platforms)

1. Google Cloud Console: create a project (for example "Varna").
2. APIs & Services > Library: enable **Google Drive API**.
3. APIs & Services > OAuth consent screen: set app name, support email; add the scope
   `https://www.googleapis.com/auth/drive.appdata` (non-sensitive, no Google review needed for this scope alone). While in Testing, add your Google accounts as test users.
4. APIs & Services > Credentials > Create credentials > OAuth client ID:
   - **Web application**: add authorised JavaScript origins (`http://localhost:<port>` for dev, your hosted URL for prod). Copy the client id.
   - **Android**: package name `com.qavedik.varna` and the SHA-1 of your signing key. Debug SHA-1: `cd android && ./gradlew signingReport`. Add the release/Play SHA-1 as another Android client later.
   - **iOS**: bundle id `com.qavedik.varna`. Copy the client id and its reversed form (`com.googleusercontent.apps.<number>-<hash>`).
5. Pass the ids at build time (names are read in `lib/app_config.dart`):

| Define | Value | Used on |
| --- | --- | --- |
| `GOOGLE_WEB_CLIENT_ID` | Web application client id | web |
| `GOOGLE_IOS_CLIENT_ID` | iOS client id | iOS |
| `GOOGLE_SERVER_CLIENT_ID` | Web client id (optional) | Android, iOS |

```
flutter run -d chrome --dart-define=GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com
flutter run -d ios --dart-define=GOOGLE_IOS_CLIENT_ID=<id>.apps.googleusercontent.com
```

Web: Google sign-in will not work without `GOOGLE_WEB_CLIENT_ID`, and the page's
origin must be listed under authorised JavaScript origins.

Android needs no define when the Android OAuth client (package + SHA-1) exists.

iOS: in `ios/Runner/Info.plist`, replace `REPLACE-WITH-REVERSED-IOS-CLIENT-ID`
(under `CFBundleURLTypes`) with the reversed iOS client id, for example
`com.googleusercontent.apps.1234567890-abcdef`.

## 2. iCloud sync (iOS)

1. Apple Developer account (paid). Certificates, Identifiers & Profiles:
   - Identifiers > App IDs: register `com.qavedik.varna`, enable **iCloud**.
   - Identifiers > iCloud Containers: create `iCloud.com.qavedik.varna` and assign it to the App ID.
2. The repo already contains `ios/Runner/Runner.entitlements` with this container. It is not
   yet linked to the Xcode project. Do these steps once on a Mac (open `ios/Runner.xcworkspace`):
   1. Runner target > Signing & Capabilities: choose your Team and confirm Bundle Identifier `com.qavedik.varna`.
   2. Click **+ Capability** > **iCloud**, tick **iCloud Documents**, and select the container `iCloud.com.qavedik.varna`.
   3. Xcode now sets `CODE_SIGN_ENTITLEMENTS`. If it creates a new entitlements file, make sure its content matches `ios/Runner/Runner.entitlements` (or point the build setting `Code Signing Entitlements` to `Runner/Runner.entitlements`).
3. The user must be signed in to iCloud on the device; there is no in-app sign-in.

## 3. iOS build notes

- `ios/Podfile` is not committed; Flutter generates it on the first `flutter build ios` / `flutter run -d ios`.
  ML Kit needs iOS 15.5: after it is generated, make sure its first lines read `platform :ios, '15.5'`
  (uncomment and edit the line). The Xcode project's deployment target is already 15.5.
- Per the ML Kit docs, also add to `post_install` in the Podfile:
  `config.build_settings["EXCLUDED_ARCHS[sdk=*]"] = "armv7"`.
- Run `pod install` from `ios/` if CocoaPods complains.

## 4. Android build notes

- minSdk is 24; core library desugaring is on (needed by flutter_local_notifications).
- No signing config is committed. Release builds currently use debug signing; create a keystore and `key.properties` yourself before publishing (both are git-ignored).

## 5. Not wired in v1

- **Store billing.** Plus is a debug toggle (`DebugToggleEntitlements`). Real billing needs Play Console and App Store Connect products plus an `Entitlements` implementation (for example in_app_purchase) that replaces it in `entitlementsProvider`.
- **AI transcription and "Ask your notes".** Needs a server-side key; never ship the key in the app. Minimal proxy design:
  1. A tiny HTTPS function (Cloud Run / Cloudflare Worker) holds the AI provider key as a secret.
  2. `POST /transcribe` takes audio bytes and a language code, returns `{text}`.
  3. `POST /ask` takes `{question, context: [string]}`, returns `{answer}`.
  4. The app sends a Google ID token (or Plus receipt) in `Authorization`; the function verifies it and rate-limits per user.
  5. The function does not log or store note content.
  6. Implement `AiService` (`lib/core/services/ai_service.dart`) with `http` calls and return it from `aiServiceProvider`.
- **Live camera scan.** Scan uses the system camera through image_picker, one page at a time.
- **Telugu OCR.** ML Kit text recognition has no Telugu script model (Latin only in this build), so Telugu text in scans is not recognised or searchable. Telugu typed text, titles and search work normally.
