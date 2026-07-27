# SQLC
sqlc generate, not only generates sql-go functions, but also creates methods (AddUser, CreateShop etc) that can be used through connection pool


# Interface
interface in go is a checklist of required abilities that needs to be satisfied in order to be assigned to a variable of that interface type.
example

```go

package db

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// interface: checklist
type DBTX interface {
	Exec(context.Context, string, ...interface{}) (pgconn.CommandTag, error)
	Query(context.Context, string, ...interface{}) (pgx.Rows, error)
	QueryRow(context.Context, string, ...interface{}) pgx.Row
}

// struct that will hold a connection pool inside db type of interace DBTX
type Queries struct {
	db DBTX
}

// assign a pool to the db and return address to the struct which holds the connection pool
func New(db DBTX) *Queries {
	return &Queries{db: db}
}

// wrapped a normal connection with pgx.Tx which can perform several sql queries, not once unlike others
func (q *Queries) WithTx(tx pgx.Tx) *Queries {
	return &Queries{
		db: tx,
	}
}

```

# http.HandleFunc
this is a method that does: "when the request comes in for this URL, call this function". the structure of this method: http.HandleFunc(pattern, handler). for example:

```go
http.HandleFunc("/api/auth/init", endpoints.WithCORS("POST", authEndpoints.Init))
```

# HTTP endpoint hit structure

```go
POST /api/shops HTTP/1.1        ← request line
Host: 192.168.1.5:8080          ←|	
Content-Type: application/json  ←| headers (metadata)
Authorization: Bearer ...       ←|
                                ← blank line (mandatory separator between headers and actual body - content)
{"name":"My Shop", ...}         ← body (the actual content)
```

# Channels
Channels in go is like a pipe that sends signals to goroutines and let's them talk to each other