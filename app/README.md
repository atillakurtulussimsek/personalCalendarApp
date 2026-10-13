# App — Flutter client (Android + macOS)

Riverpod · drift (SQLite + FTS5) · dio · offline-first outbox sync

## Run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift code
flutter gen-l10n                                            # strings (also runs on build)
flutter run -d macos          # or: flutter run -d <android device id>
```

On first launch enter the server URL (e.g. `http://localhost:8080` on macOS,
`http://10.0.2.2:8080` from the Android emulator), then register or log in.
Debug Android builds allow plain `http://`; release builds are HTTPS only.

## Test & lint

```bash
flutter analyze
flutter test
```

`test/sync_service_test.dart` runs the real sync service against an in-memory drift
database and an in-memory fake of the server's sync semantics (versions, LWW, conflict
copies, pagination). `test/api_client_test.dart` covers token refresh. The login widget
test covers form validation.

## Build

```bash
flutter build apk --release                     # build/app/outputs/flutter-apk/app-release.apk
flutter build macos --release                   # build/macos/Build/Products/Release/personal_calendar.app
```

macOS builds need Xcode + CocoaPods; Android builds need a JDK and accepted SDK licenses
(`flutter doctor --android-licenses`).

## Layout

```
lib/main.dart, app.dart        bootstrap, theme, locale, root navigation by session state
lib/core                       theme, date helpers (tr, 24h, Monday first)
lib/l10n                       app_tr.arb → generated L10n
lib/data/db                    drift tables, database, FTS5, outbox, sync state
lib/data/api                   dio client (bearer + refresh), auth + sync endpoints, token store
lib/data/sync                  JSON mappers, SyncService (push outbox → pull since last_seq)
lib/data/repositories          local-first writes: DB + outbox + sync nudge
lib/providers.dart             Riverpod wiring, session state, sync triggers
lib/features/auth              login / register
lib/features/home              shell (bottom nav / rail), sync indicator, shortcuts
lib/features/calendar          month grid + day list, agenda, quick event sheet
lib/features/notes             list + FTS search, Markdown editor with autosave
```

## Sync behaviour

* Every write goes to SQLite first and appends to the outbox (one row per record; later
  edits replace earlier ones, keeping the original base version). UI updates instantly via
  drift streams.
* `SyncService.sync()` pushes the outbox in batches of 200, applies results
  (`applied` → store version/seq, `conflict` → overwrite local with the server record,
  `rejected` → drop with error, `ignored` → drop), then pulls pages since `last_seq`.
* A pulled record never overwrites a pending local edit that is newer than the server's.
* Triggers: app resume, connectivity regained, every 5 minutes, 2 s after a local write,
  the toolbar button, ⌘R. Android WorkManager background sync arrives with phase 5.
