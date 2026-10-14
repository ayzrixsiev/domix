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

type contextKey string

const userIDContextKey contextKey = "userID"
const bearerPrefix = "Bearer "

type UserStore interface {
	GetUserRole(ctx context.Context, id int64) (string, error)
}

// runs a handler only once the caller's jwt is valid *and* the account it names still exists - the
// second half is a live database read, so a deleted account stops working immediately
func RequireAuth(jwtSecret string, users UserStore, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")

		if !strings.HasPrefix(authHeader, bearerPrefix) {
			respondUnauthorized(w, "unauthorized", "missing bearer token")
			return
		}

		tokenString := strings.TrimPrefix(authHeader, bearerPrefix)
		claims, err := ValidateJWT(tokenString, jwtSecret)
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

		// the user id rides on the context from here, which is what every handler authorizes on
		authed := context.WithValue(r.Context(), userIDContextKey, claims.UserID)
		next(w, r.WithContext(authed))
	}
}

// UserIDFromRequest reads the account id off the Authorization header, verifying the signature but
// touching no database. for the rate limiter, which runs *before* RequireAuth and only needs a stable
// key: a forged token fails the signature check and falls back to the caller's address.
func UserIDFromRequest(r *http.Request, jwtSecret string) (int64, bool) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, bearerPrefix) {
		return 0, false
	}
	claims, err := ValidateJWT(strings.TrimPrefix(header, bearerPrefix), jwtSecret)
	if err != nil {
		return 0, false
	}
	return claims.UserID, true
}

func UserIDFromContext(ctx context.Context) (int64, bool) {
	userID, ok := ctx.Value(userIDContextKey).(int64)
	return userID, ok
}

// carries a machine-readable `code` next to the english message - the app switches on the code
func respondUnauthorized(w http.ResponseWriter, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	json.NewEncoder(w).Encode(map[string]string{"code": code, "error": message})
}

// a failed lookup is our problem, not the caller's: the app treats 401 as "log out", so a minute of
// database trouble would otherwise sign every user out
func respondServiceUnavailable(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusServiceUnavailable)
	json.NewEncoder(w).Encode(map[string]string{
		"code":  "service_unavailable",
		"error": "could not verify the session, try again",
	})
}
