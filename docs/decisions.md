# Architecture Decision Log

Each entry: date, decision, rationale. Newest at the bottom.

## 2026-10-13 — MySQL 8 instead of PostgreSQL 16

**Decision:** The backend uses MySQL 8.x (`go-sql-driver/mysql`) instead of PostgreSQL/`pgx`.
`sqlc` (engine `mysql`) and `golang-migrate` (mysql driver) are kept as planned.

**Rationale:** The project owner asked for MySQL explicitly (no PostgreSQL experience,
existing remote MySQL available). Consequences:

- UUIDs are stored as `CHAR(36)` (client-generated, canonical lowercase form).
- `notes.tags` is a `JSON` array of strings instead of `text[]`.
- `events.reminders` is a `JSON` array of integers (minutes before start).
- Full-text search on notes uses a MySQL `FULLTEXT` index (server side); the client
  still uses SQLite FTS5.
- The global monotonic `server_seq` is produced by a single-row `sync_counter` table
  updated inside the same transaction as the write
  (`UPDATE sync_counter SET value = LAST_INSERT_ID(value + 1)`), which is the standard
  MySQL pattern for a gap-free, ordered sequence.
- All `DATETIME(6)` columns hold UTC; the DSN uses `parseTime=true&loc=UTC`.

## 2026-10-13 — Local development database

**Decision:** Development uses a remote MySQL instance provided via `DATABASE_URL` in `.env`.
Integration tests run only when `TEST_DATABASE_URL` is set and use a dedicated database
(they drop and re-create all tables).

**Rationale:** No Docker on the development machine; the owner prefers a remote MySQL.

## 2026-10-13 — Production database in docker-compose

**Decision:** `docker-compose.yml` ships a `mysql:8.4` service with a named volume next to the
API, so the stack deploys to Dokploy as one compose project. Pointing the API to an external
MySQL only requires overriding `DATABASE_URL`.

**Rationale:** No preference was given; a self-contained compose is the simplest Dokploy deploy.

## 2026-10-13 — Registration policy

**Decision:** `POST /auth/register` is open by default and can be closed with
`ALLOW_REGISTRATION=false` once the owner's account exists.

## 2026-10-13 — Migrations run on startup

**Decision:** The API binary embeds its SQL migrations and applies pending ones at startup
(`golang-migrate` library with `iofs` source). The `migrate` CLI is only needed to author
new migrations.

**Rationale:** Zero-step deploys on Dokploy; the container is the only thing that needs to run.

## 2026-10-13 — Sync conflict policy

**Decision:** `POST /sync` applies "last writer wins" on `updated_at` when the pushed
`base_version` does not match the server version. For `notes`, the losing body is never
discarded: it is stored as a new note titled `(çakışan kopya) <title>` owned by the same user,
and the id of that copy is returned to the pushing client.

## 2026-10-13 — Recurrence expansion lives on the server too

**Decision:** `GET /events?from=&to=&expand=true` expands RRULEs with `teambition/rrule-go`
already in phase 1, honouring exception instances (`recurrence_id` + `original_start`).
The client gets its own expansion in phase 3 (Dart `rrule` package).

**Rationale:** The endpoint is part of the public API contract; having it server side early
makes the OpenAPI spec and integration tests complete.

## 2026-10-13 — Exactly one default calendar

**Decision:** A user always has exactly one default calendar. `is_default=true` on a
create/update moves the flag; `is_default=false` on the current default is ignored.
Deleting the default promotes the first remaining calendar. The last calendar cannot be deleted.

## 2026-10-13 — Flutter dependencies beyond the mandated stack

| package | reason |
|---------|--------|
| `drift_flutter` | official helper to open drift databases on Android/macOS (replaces the EOL `sqlite3_flutter_libs`) |
| `flutter_secure_storage` | tokens in Keychain / Android Keystore instead of plain prefs |
| `connectivity_plus` | "network came back" sync trigger |
| `uuid` | client-side UUID v4 generation (required by the data model) |
| `intl` + `flutter_localizations` | Turkish date formats and the i18n pipeline (`gen-l10n`) |
| `flutter_markdown_plus` | Markdown preview in the note editor (maintained fork of the discontinued `flutter_markdown`) |
| `mocktail` (dev) | reserved for widget tests; sync tests use hand-written fakes |

No router package: navigation is a `switch` on session state plus `Navigator.push`.

## 2026-10-13 — Client timezone in phase 2

Dart exposes only the zone abbreviation (`+03`), not an IANA name. Until phase 3 adds a
timezone package the client sends `Europe/Istanbul` for new events; the server stores UTC
regardless, so this only affects recurrence expansion of events created in phase 2.

## 2026-10-13 — Background sync on Android deferred to phase 5

Foreground triggers (resume, connectivity, periodic timer, post-write debounce) cover
phase 2. WorkManager periodic sync is added together with FCM in phase 5, because both
need the same background isolate / shared-database setup (`shareAcrossIsolates`).

## 2026-10-13 — ICS subscriptions are device-local

**Decision:** Subscribed calendars (`calendars.source = 'ics'`) and their events live only in
the device database; they are never pushed and the server knows nothing about them. Each
device subscribes on its own and refreshes feeds every 12 hours.

**Rationale:** Feeds are read-only and re-fetchable; syncing thousands of holiday rows through
the outbox adds nothing. A synced "subscription list" can be added later if wanted.

## 2026-10-13 — "This and following" is implemented client-side

**Decision:** Splitting a series sets `UNTIL` on the master (one second before the edited
instance, in the series zone), drops exceptions at or after the cut, and creates a new master
with the remaining `COUNT` when the rule had one. The server only sees ordinary upserts.

## 2026-10-13 — Timezone handling

**Decision:** `flutter_timezone` provides the device IANA name, `timezone` provides the tz
database; recurrence is iterated in "wall time" (`Tz.toWall`/`fromWall`) so local hours
survive DST, matching `teambition/rrule-go` with `StrToROptionInLocation` on the server.

## 2026-10-13 — Phase 4 platform packages

| package | reason |
|---------|--------|
| `home_widget` | bridges SharedPreferences data to a native `AppWidgetProvider` and reports widget taps |
| `quick_actions` | long-press launcher shortcuts (official flutter/packages) |
| `tray_manager` (legacy API), `hotkey_manager`, `window_manager` | leanflutter trio for menu bar icon, global hotkey, hide-to-tray and Dock hiding |

`launch_at_startup` was rejected (its `win32` pin conflicts with `flutter_secure_storage` 11);
launch-at-login is a 20-line `SMAppService` call in `AppDelegate.swift` instead.

## 2026-10-13 — Quick capture window on macOS

**Decision:** The global hotkey brings the main window forward and opens the capture sheet
instead of a separate Spotlight-style panel. Flutter desktop has no stable multi-window API;
a second engine for one text field is not worth the complexity. Revisit when
`flutter/flutter#30701` lands.

## 2026-10-13 — macOS code is unverified

Xcode is not installed on the development machine, so phase 4 macOS code (tray, hotkey,
AppDelegate) compiles only in theory. First macOS build will likely need small fixes.

## 2026-10-13 — Device-local settings live in `sync_state`

Hotkey, Dock hiding, launch-at-login and the Android capture notification are per device,
so they are stored in the drift key/value table under `setting.*` keys, not synced.

## 2026-10-13 — Firebase without google-services.json

**Decision:** FCM is initialised from `--dart-define` values (`FirebaseOptions`) instead of
`google-services.json` + the Gradle plugin, and the backend takes the service-account JSON
from `FCM_SERVICE_ACCOUNT_JSON`. Push is optional: when the values are empty the app builds
and runs without Firebase, relying on WebSocket (foreground) and WorkManager (background).

**Rationale:** The repository stays free of project-specific secrets and the build never
breaks for a contributor without a Firebase project.

## 2026-10-13 — Live sync transport per platform

macOS keeps a WebSocket to `/ws` open permanently. Android uses the socket only while the app
is in the foreground (Doze kills idle sockets anyway); in the background FCM high-priority
data messages and the 15-minute WorkManager job take over. The server never notifies the
device that caused the change.

## 2026-10-13 — Reminder scheduling window

Only the next 14 days (max 400 alarms) are scheduled, because Android limits pending alarms
(~500 per app) and recurring events are unbounded. The window slides every 6 hours and after
each change; ids are deterministic hashes so an unchanged occurrence is never re-scheduled.

## 2026-10-13 — CalDAV layer not implemented

**Decision:** The optional CalDAV server (for iPhone / Thunderbird) is left out of phase 6.
ICS export + subscription URLs cover read-only interop; a full CalDAV implementation (WebDAV
PROPFIND/REPORT, ETags, calendar-query filters) is a project of its own.

## 2026-10-13 — Backups via a compose sidecar

`mysqldump --single-transaction` runs in a `mysql:8.4` sidecar every 24 h into the `backups`
volume with 14-day retention. No cron daemon in the API image; the loop script is the cron.

## 2026-10-13 — ICS import is client-side

Imported files are parsed on the device (`core/ics.dart`) and created as ordinary events so
they flow through the outbox like manual entries. Exceptions (RECURRENCE-ID) in imported
files are ignored for now.

## 2026-10-14 — Web UI embedded into the API binary

**Decision:** The Flutter web build is embedded with `go:embed` (`backend/internal/webui`) and
served on the API port; non-API GETs fall back to `index.html`. One root `Dockerfile`
(Flutter stage → Go stage → distroless) and one `make build` produce everything.

**Rationale:** Single deploy unit on Dokploy, same origin (no CORS, no server URL prompt on
the web), and the UI version always matches the API version.

## 2026-10-14 — drift web storage fallback

Some browsers (and embedded webviews) advertise SharedWorker but block its network access,
so loading `sqlite3.wasm` inside the worker fails. `connection_web.dart` probes each
worker-based storage with a throwaway database and falls back to `unsafeIndexedDb`
(single-tab, persistent). `drift_worker.js` is compiled from our own lockfile instead of
downloading the release build, so worker and wasm versions always match.

## 2026-10-14 — connectivity_plus pinned to 6.x

7.x uses `NWPath.isUltraConstrained`, absent from the Xcode 16.4 macOS SDK.
