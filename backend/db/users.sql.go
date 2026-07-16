package db

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"
)

// sign up
const createUser = `-- name: CreateUser :one
INSERT INTO users (name, phone, telegram_chat_id, role)
VALUES ($1, $2, $3, $4)
RETURNING id, name, phone, telegram_chat_id, role, created_at, updated_at
`
// blueprint for createUser sql query
type CreateUserParams struct {
	Name           pgtype.Text `json:"name"`
	Phone          string      `json:"phone"`
	TelegramChatID pgtype.Int8 `json:"telegram_chat_id"`
	Role           string      `json:"role"`
}

// blueprint for the user returned after createUser sql query to save in backend
type CreateUserRow struct {
	ID             int64              `json:"id"`
	Name           pgtype.Text        `json:"name"`
	Phone          string             `json:"phone"`
	TelegramChatID pgtype.Int8        `json:"telegram_chat_id"`
	Role           string             `json:"role"`
	CreatedAt      pgtype.Timestamptz `json:"created_at"`
	UpdatedAt      pgtype.Timestamptz `json:"updated_at"`
}

// insert a user and save in backend
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

// log in
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

const updateUserRoleAndChat = `-- name: UpdateUserRoleAndChat :one
UPDATE users
SET telegram_chat_id = $2,
    role = $3,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, name, phone, telegram_chat_id, role, created_at, updated_at
`

type UpdateUserRoleAndChatParams struct {
	ID             int64       `json:"id"`
	TelegramChatID pgtype.Int8 `json:"telegram_chat_id"`
	Role           string      `json:"role"`
}

type UpdateUserRoleAndChatRow struct {
	ID             int64              `json:"id"`
	Name           pgtype.Text        `json:"name"`
	Phone          string             `json:"phone"`
	TelegramChatID pgtype.Int8        `json:"telegram_chat_id"`
	Role           string             `json:"role"`
	CreatedAt      pgtype.Timestamptz `json:"created_at"`
	UpdatedAt      pgtype.Timestamptz `json:"updated_at"`
}

func (q *Queries) UpdateUserRoleAndChat(ctx context.Context, arg UpdateUserRoleAndChatParams) (UpdateUserRoleAndChatRow, error) {
	row := q.db.QueryRow(ctx, updateUserRoleAndChat, arg.ID, arg.TelegramChatID, arg.Role)
	var i UpdateUserRoleAndChatRow
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
