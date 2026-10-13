-- name: UpsertDevice :exec
INSERT INTO devices (id, user_id, platform, name, push_token, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON DUPLICATE KEY UPDATE
  platform = VALUES(platform),
  name = VALUES(name),
  push_token = VALUES(push_token),
  updated_at = VALUES(updated_at),
  deleted_at = NULL,
  version = version + 1;

-- name: ListDevices :many
SELECT * FROM devices WHERE user_id = ? AND deleted_at IS NULL ORDER BY created_at;

-- name: GetDevice :one
SELECT * FROM devices WHERE id = ? AND user_id = ? LIMIT 1;

-- name: UpdateDevicePushToken :exec
UPDATE devices SET push_token = ?, updated_at = ?, version = version + 1
WHERE id = ? AND user_id = ?;

-- name: TouchDeviceSync :exec
UPDATE devices SET last_sync_at = ? WHERE id = ? AND user_id = ?;

-- name: SoftDeleteDevice :exec
UPDATE devices SET deleted_at = ?, updated_at = ?, version = version + 1
WHERE id = ? AND user_id = ? AND deleted_at IS NULL;
