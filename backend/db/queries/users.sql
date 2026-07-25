-- name: GetUserByPhone :one
SELECT id, name, phone, telegram_chat_id, role, created_at, updated_at
FROM users
WHERE phone = $1;

-- name: GetUserRole :one
-- role isn't baked into the jwt (it can change after the token is issued), so authorization checks
-- look this up fresh instead of trusting a claim that might be stale - see internal/auth/jwt.go
SELECT role FROM users WHERE id = $1;

-- name: CreateUser :one
INSERT INTO users (name, phone, telegram_chat_id, role)
VALUES ($1, $2, $3, $4)
RETURNING id, name, phone, telegram_chat_id, role, created_at, updated_at;

-- name: UpdateUserProfile :one
UPDATE users
SET name = $2,
    telegram_chat_id = $3,
    role = $4,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, phone, telegram_chat_id, role, created_at, updated_at;