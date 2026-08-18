-- name: GetUserByPhone :one
SELECT id, name, phone, telegram_chat_id, role, created_at, updated_at
FROM users
WHERE phone = $1;

-- name: GetUserRole :one
SELECT role FROM users WHERE id = $1;

-- name: GetUserByID :one
-- backs GET /api/me, which the app calls on launch and whenever it comes back to the foreground.
--
-- it exists so the app can find out its session is dead *before* the user taps anything. the token
-- alone cannot tell it: a JWT is valid until it expires no matter what happened to the account, so
-- without asking the server a deleted user sees their own profile screen until they happen to press
-- something. this is also where a role change (customer -> shop_owner) reaches an app that has been
-- installed since before the upgrade.
SELECT id, name, phone, role FROM users WHERE id = $1;

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

-- name: DeleteUser :exec
-- backs DELETE /api/me. the account and everything hanging off it, in one statement.
--
-- one statement is all it takes because every child relation was declared ON DELETE CASCADE back in
-- migration 000001: this row goes, its shops go with it, and each shop takes its products. writing
-- the three deletes by hand would be a second description of the same rule, and the two would
-- eventually disagree - the schema is the one that postgres actually enforces.
--
-- :exec, not :execrows, and that is a deliberate choice about what DELETE means here. the caller is
-- asking for a state ("this account no longer exists"), not for an event, so a row that was already
-- gone is a success, not a 404. RequireAuth read the row a moment earlier anyway; the only way to
-- reach a no-op is deleting twice from two devices at once, and both of those users got what they
-- asked for.
DELETE FROM users WHERE id = $1;