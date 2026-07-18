package auth

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"sync"
	"time"
)

// holds the real-time login data and it's state
type SessionData struct {
	Status    string    `json:"status"`          // "pending", "success", or "not_found"
	Name      string    `json:"name,omitempty"`
	Role      string    `json:"role,omitempty"`
	Phone     string    `json:"phone,omitempty"`
	Token     string    `json:"token,omitempty"`
	CreatedAt time.Time `json:"-"`               // we use - to hide this internal timestamp from json response
}

// blueprint of data during active session
type SessionManager struct {
	chatToSession sync.Map // maps telegram ChatID -> SessionID
	sessions      sync.Map // maps SessionID -> SessionData
}

// initialize in ram our active session blueprint and hand over its address to use its methods
func NewSessionManager() *SessionManager {
	sm := &SessionManager{}

	// shield: run a background thread (goroutine) that wakes up every 1 minute and clears out any sessions older than 10 minutes.
	go sm.startCleanupSweeper(1*time.Minute, 10*time.Minute)

	return sm
}

// func called when flutter hits POST /api/auth/init and sends us json with collected data - name and role
func (sm *SessionManager) InitSession(name string, role string) string {
	// generate a random 8-character hex string (e.g., "sess_a1b2c3d4")
	bytes := make([]byte, 4)
	rand.Read(bytes)
	sessionID := "sess_" + hex.EncodeToString(bytes)

	// save their custom name and role in ram safely
	sm.sessions.Store(sessionID, SessionData{
		Status:    "pending",
		Name:      name,
		Role:      role,
		CreatedAt: time.Now(),
	})

	return sessionID
}

// when /start button pressed in tg we link sessionID with telegram chatID, and track from which chat expect user's phone number
func (sm *SessionManager) LinkChat(chatID int64, sessionID string) bool {
	// make sure the session actually exists in RAM first
	if _, exists := sm.sessions.Load(sessionID); !exists {
		return false
	}
	sm.chatToSession.Store(chatID, sessionID)
	return true
}

// when /phone button pressed we retrieve role, name and sessionID
func (sm *SessionManager) GetPendingSession(chatID int64) (sessionID string, name string, role string, exists bool) {
	// FIXED: Added := operator
	val, found := sm.chatToSession.Load(chatID)
	if !found {
		return "", "", "customer", false
	}
	sID := val.(string)

	sessionVal, sFound := sm.sessions.Load(sID)
	if !sFound {
		return sID, "", "customer", false
	}

	data := sessionVal.(SessionData)

	return sID, data.Name, data.Role, true
}

// func that creates jwt token and return SessionData struct with full info
func (sm *SessionManager) CompleteSession(chatID int64, userID int64, phone string, role string, jwtSecret string) (string, error) {
	// find which Flutter session belongs to this Telegram chat
	val, exists := sm.chatToSession.Load(chatID)
	if !exists {
		return "", errors.New("No active flutter session found for this chat ID")
	}
	sessionID := val.(string)

	var existingName string
    if sessionVal, sFound := sm.sessions.Load(sessionID); sFound {
        existingName = sessionVal.(SessionData).Name
    }

	// generate jwt token
	jwt, err := GenerateJWT(userID, phone, role, jwtSecret)
	if err != nil {
		return "", err
	}

	// mark session as success
	sm.sessions.Store(sessionID, SessionData{
		Status:    "success",
		Name:      existingName,
		Role:      role,
		Phone:     phone,
		Token:     jwt,
		CreatedAt: time.Now(),
	})

	// clean up the chat mapping so it cannot be re-used
	sm.chatToSession.Delete(chatID)

	return sessionID, nil
}

// func is called by flutter every 2 seconds via GET /api/auth/status to see whether user logged successfully
func (sm *SessionManager) GetStatus(sessionID string) SessionData {
	val, exists := sm.sessions.Load(sessionID)
	if !exists {
		return SessionData{Status: "not_found"}
	}
	// return the whole SessionData strcut filled with info
	return val.(SessionData)
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