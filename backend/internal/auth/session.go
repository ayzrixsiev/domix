package auth

import (
	"sync"
)

// SessionData holds the real-time login state for flutter to poll
type SessionData struct {
	Status string `json:"status"` // "pending", "success", or "not_found"
	Phone  string `json:"phone,omitempty"`
	Token  string `json:"token,omitempty"` // JWT token here
}

// blueprint of data during active session
type SessionManager struct {
	// maps telegram ChatID -> SessionID (e.g., 12345678 -> "session_12345")
	chatToSession sync.Map

	// maps SessionID -> SessionData (e.g., "session_12345" -> {Status: "pending"})
	sessions sync.Map
}

// initialize our active session blueprint data and hand over it's address
func NewSessionManager() *SessionManager {
	return &SessionManager{}
}

// RegisterChat links a Telegram user to a Flutter session ID when they press /start
func (sm *SessionManager) RegisterChat(chatID int64, sessionID string) {
	sm.chatToSession.Store(chatID, sessionID)
	sm.sessions.Store(sessionID, SessionData{Status: "pending"})
}

// CompleteSession is called when the user clicks "Share Contact"
func (sm *SessionManager) CompleteSession(chatID int64, phone string) (string, bool) {
	// 1. Find which Flutter session belongs to this Telegram chat
	val, exists := sm.chatToSession.Load(chatID)
	if !exists {
		return "", false
	}
	sessionID := val.(string)

	// 2. For your investor MVP, we generate a mock JWT token string
	mockJWT := "jwt_token_" + phone + "_verified_domix_mvp"

	// 3. Mark the session as SUCCESS so Flutter opens the map!
	sm.sessions.Store(sessionID, SessionData{
		Status: "success",
		Phone:  phone,
		Token:  mockJWT,
	})

	// Optional: clean up the chat mapping so they can't re-use it immediately
	sm.chatToSession.Delete(chatID)

	return sessionID, true
}

// GetStatus is called by Flutter every 2 seconds via GET /api/auth/status
func (sm *SessionManager) GetStatus(sessionID string) SessionData {
	val, exists := sm.sessions.Load(sessionID)
	if !exists {
		return SessionData{Status: "not_found"}
	}
	return val.(SessionData)
}