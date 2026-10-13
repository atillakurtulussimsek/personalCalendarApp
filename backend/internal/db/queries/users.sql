-- name: CreateUser :exec
INSERT INTO users (id, email, password_hash, created_at, updated_at)
VALUES (?, ?, ?, ?, ?);

-- name: GetUserByEmail :one
SELECT * FROM users WHERE email = ? LIMIT 1;

-- name: GetUserByID :one
SELECT * FROM users WHERE id = ? LIMIT 1;

-- name: CountUsers :one
SELECT COUNT(*) FROM users;
