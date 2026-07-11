/*
sqlc built ready to use go functions out of raw sql queries from user.sql
*/

package db

import (
	"context"
)

// SIGN UP
const createUser = `-- name: CreateUser :one
INSERT INTO users (name, phone)
VALUES ($1, $2)
RETURNING id, name, phone, created_at, updated_at
`

// several arguments defined inside struct
type CreateUserParams struct {
	Name  string `json:"name"`
	Phone string `json:"phone"`
}

// q *Queries lets CreateUser action to interact with the db, ctx arg watches whether user is connected to the internet during sign up
func (q *Queries) CreateUser(ctx context.Context, arg CreateUserParams) (User, error) {
	row := q.db.QueryRow(ctx, createUser, arg.Name, arg.Phone) // connects to the db using pgx/v5, drops $1 and 2$ args to the createUser sql query
	var i User // initialize data struct defined in models.go
	err := row.Scan( // get the whole returning data from postgresql table when user created and save it in backend - User struct i
		&i.ID,
		&i.Name,
		&i.Phone,
		&i.CreatedAt,
		&i.UpdatedAt,
	)
	return i, err
}


// LOG IN
const getUserByPhone = `-- name: GetUserByPhone :one
SELECT id, name, phone, created_at, updated_at 
FROM users 
WHERE phone = $1
`

func (q *Queries) GetUserByPhone(ctx context.Context, phone string) (User, error) {
	row := q.db.QueryRow(ctx, getUserByPhone, phone)
	var i User
	err := row.Scan(
		&i.ID,
		&i.Name,
		&i.Phone,
		&i.CreatedAt,
		&i.UpdatedAt,
	)
	return i, err
}
