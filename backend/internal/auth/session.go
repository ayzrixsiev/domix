package auth

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"sync"
	"time"
)

// holds the real-time login data and it's state
type SessionData struct {
	Status    string    `json:"status"` // "pending", "success", or "not_found"
	Name      string    `json:"name,omitempty"`
	Role      string    `json:"role,omitempty"`
	Phone     string    `json:"phone,omitempty"`
	Token     string    `json:"token,omitempty"`
	CreatedAt time.Time `json:"-"` // we use - to hide this internal timestamp from json response
}

// blueprint of data manager during active session
type SessionManager struct {
	sessions      sync.Map // maps SessionID -> SessionData
	chatToSession sync.Map // maps telegram ChatID -> SessionID
}

// initialize our active session blueprint and hand over its address to use its methods
func NewSessionManager() *SessionManager {
	sm := &SessionManager{}

	// shield: run a background thread (goroutine) that wakes up every 1 minute and clears out any sessions older than 10 minutes.
	go sm.startCleanupSweeper(1*time.Minute, 10*time.Minute)

	return sm
}

// func called when flutter hits POST /api/auth/init and sends us json with collected data - name and role
func (sm *SessionManager) InitSession(name string, role string) string {
	// 32 bytes, not 4.
	//
	// this id is the only thing standing between a stranger and somebody else's JWT: whoever knows a
	// pending session's id can poll GET /api/auth/status and collect the token the moment the real
	// user finishes in Telegram. at 4 bytes the whole space is 2^32, small enough to be worth
	// sweeping; at 32 it is 2^256 and guessing stops being a strategy.
	//
	// **base64url, not hex, and the encoding is load-bearing.** this id travels as the `start=`
	// parameter of a t.me deep link, and telegram caps that parameter at **64 characters** and allows
	// only [A-Za-z0-9_-]. hex doubles 32 bytes into 64 characters, and "sess_" made 69 - over the
	// limit, so telegram silently dropped the parameter, opened the bot chat and sent no /start at
	// all. every symptom pointed elsewhere: the link opened, the bot appeared, and the backend logged
	// "pressed /start directly without a Flutter link" as though the user had found the bot by hand,
	// while the app polled a session nothing would ever complete and finally reported it expired.
	//
	// base64url encodes the same 32 bytes in 43 characters, giving 48 with the prefix, and its
	// alphabet is exactly the set telegram permits. the entropy is unchanged - this is a shorter
	// spelling of the same 256 bits, not a weaker id. RawURLEncoding because the padded form ends in
	// '=' , which is not in telegram's allowed set.
	//
	// rand.Read's error is checked rather than dropped. crypto/rand does not return one on any
	// platform we run on, but the failure mode if it ever did is a session id of all zeros handed to
	// every caller, which is the single worst outcome this file can produce - so it panics instead,
	// loudly, at the point of failure.
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		panic("auth: no source of randomness for session ids: " + err.Error())
	}
	sessionID := "sess_" + base64.RawURLEncoding.EncodeToString(bytes)

	// save their custom name, role in ram and set login status to pending
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
	// safety check to see whether session id was dropped inside telegram link to avoid ghost account creation
	if sessionID == "" {
		return false
	}

	// make sure the session actually exists in RAM first
	if _, exists := sm.sessions.Load(sessionID); !exists {
		return false
	}
	sm.chatToSession.Store(chatID, sessionID)
	return true
}

// when /phone button pressed we retrieve role, name and sessionID
func (sm *SessionManager) GetPendingSession(chatID int64) (sessionID string, name string, role string, exists bool) {

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

	// generate jwt token - role is not part of the token itself, see internal/auth/jwt.go
	jwt, err := GenerateJWT(userID, phone, jwtSecret)
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

// goroutine for the old session cleaning
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

		// a chat link is only useful as long as the session it points to still exists.
		// CompleteSession already deletes its own chat link on success (see above), so the only
		// way a link ends up here is a chat that never finished the flow (phone number was not send)
		// its session just got deleted by the sweep above, orphaning this entry. cleaning it up too.
		sm.chatToSession.Range(func(key, value interface{}) bool {
			chatID := key.(int64)
			sessionID := value.(string)

			if _, exists := sm.sessions.Load(sessionID); !exists {
				sm.chatToSession.Delete(chatID)
			}
			return true
		})
	}
}
