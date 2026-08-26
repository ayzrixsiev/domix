// file answers a question: is this user's jwt really created by us? if yes, hands over user id
// or in other words authorization process

package auth

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5"

	"domix/backend/internal/dbctx"
)

// new type of variable unique for this file to hold user id without any possiblity to mistaken it and overwrite in another file
type contextKey string

// declaration of this variable
const userIDContextKey contextKey = "userID"

const bearerPrefix = "Bearer "

type UserStore interface {
	GetUserRole(ctx context.Context, id int64) (string, error)
}

// wraps a handler (http endpoints) so it only runs once we've confirmed the caller sent a valid jwt and that the account that jwt names still exists.
func RequireAuth(jwtSecret string, users UserStore, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization") // store token here

		if !strings.HasPrefix(authHeader, bearerPrefix) { // tokens coming from flutter has Bearer word before them
			respondUnauthorized(w, "unauthorized", "missing bearer token") // check whether we have it there
			return
		}

		tokenString := strings.TrimPrefix(authHeader, bearerPrefix) // chop that Bearer word in the string
		claims, err := ValidateJWT(tokenString, jwtSecret)          // validate, if true returns id and phone number
		if err != nil {
			respondUnauthorized(w, "unauthorized", "invalid or expired token")
			return
		}

		ctx, cancel := dbctx.WithTimeout(r.Context())
		defer cancel()

		if _, err := users.GetUserRole(ctx, claims.UserID); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				respondUnauthorized(w, "account_deleted", "this account no longer exists")
				return
			}
			log.Printf("CRITICAL: cannot verify user %d: %v", claims.UserID, err)
			respondServiceUnavailable(w)
			return
		}

		// wrap original context created by the net/http package (which is check is user conn drops), and add a sticky note to it - user id
		authed := context.WithValue(r.Context(), userIDContextKey, claims.UserID)
		// run the wrapped function and hand it context with sticky note
		next(w, r.WithContext(authed))
	}
}

// reads back the user id that RequireAuth attached as sticky note to the request context
func UserIDFromContext(ctx context.Context) (int64, bool) {
	userID, ok := ctx.Value(userIDContextKey).(int64)
	return userID, ok
}

// func to send back to flutter one json response: "you are not allowed in".
// carries a machine-readable `code` alongside the english message for flutter to show appropriate error message
func respondUnauthorized(w http.ResponseWriter, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	json.NewEncoder(w).Encode(map[string]string{"code": code, "error": message})
}

// a failed user lookup is our problem, not the caller's, so it must not come back as a 401 - the app
// treats 401 as "log out", and a minute of database trouble would otherwise sign out every user.
func respondServiceUnavailable(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusServiceUnavailable)
	json.NewEncoder(w).Encode(map[string]string{
		"code":  "service_unavailable",
		"error": "could not verify the session, try again",
	})
}
