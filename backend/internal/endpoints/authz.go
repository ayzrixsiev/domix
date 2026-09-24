package endpoints

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
)

// an authorization failure carrying everything needed to answer the request; nil means "allowed".
// a struct rather than an `error` because the http status and the stable machine-readable code the
// app localizes off (AppLocalizations.shopMutationErrorMessage) both have to survive the return.
type accessError struct {
	status  int
	code    string
	message string
}

// every error is the same shape: {"error", "code"}. the app is ru/uz only and never shows the
// english message - it switches on the code.
func writeAPIError(w http.ResponseWriter, status int, code, message string) {
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message, "code": code})
}

func (e *accessError) write(w http.ResponseWriter) {
	writeAPIError(w, e.status, e.code, e.message)
}

// authorizeShopAccess answers whether userID may modify shopID, and it is two questions: is this a
// shop owner at all (read from the database every time - jwt.go carries no role claim, and a token
// outlives a role change), and do they own *this* shop. an admin passes the second by definition.
func authorizeShopAccess(ctx context.Context, q *db.Queries, userID, shopID int64) *accessError {
	role, err := q.GetUserRole(ctx, userID)
	if err != nil {
		log.Printf("CRITICAL: failed to look up role for user %d: %v", userID, err)
		return &accessError{http.StatusInternalServerError, "server_error", "failed to verify permissions"}
	}
	if role != "shop_owner" && role != "admin" {
		return &accessError{http.StatusForbidden, "forbidden_role", "only shop owners can modify a shop"}
	}

	ownerID, err := q.GetShopOwner(ctx, shopID)
	if err != nil {
		// a missing shop and a database that fell over are different events: reporting the second as
		// "not found" sends the owner hunting through their own data while the incident goes unlogged
		if errors.Is(err, pgx.ErrNoRows) {
			return &accessError{http.StatusNotFound, "shop_not_found", "shop not found"}
		}
		log.Printf("CRITICAL: failed to look up owner of shop %d: %v", shopID, err)
		return &accessError{http.StatusInternalServerError, "server_error", "failed to verify shop ownership"}
	}
	if role != "admin" && ownerID != userID {
		return &accessError{http.StatusForbidden, "not_owner", "you do not own this shop"}
	}

	return nil
}
