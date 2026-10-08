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

-- name: UpdateUserPhone :one
-- separate from UpdateUserProfile because phone is the identity column: UNIQUE, and what every login
-- looks an account up by, so the one write that touches it is the one the code flow guards.
UPDATE users
SET phone = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, phone, role, created_at, updated_at;

-- name: DeleteUser :exec
DELETE FROM users WHERE id = $1;

-- name: ListUploadedImagesOfUser :many
-- the photos an owner uploaded, read before the account goes: the delete cascades through shops and
-- products, and after it nothing names these files any more
SELECT p.image_path::text AS image_path
FROM products p
JOIN shops s ON s.id = p.shop_id
WHERE s.user_id = $1 AND p.image_path LIKE 'shops/uploads/%';
