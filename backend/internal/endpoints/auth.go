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

// the longest display name we will accept at registration. the same limit products.name gets, and
// for the same reason: it is written to a VARCHAR column and held in memory until the session
// expires, so an unbounded one is a memory cost an anonymous caller controls.
const maxUserNameLen = 150

// the telegram-login handshake's endpoints - kicking off a login attempt, polling for whether it has
// completed - plus the one that tells an already-logged-in app whether its session is still real.
// see internal/auth/session.go for the actual in-memory state machine.
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
	// the same capped decoder every other endpoint uses. this handler was written before that helper
	// existed and kept a bare json.Decoder, which meant `{"name": "<a gigabyte of characters>"}` was
	// read into memory in full and then parked in the session map for ten minutes - the one
	// unauthenticated endpoint in the api, and the only one without a limit.
	if !decodeJSONBody(w, r, &req) {
		return
	}

	// **`admin` is deliberately not accepted here, and must never be added back.**
	//
	// this used to read `req.Role != "shop_owner" && req.Role != "admin"`, which let any caller
	// register themselves as an administrator simply by posting `{"role":"admin"}` - the value
	// travels straight through the telegram handler into CreateUser, and the users.role CHECK
	// constraint allows it, so the account was created and could never be demoted through the app.
	//
	// the role a stranger asks for cannot be a role that grants power over other people's shops.
	// admin is granted out of band, by whoever runs Domix, with SQL against the database - there is
	// no endpoint for it on purpose.
	if req.Role != "shop_owner" {
		req.Role = "customer"
	}

	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		req.Name = "Domix User"
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

// MeResponse is the app's own account, as the server currently sees it.
//
// It carries the role because that is the field most likely to be *stale* on a phone: a customer who
// registers a shop becomes a shop_owner during the Telegram flow, and an app that only ever read its
// role at login would keep hiding the owner screens until the user signed out and back in.
type MeResponse struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Phone string `json:"phone"`
	Role  string `json:"role"`
}

// GET /api/me - "is this session still real, and who am I now?"
//
// **This is what lets the app show a guest screen the moment it opens, rather than the moment the
// user taps something.** A stored JWT proves nothing about the present: it stays cryptographically
// valid for its whole four months whether or not the account behind it still exists. So the app
// hydrates from its cache for a fast first paint and calls this immediately afterwards - and again
// every time it returns to the foreground - and a 401 here is what turns it back into a guest.
//
// The handler body is deliberately thin: auth.RequireAuth has already proved the token and confirmed
// the row exists, and it is the one that answers 401 `account_deleted`. This just reports the row.
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
		// RequireAuth read this same row a moment ago, so no-rows here means the account was deleted
		// in between - rare, but it is the same answer the app already knows how to act on
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

// DELETE /api/me - the user destroys their own account.
//
// **This is a Google Play requirement, not a feature request.** Any app that lets someone create an
// account must let them delete it from inside the app, and must publish a web page describing the
// same thing for people who have already uninstalled. An app without this is rejected at review.
//
// **It is a hard delete, and it deliberately is not a soft one.** The tempting version sets a
// `deleted_at` and hides the row - it keeps the analytics tidy and makes "oops, undo" possible. It
// also means the user asked you to erase their phone number and you kept it, which is the one thing
// the policy exists to prevent. There is nothing here worth keeping either: the account is a name, a
// phone number and a Telegram chat id.
//
// One statement does the whole job because the schema cascades - see the DeleteUser query. The shops
// go, and each shop takes its products, so a deleted owner's pins leave the map in the same
// transaction. That is also why there is no "you must delete your shops first" check: making the
// user dismantle their own account by hand before they may close it is a dark pattern, and Play
// treats a deletion path with obstacles in it as no deletion path at all.
//
// **No confirmation step lives here.** The server does what it is told; the "are you sure" belongs
// on the screen with the button, where the user can still change their mind. An endpoint that
// required a second call would just be a second thing to get wrong.
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

	// the id and nothing else. every other field on this row is the personal data the caller just
	// asked us to forget, and writing it into a log file is keeping a copy in the one place nobody
	// thinks to go back and clean.
	log.Printf("User %d deleted their account", userID)

	// **the JWT this request arrived with is still cryptographically valid, and there is no
	// revocation list.** what stops it is RequireAuth's own existence check: the next request it
	// carries finds no row and answers 401 `account_deleted`, which is the code the app wipes its
	// storage on. so the token outlives the account by exactly one request, and that request fails.
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}
