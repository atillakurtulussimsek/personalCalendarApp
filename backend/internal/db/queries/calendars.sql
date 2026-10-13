-- name: InsertCalendar :exec
INSERT INTO calendars (id, user_id, name, color, is_default, created_at, updated_at, deleted_at, version, server_seq)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateCalendar :exec
UPDATE calendars
SET name = ?, color = ?, is_default = ?, updated_at = ?, deleted_at = ?, version = ?, server_seq = ?
WHERE id = ? AND user_id = ?;

-- name: GetCalendar :one
SELECT * FROM calendars WHERE id = ? AND user_id = ? LIMIT 1;

-- name: GetCalendarForUpdate :one
SELECT * FROM calendars WHERE id = ? AND user_id = ? LIMIT 1 FOR UPDATE;

-- name: ListCalendars :many
SELECT * FROM calendars WHERE user_id = ? AND deleted_at IS NULL ORDER BY is_default DESC, name;

-- name: ClearDefaultCalendar :exec
UPDATE calendars SET is_default = FALSE WHERE user_id = ? AND is_default = TRUE AND id <> ?;

-- name: CountActiveCalendars :one
SELECT COUNT(*) FROM calendars WHERE user_id = ? AND deleted_at IS NULL;
