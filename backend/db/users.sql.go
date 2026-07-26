package db

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"
)

const createUser = `-- name: CreateUser :one
INSERT INTO users (name, phone, telegram_chat_id, role)
VALUES ($1, $2, $3, $4)
RETURNING id, name, phone, telegram_chat_id, role, created_at, updated_at
`

type CreateUserParams struct {
	Name           pgtype.Text `json:"name"`
	Phone          string      `json:"phone"`
	TelegramChatID pgtype.Int8 `json:"telegram_chat_id"`
	Role           string      `json:"role"`
}

type CreateUserRow struct {
	ID             int64              `json:"id"`
	Name           pgtype.Text        `json:"name"`
	Phone          string             `json:"phone"`
	TelegramChatID pgtype.Int8        `json:"telegram_chat_id"`
	Role           string             `json:"role"`
	CreatedAt      pgtype.Timestamptz `json:"created_at"`
	UpdatedAt      pgtype.Timestamptz `json:"updated_at"`
}

func (q *Queries) CreateUser(ctx context.Context, arg CreateUserParams) (CreateUserRow, error) {
	row := q.db.QueryRow(ctx, createUser,
		arg.Name,
		arg.Phone,
		arg.TelegramChatID,
		arg.Role,
	)
	var i CreateUserRow
	err := row.Scan(
		&i.ID,
		&i.Name,
		&i.Phone,
		&i.TelegramChatID,
		&i.Role,
		&i.CreatedAt,
		&i.UpdatedAt,
	)
	return i, err
}

const getUserByPhone = `-- name: GetUserByPhone :one
SELECT id, name, phone, telegram_chat_id, role, created_at, updated_at
FROM users
WHERE phone = $1
`

type GetUserByPhoneRow struct {
	ID             int64              `json:"id"`
	Name           pgtype.Text        `json:"name"`
	Phone          string             `json:"phone"`
	TelegramChatID pgtype.Int8        `json:"telegram_chat_id"`
	Role           string             `json:"role"`
	CreatedAt      pgtype.Timestamptz `json:"created_at"`
	UpdatedAt      pgtype.Timestamptz `json:"updated_at"`
}

func (q *Queries) GetUserByPhone(ctx context.Context, phone string) (GetUserByPhoneRow, error) {
	row := q.db.QueryRow(ctx, getUserByPhone, phone)
	var i GetUserByPhoneRow
	err := row.Scan(
		&i.ID,
		&i.Name,
		&i.Phone,
		&i.TelegramChatID,
		&i.Role,
		&i.CreatedAt,
		&i.UpdatedAt,
	)
	return i, err
}

const getUserRole = `-- name: GetUserRole :one
SELECT role FROM users WHERE id = $1
`

func (q *Queries) GetUserRole(ctx context.Context, id int64) (string, error) {
	row := q.db.QueryRow(ctx, getUserRole, id)
	var role string
	err := row.Scan(&role)
	return role, err
}

const updateUserProfile = `-- name: UpdateUserProfile :one
UPDATE users
SET name = $2,
    telegram_chat_id = $3,
    role = $4,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, phone, telegram_chat_id, role, created_at, updated_at
`

type UpdateUserProfileParams struct {
	ID             int64       `json:"id"`
	Name           pgtype.Text `json:"name"`
	TelegramChatID pgtype.Int8 `json:"telegram_chat_id"`
	Role           string      `json:"role"`
}

type UpdateUserProfileRow struct {
	ID             int64              `json:"id"`
	Name           pgtype.Text        `json:"name"`
	Phone          string             `json:"phone"`
	TelegramChatID pgtype.Int8        `json:"telegram_chat_id"`
	Role           string             `json:"role"`
	CreatedAt      pgtype.Timestamptz `json:"created_at"`
	UpdatedAt      pgtype.Timestamptz `json:"updated_at"`
}

func (q *Queries) UpdateUserProfile(ctx context.Context, arg UpdateUserProfileParams) (UpdateUserProfileRow, error) {
	row := q.db.QueryRow(ctx, updateUserProfile,
		arg.ID,
		arg.Name,
		arg.TelegramChatID,
		arg.Role,
	)
	var i UpdateUserProfileRow
	err := row.Scan(
		&i.ID,
		&i.Name,
		&i.Phone,
		&i.TelegramChatID,
		&i.Role,
		&i.CreatedAt,
		&i.UpdatedAt,
	)
	return i, err
}
