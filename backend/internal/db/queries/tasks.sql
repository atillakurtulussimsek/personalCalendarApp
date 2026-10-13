-- name: InsertTask :exec
INSERT INTO tasks (id, user_id, title, due_at, done, note_id, created_at, updated_at, deleted_at, version, server_seq)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: UpdateTask :exec
UPDATE tasks
SET title = ?, due_at = ?, done = ?, note_id = ?, updated_at = ?, deleted_at = ?, version = ?, server_seq = ?
WHERE id = ? AND user_id = ?;

-- name: GetTask :one
SELECT * FROM tasks WHERE id = ? AND user_id = ? LIMIT 1;

-- name: GetTaskForUpdate :one
SELECT * FROM tasks WHERE id = ? AND user_id = ? LIMIT 1 FOR UPDATE;

-- name: ListTasks :many
SELECT * FROM tasks WHERE user_id = ? AND deleted_at IS NULL
ORDER BY done ASC, due_at IS NULL, due_at ASC, created_at DESC LIMIT ? OFFSET ?;

-- name: PullTasks :many
SELECT * FROM tasks WHERE user_id = ? AND server_seq > ? ORDER BY server_seq LIMIT ?;
