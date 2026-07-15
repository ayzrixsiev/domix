package auth

import (
	"errors"
	"sync"
	"time"
)

// SessionData holds the real-time login state for flutter to poll
type SessionData struct {
	Status string `json:"status"` 		   // "pending", "success", or "not_found"
	Phone  string `json:"phone,omitempty"`
	Token  string `json:"token,omitempty"` // JWT token here
	CreatedAt time.Time `json:"-"`		   // we use - to hide this internal timestamp from json response
}

// blueprint of data during active session
type SessionManager struct {
	// maps telegram ChatID -> SessionID
	chatToSession sync.Map

	// maps SessionID -> SessionData
	sessions sync.Map
}

// initialize in ram our active session blueprint data and hand over it's address
func NewSessionManager() *SessionManager {
	sm := &SessionManager{}

	// production Shield: run a background thread (goroutine) that wakes up every 
	// 1 minute and clears out any sessions older than 10 minutes.
	go sm.startCleanupSweeper(1*time.Minute, 10*time.Minute)

	return sm
}

// SessionManager object's method (RegisterChat)
// RegisterChat links a Telegram user to a Flutter session ID when /start button pressed
func (sm *SessionManager) RegisterChat(chatID int64, sessionID string) {
	sm.chatToSession.Store(chatID, sessionID)
	sm.sessions.Store(sessionID, SessionData{
		Status: "pending",
		CreatedAt: time.Now(),
	})
}

// CompleteSession creates jwt token and requires userID for it 
func (sm *SessionManager) CompleteSession(chatID int64, userID int64, phone string, role string, jwtSecret string) (string, error) {
	// 1. find which Flutter session belongs to this Telegram chat
	val, exists := sm.chatToSession.Load(chatID)
	if !exists {
		return "", errors.New("no active flutter session found for this chat ID")
	}
	sessionID := val.(string)

	// 2. generate a real, cryptographically signed JWT token!
	JWT, err := GenerateJWT(userID, phone, role, jwtSecret)
	if err != nil {
		return "", err
	}

	// 3. mark the session as SUCCESS with the real token
	sm.sessions.Store(sessionID, SessionData{
		Status: "success",
		Phone:  phone,
		Token:  JWT,
		CreatedAt: time.Now(),
	})

	// 4. clean up the chat mapping so it cannot be re-used
	sm.chatToSession.Delete(chatID)

	return sessionID, nil
}


func (sm *SessionManager) startCleanupSweeper(interval, ttl time.Duration) {
	ticker := time.NewTicker(interval)
	for range ticker.C {
		now := time.Now()
		sm.sessions.Range(func(key, value interface{}) bool {
			sessionID := key.(string)
			data := value.(SessionData)

			// if the session has been sitting in RAM longer than our limit (TTL), destroy it
			if now.Sub(data.CreatedAt) > ttl {
				sm.sessions.Delete(sessionID)
			}
			return true // return true to keep iterating through all map items
		})
	}
}

// GetStatus is called by Flutter every 2 seconds via GET /api/auth/status
func (sm *SessionManager) GetStatus(sessionID string) SessionData {
	val, exists := sm.sessions.Load(sessionID)
	if !exists {
		return SessionData{Status: "not_found"}
	}
	return val.(SessionData)
}