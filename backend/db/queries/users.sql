-- name: GetUserByPhone :one
SELECT id, name, phone, role, created_at, updated_at
FROM users
WHERE phone = $1;

-- name: GetUserRole :one
SELECT role FROM users WHERE id = $1;

-- name: GetUserByID :one
SELECT id, name, phone, role FROM users WHERE id = $1;

-- name: CreateUser :one
INSERT INTO users (name, phone, role)
VALUES ($1, $2, $3)
RETURNING id, name, phone, role, created_at, updated_at;

-- name: UpdateUserProfile :one
UPDATE users
SET name = $2,
    role = $3,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, phone, role, created_at, updated_at;

-- name: DeleteUser :exec
DELETE FROM users WHERE id = $1;
