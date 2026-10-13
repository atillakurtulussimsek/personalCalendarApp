-- name: CreateSession :exec
INSERT INTO sessions (id, user_id, device_id, refresh_token_hash, expires_at, created_at)
VALUES (?, ?, ?, ?, ?, ?);

-- name: GetSessionByTokenHash :one
SELECT * FROM sessions WHERE refresh_token_hash = ? LIMIT 1;

-- name: RevokeSession :exec
UPDATE sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL;

-- name: RevokeSessionsByDevice :exec
UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND device_id = ? AND revoked_at IS NULL;

-- name: DeleteExpiredSessions :exec
DELETE FROM sessions WHERE expires_at < ? OR revoked_at < ?;
