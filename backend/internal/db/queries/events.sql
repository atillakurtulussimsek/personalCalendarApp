-- name: InsertEvent :exec
INSERT INTO events (
  id, user_id, calendar_id, title, description, location, start_at, end_at, timezone, all_day,
  rrule, recurrence_id, original_start, reminders, created_at, updated_at, deleted_at, version, server_seq
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateEvent :exec
UPDATE events
SET calendar_id = ?, title = ?, description = ?, location = ?, start_at = ?, end_at = ?, timezone = ?,
    all_day = ?, rrule = ?, recurrence_id = ?, original_start = ?, reminders = ?,
    updated_at = ?, deleted_at = ?, version = ?, server_seq = ?
WHERE id = ? AND user_id = ?;

-- name: GetEvent :one
SELECT * FROM events WHERE id = ? AND user_id = ? LIMIT 1;

-- name: GetEventForUpdate :one
SELECT * FROM events WHERE id = ? AND user_id = ? LIMIT 1 FOR UPDATE;

-- name: ListEventsInRange :many
-- Non-recurring events overlapping [from, to) plus every recurring master (filtered in Go).
SELECT * FROM events
WHERE user_id = ? AND deleted_at IS NULL
  AND (
    (rrule IS NULL AND start_at < sqlc.arg(range_to) AND end_at > sqlc.arg(range_from))
    OR (rrule IS NOT NULL AND start_at < sqlc.arg(range_to))
  )
ORDER BY start_at;

-- name: ListEventExceptions :many
SELECT * FROM events
WHERE user_id = ? AND recurrence_id IN (sqlc.slice(series_ids))
ORDER BY original_start;
