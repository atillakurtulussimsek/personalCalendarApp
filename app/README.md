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
lib/features/calendar          month / week / day (drag & drop, resize) / agenda, full event editor,
                               recurrence picker, edit-scope dialog, calendars + ICS subscriptions
lib/core/recurrence.dart       RRULE expansion with exceptions (mirrors the server)
lib/core/tz.dart               IANA zones (timezone + flutter_timezone), wall-time conversions
lib/core/ics.dart              minimal iCalendar parser for subscriptions
lib/features/notes             list + FTS search, Markdown editor with autosave
```

## Calendar behaviour

* Recurring events are expanded on the device in the event's own IANA zone
  (`core/recurrence.dart`), identical to the server's `expand=true`. Exceptions
  (`recurrence_id` + `original_start`) replace or cancel single instances.
* Editing an instance asks for a scope: **only this** (creates/updates an exception row),
  **this and following** (sets `UNTIL` on the master, starts a new series with the remaining
  `COUNT`), **all** (edits the master, shifting times by the delta applied to the instance).
* Week/day grid: drag a block to move it (mouse drag on macOS, long-press on Android), drag the
  bottom handle to resize; 15-minute snapping; tap an empty slot to create.
* ICS subscriptions (e.g. Turkish public holidays) are device-local, read-only calendars
  refreshed every 12 hours; they are never pushed to the server.
* Shortcuts: ←/→ day, ↑/↓ week, PgUp/PgDn period, T today, M/W/D/A views, ⌘N new, ⌘S save.

## Quick capture (phase 4)

* `core/capture_parser.dart` turns one Turkish line into an event or a note
  (dates, weekdays, times and ranges, day parts, durations, reminders, recurrence,
  `@location`); `test/capture_parser_test.dart` holds the spec examples.
* `features/capture/capture_sheet.dart` shows live preview chips; tapping a chip opens the
  full editor prefilled. Entry points: ⚡ toolbar button, ⌘K / Ctrl+K, long-press on the FAB,
  and every native entry below (routed through `platform/app_intents.dart`).
* **Android** (`android/app/src/main/kotlin/...`): share sheet (text/*), home-screen widget
  with today's agenda + add button (`AgendaWidgetProvider`, data via `home_widget`),
  Quick Settings tile (`CaptureTileService`), optional persistent notification with
  note/event actions (`CaptureNotification`, toggled in Settings), long-press app shortcuts
  (`quick_actions`), deep links `personalcalendar://capture?text=…|note|event|today`.
* **macOS** (`platform/desktop_integration.dart`, `macos/Runner/AppDelegate.swift`): menu bar
  icon listing the next events with "Hızlı ekle…", global hotkey (default ⌥Space, changeable in
  Settings), close-to-menu-bar, "hide from Dock", launch at login (SMAppService), URL scheme.
  Not yet compiled on this machine (Xcode missing) — see `docs/decisions.md`.

## Reminders & live sync (phase 5)

* `platform/reminders_service.dart` expands the next 14 days, gives every
  (occurrence, reminder) a stable id and re-plans after each local change or sync:
  stale alarms are cancelled, new ones scheduled with `flutter_local_notifications`.
  Works fully offline; tapping a notification opens the event.
* **Android permissions**: on first launch the app explains and requests notification
  permission and (Android 12+) the "Alarms & reminders" exact-alarm permission. Without it
  reminders use `inexactAllowWhileIdle` and may be delayed by Doze; Settings shows the
  state and re-requests. Some OEMs (Xiaomi, Huawei) also need battery optimisation disabled.
* `platform/live_sync.dart` keeps `GET /ws` open (always on macOS, foreground only on
  Android) and runs a sync on each `{"type":"sync"}` signal; exponential backoff,
  re-auth after token refresh.
* `platform/push_service.dart` (Android): FCM data messages wake the app for a sync even
  when it is closed. Configure with `--dart-define` (no google-services.json needed):

  ```bash
  flutter build apk --release \
    --dart-define=FIREBASE_API_KEY=… --dart-define=FIREBASE_APP_ID=… \
    --dart-define=FIREBASE_SENDER_ID=… --dart-define=FIREBASE_PROJECT_ID=…
  ```

  and set `FCM_SERVICE_ACCOUNT_JSON` on the backend. Without these, push is simply off.
* `platform/background_sync.dart`: WorkManager periodic sync every 15 min (Android),
  network-constrained, shares the SQLite database across isolates.

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
