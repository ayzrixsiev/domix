package db

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type DBTX interface {
	Exec(context.Context, string, ...interface{}) (pgconn.CommandTag, error)
	Query(context.Context, string, ...interface{}) (pgx.Rows, error)
	QueryRow(context.Context, string, ...interface{}) pgx.Row
}

// factory to create connections between backend and database
func New(db DBTX) *Queries {
	return &Queries{db: db}
}

// tool to send go-sqlc functions to the db using connections from factory
type Queries struct {
	db DBTX
}

// ACID transaction (fail or success) for multiple sql operations
func (q *Queries) WithTx(tx pgx.Tx) *Queries {
	return &Queries{
		db: tx,
	}
}
