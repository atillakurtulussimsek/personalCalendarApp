-- name: NextServerSeq :execresult
UPDATE sync_counter SET value = LAST_INSERT_ID(value + 1) WHERE id = 1;

-- name: CurrentServerSeq :one
SELECT value FROM sync_counter WHERE id = 1;

-- name: PullCalendars :many
SELECT * FROM calendars WHERE user_id = ? AND server_seq > ? ORDER BY server_seq LIMIT ?;

-- name: PullEvents :many
SELECT * FROM events WHERE user_id = ? AND server_seq > ? ORDER BY server_seq LIMIT ?;

-- name: PullNotes :many
SELECT * FROM notes WHERE user_id = ? AND server_seq > ? ORDER BY server_seq LIMIT ?;
