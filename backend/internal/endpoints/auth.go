package endpoints

import (
	"encoding/json"
	"net/http"

	"domix/backend/internal/auth"
)

// the telegram-login handshake's two endpoints: kicking off a login attempt, and polling for
// whether it has completed. see internal/auth/session.go for the actual in-memory state machine.
type Auth struct {
	SessionMgr  *auth.SessionManager
	BotUsername string
}

// POST /api/auth/init - flutter calls this to start a login session and get a telegram deep link with sessID back
func (a *Auth) Init(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name string `json:"name"`
		Role string `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "invalid json body"})
		return
	}

	if req.Role != "shop_owner" && req.Role != "admin" {
		req.Role = "customer"
	}
	if req.Name == "" {
		req.Name = "Domix User"
	}

	// create session ticket with name, role and session id
	sessionID := a.SessionMgr.InitSession(req.Name, req.Role)

	w.WriteHeader(http.StatusOK)
	// send back to flutter the link to telegram with the session id embedded inside it
	json.NewEncoder(w).Encode(map[string]string{
		"session_id": sessionID,
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
