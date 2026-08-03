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

// "may this caller modify that shop?" is asked in four places - edit shop, delete shop, add a
// product, edit or delete a product - and it was written out inline in the first three. four copies
// of an authorization check is four chances for one of them to be subtly weaker than the others,
// which is the kind of bug nobody notices until someone edits a competitor's shop.

// an authorization failure, carrying everything needed to answer the request. nil means "allowed".
//
// a struct rather than four return values because every caller does the same thing with it - hand
// it to write() and return - and because a plain `error` would lose the http status and the stable
// machine-readable code the flutter app localizes off (see AppLocalizations.shopMutationErrorMessage).
type accessError struct {
	status  int
	code    string
	message string
}

// every error response from these endpoints is the same shape: {"error": "...", "code": "..."}.
// the app is ru/uz only and never displays the english message - it switches on the code.
func writeAPIError(w http.ResponseWriter, status int, code, message string) {
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message, "code": code})
}

func (e *accessError) write(w http.ResponseWriter) {
	writeAPIError(w, e.status, e.code, e.message)
}

// authorizeShopAccess answers whether userID may modify shopID. it is two questions, not one:
//
//  1. is this user a shop_owner (or admin) at all? looked up fresh from the database every time,
//     because internal/auth/jwt.go deliberately carries no role claim - a token lives a year and a
//     role can change inside that year, so a claim could assert a role the user no longer has.
//  2. do they own *this particular* shop? without it, question 1 alone would let any shop owner in
//     the country edit, restock or delete a competitor's shop.
//
// an admin passes the second question by definition, which is what the `role != "admin"` guard on
// the ownership comparison is doing.
//
// returns nil when the caller is allowed.
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
		// a genuinely missing shop and a database that just fell over are very different events, and
		// reporting the second as "shop not found" would send the owner hunting for a problem in
		// their own data while the real incident goes unlogged
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
