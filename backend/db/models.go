/*
sqlc translated postgresql tables into go language, so that our backend knows how to hold and send data properly
*/

package db

import (
	"github.com/jackc/pgx/v5/pgtype"
)

type Product struct {
	ID        int64              `json:"id"`
	ShopID    int64              `json:"shop_id"`
	Name      string             `json:"name"`
	Price     int64              `json:"price"`
	Category  string             `json:"category"`
	CreatedAt pgtype.Timestamptz `json:"created_at"`
	UpdatedAt pgtype.Timestamptz `json:"updated_at"`
}

type Shop struct {
	ID              int64              `json:"id"`
	UserID          int64              `json:"user_id"`
	Name            string             `json:"name"`
	Address         string             `json:"address"`
	Rating          pgtype.Numeric     `json:"rating"`
	AveragePaycheck int32              `json:"average_paycheck"`
	Location        interface{}        `json:"location"`
	CreatedAt       pgtype.Timestamptz `json:"created_at"`
	UpdatedAt       pgtype.Timestamptz `json:"updated_at"`
}

type User struct {
	ID        int64              `json:"id"`
	Name      string             `json:"name"`
	Phone     string             `json:"phone"`
	CreatedAt pgtype.Timestamptz `json:"created_at"`
	UpdatedAt pgtype.Timestamptz `json:"updated_at"`
}
