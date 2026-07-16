-- name: GetUserByPhone :one
SELECT id, name, phone, telegram_chat_id, role, created_at, updated_at 
FROM users 
WHERE phone = $1;

-- name: CreateUser :one
INSERT INTO users (name, phone, telegram_chat_id, role)
VALUES ($1, $2, $3, $4)
RETURNING id, name, phone, telegram_chat_id, role, created_at, updated_at;

-- name: UpdateUserRoleAndChat :one
UPDATE users
SET telegram_chat_id = $2,
    role = $3,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, phone, telegram_chat_id, role, created_at, updated_at;