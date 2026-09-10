package endpoints

import (
	"encoding/json"
	"net/http"

	"domix/backend/internal/auth"
)

type AccountDeletion struct {
	SessionMgr  *auth.SessionManager
	BotUsername string
}

const (
	minPhoneDigits = 9
	maxPhoneDigits = 15
)

func (d *AccountDeletion) Init(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Phone string `json:"phone"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	phone := auth.NormalizePhone(req.Phone)
	if len(phone) < minPhoneDigits || len(phone) > maxPhoneDigits {
		writeAPIError(w, http.StatusBadRequest, "invalid_phone", "that is not a phone number")
		return
	}

	sessionID := d.SessionMgr.InitDeletion(phone)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"session_id":   sessionID,
		"telegram_url": "https://t.me/" + d.BotUsername + "?start=" + sessionID,
	})
}

func (d *AccountDeletion) Status(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("session_id")
	if sessionID == "" {
		writeAPIError(w, http.StatusBadRequest, "missing_session", "missing session_id")
		return
	}

	session := d.SessionMgr.GetStatus(sessionID)

	status := session.Status
	if session.Purpose != auth.PurposeDeletion {
		status = "not_found"
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": status})
}
