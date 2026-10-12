# Decisions

- sembast over drift — pure Dart, works on web and mobile, no code generation.
- No codegen anywhere — no build_runner, freezed, riverpod_generator or json_serializable; JSON is hand-written.
- flutter_riverpod 2.x — plain providers, no generator.
- go_router for navigation.
- google_sign_in 6.x with the drive.appdata scope — notes live in the app's hidden Drive folder, never in the user's visible files.
- iCloud via icloud_storage — container `iCloud.com.qavedik.varna`, iOS/macOS only.
- ML Kit text recognition is mobile-only — web uses a no-op OCR service.
- Fonts are bundled (Figtree, Bricolage Grotesque, Noto Sans Telugu) — nothing is downloaded at runtime.
- Light theme only in v1 — colours go through `VarnaColors` so dark can be added later.
- Reminders use inexact alarms — no SCHEDULE_EXACT_ALARM permission needed.
- connectivity_plus — enforce the Wi-Fi-only sync setting
