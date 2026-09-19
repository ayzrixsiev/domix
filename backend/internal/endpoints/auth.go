package endpoints

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
)

const maxUserNameLen = 150

// the telegram-login handshake's endpoints - kicking off a login attempt, polling for whether it has
// completed - plus the one that tells an already-logged-in app whether its session is still real.
//
// **Init and Status are SUPERSEDED by endpoints.PhoneAuth** (POST /api/auth/request-code and
// /api/auth/verify). They are still registered only because the apk currently installed on the
// founder's phone calls them; once the flutter side is on the code flow, delete them, the
// SessionMgr and BotUsername fields, and internal/telegram with them. RouteMe/Me/DeleteMe stay -
// they were never part of the handshake.
type Auth struct {
	Queries     *db.Queries
	SessionMgr  *auth.SessionManager
	BotUsername string
}

// POST /api/auth/init - flutter calls this to start a login session and get a telegram deep link with sessID back
func (a *Auth) Init(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name string `json:"name"`
		Role string `json:"role"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	if req.Role != "shop_owner" {
		req.Role = "customer"
	}

	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		req.Name = defaultUserName
	}
	if utf8.RuneCountInString(req.Name) > maxUserNameLen {
		writeAPIError(w, http.StatusBadRequest, "name_too_long",
			"name is longer than the maximum allowed length")
		return
	}

	// create session ticket with name, role and session id
	sessionID := a.SessionMgr.InitSession(req.Name, req.Role)

	w.WriteHeader(http.StatusOK)
	// send back to flutter the link to telegram with the session id embedded inside it
	json.NewEncoder(w).Encode(map[string]string{
		"session_id":   sessionID,
		"telegram_url": "https://t.me/" + a.BotUsername + "?start=" + sessionID,
	})
}

// GET /api/auth/status - flutter polls this every ~2s to see whether login completed and get the jwt
func (a *Auth) Status(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("session_id")
	if sessionID == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "missing session_id"})
		return
	}

	statusData := a.SessionMgr.GetStatus(sessionID)
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(statusData)
}

// what we are returning to the flutter after user validation
type MeResponse struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Phone string `json:"phone"`
	Role  string `json:"role"`
}


// dispatches /api/me by method. both read or destroy the caller's own account, so both sit behind
// the same RequireAuth - which is applied once where the route is registered, rather than twice
// here.
func (a *Auth) RouteMe(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.Me(w, r)
	case http.MethodDelete:
		a.DeleteMe(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
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

	if err := a.Queries.DeleteUser(ctx, userID); err != nil {
		log.Printf("CRITICAL: failed to delete user %d: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the account")
		return
	}

	log.Printf("User %d deleted their account", userID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}
