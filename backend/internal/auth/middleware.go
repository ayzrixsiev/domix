// file answers a question: is this user's jwt really created by us? if yes, hands over user id
// or in other words authorization process

package auth

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
)

// new type of variable unique for this file to hold user id without any possiblity to mistaken in and overwrite in another file
type contextKey string

// declaration of this file
const userIDContextKey contextKey = "userID"

const bearerPrefix = "Bearer "

// wraps a handler (http endpoints) so it only runs once we've confirmed the caller sent a valid jwt
func RequireAuth(jwtSecret string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization") // store token here

		if !strings.HasPrefix(authHeader, bearerPrefix) {  // tokens coming from flutter has Bearer word before them
			respondUnauthorized(w, "missing bearer token") // check whether we have it there
			return
		}

		tokenString := strings.TrimPrefix(authHeader, bearerPrefix) // chop that Bearer word in the string
		claims, err := ValidateJWT(tokenString, jwtSecret) // validate, if true returns id and phone number
		if err != nil {
			respondUnauthorized(w, "invalid or expired token")
			return
		}
		// wrap original context created by the net/http package (which is check is user conn drops), and add a sticky note to it - user id
		ctx := context.WithValue(r.Context(), userIDContextKey, claims.UserID)
		// run the wrapped function and hand it context with sticky note
		next(w, r.WithContext(ctx))
	}
}

// reads back the user id that RequireAuth attached as sticky note to the request context
func UserIDFromContext(ctx context.Context) (int64, bool) {
	userID, ok := ctx.Value(userIDContextKey).(int64)
	return userID, ok
}

// func to send back to flutter one json response: "you are not allowed in"
func respondUnauthorized(w http.ResponseWriter, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}
