-- name: InsertNote :exec
INSERT INTO notes (id, user_id, title, body, pinned, event_id, tags, created_at, updated_at, deleted_at, version, server_seq)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateNote :exec
UPDATE notes
SET title = ?, body = ?, pinned = ?, event_id = ?, tags = ?, updated_at = ?, deleted_at = ?, version = ?, server_seq = ?
WHERE id = ? AND user_id = ?;

-- name: GetNote :one
SELECT * FROM notes WHERE id = ? AND user_id = ? LIMIT 1;

-- name: GetNoteForUpdate :one
SELECT * FROM notes WHERE id = ? AND user_id = ? LIMIT 1 FOR UPDATE;

-- name: ListNotes :many
SELECT * FROM notes WHERE user_id = ? AND deleted_at IS NULL
ORDER BY pinned DESC, updated_at DESC LIMIT ? OFFSET ?;

-- name: ListNotesByEvent :many
SELECT * FROM notes WHERE user_id = ? AND event_id = ? AND deleted_at IS NULL ORDER BY updated_at DESC;

-- name: SearchNotes :many
SELECT * FROM notes
WHERE user_id = ? AND deleted_at IS NULL
  AND MATCH(title, body) AGAINST (sqlc.arg(query) IN BOOLEAN MODE)
ORDER BY pinned DESC, updated_at DESC LIMIT ? OFFSET ?;

-- name: ListNotesByTag :many
SELECT * FROM notes
WHERE user_id = ? AND deleted_at IS NULL AND JSON_CONTAINS(tags, JSON_QUOTE(sqlc.arg(tag)))
ORDER BY pinned DESC, updated_at DESC LIMIT ? OFFSET ?;
