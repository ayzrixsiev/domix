-- name: GetUserByPhone :one
SELECT id, name, phone, created_at, updated_at 
FROM users 
WHERE phone = $1;

-- name: CreateUser :one
INSERT INTO users (name, phone)
VALUES ($1, $2)
RETURNING id, name, phone, created_at, updated_at;