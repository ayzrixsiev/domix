package endpoints

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
)

const maxUserNameLen = 150

// /api/me: the caller reading, editing or destroying their own account. Signing in lives in
// endpoints.PhoneAuth, and moving an account onto a new number in phone_change.go.
type Auth struct {
	Queries *db.Queries

	// only DeleteMe needs it: an account's photos go with the account - see eraseAccount
	Images imagestore.Storage
}

// the account, as GET /api/me and the login both answer with it
type MeResponse struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Phone string `json:"phone"`
	Role  string `json:"role"`
}

// dispatches /api/me by method - all three act on the caller's own account, behind one RequireAuth
// applied where the route is registered. the number is not editable here: moving an account onto a
// different phone needs that phone proven first (PhoneAuth.RequestPhoneChangeCode).
func (a *Auth) RouteMe(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.Me(w, r)
	case http.MethodPatch:
		a.UpdateMe(w, r)
	case http.MethodDelete:
		a.DeleteMe(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// PATCH /api/me - rename the caller, and let a customer become a shop owner.
//
// **a role only ever goes up, and only from `customer`** (the same rule PhoneAuth.upsertUser
// applies): a shop owner who demoted themselves would keep every shop while losing the right to
// edit any of them. `admin` is refused by the same branch - an admin is made in the database.
func (a *Auth) UpdateMe(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
		return
	}

	// pointers, so an omitted field is distinguishable from one deliberately set to empty
	var req struct {
		Name *string `json:"name"`
		Role *string `json:"role"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	current, err := a.Queries.GetUserByID(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusUnauthorized, "account_deleted", "this account no longer exists")
			return
		}
		log.Printf("CRITICAL: failed to load user %d before a profile edit: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the account")
		return
	}

	name := current.Name.String
	if req.Name != nil {
		name = strings.TrimSpace(*req.Name)
		if name == "" {
			writeAPIError(w, http.StatusBadRequest, "name_required", "a name is required")
			return
		}
		if utf8.RuneCountInString(name) > maxUserNameLen {
			writeAPIError(w, http.StatusBadRequest, "name_too_long", "name is longer than the maximum allowed length")
			return
		}
	}

	role := current.Role
	if req.Role != nil && *req.Role != current.Role {
		if current.Role != "customer" || *req.Role != "shop_owner" {
			writeAPIError(w, http.StatusForbidden, "role_locked", "this role cannot be changed")
			return
		}
		role = "shop_owner"
	}

	updated, err := a.Queries.UpdateUserProfile(ctx, db.UpdateUserProfileParams{
		ID:   userID,
		Name: pgtype.Text{String: name, Valid: name != ""},
		Role: role,
	})
	if err != nil {
		log.Printf("CRITICAL: failed to update the profile of user %d: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not save the profile")
		return
	}

	if role != current.Role {
		log.Printf("User %d became a %s", userID, role)
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(meResponseOf(updated))
}

// decides which screen to show and what to shop in profile page: user and its credentials or guest
func (a *Auth) Me(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	user, err := a.Queries.GetUserByID(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusUnauthorized, "account_deleted", "this account no longer exists")
			return
		}
		log.Printf("CRITICAL: failed to load user %d: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the account")
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(MeResponse{
		ID:    user.ID,
		Name:  user.Name.String,
		Phone: user.Phone,
		Role:  user.Role,
	})
}

func (a *Auth) DeleteMe(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	if err := eraseAccount(ctx, a.Queries, a.Images, userID); err != nil {
		log.Printf("CRITICAL: failed to delete user %d: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the account")
		return
	}

	log.Printf("User %d deleted their account", userID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}
