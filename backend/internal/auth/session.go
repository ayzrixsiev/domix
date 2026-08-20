package auth

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"strings"
	"sync"
	"time"
)

// what a session is for.
//
// two flows use the identical handshake - mint a random id, hand back a t.me deep link, wait for a
// contact to be shared in that chat - and end in opposite places: one issues a jwt, the other
// destroys the account. they share one manager, one sweeper and one id generator because the only
// thing that actually differs is the last step, and this field is what the telegram handler
// branches on when the contact finally arrives.
const (
	PurposeLogin    = "login"
	PurposeDeletion = "deletion"
)

// the states a deletion session can finish in. the /delete-account page renders one sentence per
// value, so a status added here needs a sentence added there or the page goes blank on it.
const (
	DeletionDone      = "success"    // the account and everything under it is gone
	DeletionNoAccount = "no_account" // the number is proven, but no account is registered to it
	DeletionMismatch  = "mismatch"   // the contact shared is not the number typed on the page
	DeletionFailed    = "error"      // the database refused; nothing was deleted
)

// holds the real-time login data and it's state
type SessionData struct {
	Status    string    `json:"status"` // "pending", "success", or "not_found"
	Purpose   string    `json:"-"`      // PurposeLogin or PurposeDeletion - internal, never sent out
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
	sessionID := newSessionID("sess_")

	// save their custom name, role in ram and set login status to pending
	sm.sessions.Store(sessionID, SessionData{
		Status:    "pending",
		Purpose:   PurposeLogin,
		Name:      name,
		Role:      role,
		CreatedAt: time.Now(),
	})

	return sessionID
}

// newSessionID mints one id with the given prefix. everything about the shape of it - 32 random
// bytes, spelled in base64url - is explained on InitSession above, and both flows share this
// function so a second prefix cannot accidentally be given a weaker or longer id.
func newSessionID(prefix string) string {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		panic("auth: no source of randomness for session ids: " + err.Error())
	}
	return prefix + base64.RawURLEncoding.EncodeToString(bytes)
}

// InitDeletion starts an account-deletion session for the number typed on the /delete-account page.
//
// **the number typed there proves nothing and is not treated as proof.** it is stored only so the
// contact eventually shared in telegram can be checked against it: whoever presses the button in
// the bot is deleting their own account and no other, whatever they typed on the page.
//
// nothing is looked up in the database here either, deliberately. answering "there is no such
// account" at this point would turn the page into a way to ask whether any phone number in the
// country is registered with Domix, from a browser, without proving anything at all. the answer to
// that question is given inside telegram, after ownership of the number has been demonstrated.
func (sm *SessionManager) InitDeletion(phone string) string {
	sessionID := newSessionID("del_")

	sm.sessions.Store(sessionID, SessionData{
		Status:    "pending",
		Purpose:   PurposeDeletion,
		Phone:     NormalizePhone(phone),
		CreatedAt: time.Now(),
	})

	return sessionID
}

// NormalizePhone reduces a phone number to its digits, so "+998 90 123 45 67" and "998901234567"
// compare equal.
//
// it exists for exactly one comparison - the number typed into a browser against the number
// telegram reports for a shared contact - and those two are formatted by different software, so a
// literal string compare would refuse most honest attempts.
//
// **it is deliberately not used to look an account up.** users.phone holds whatever telegram sent
// at registration, so the lookup has to use that same raw value, exactly as the login flow does.
func NormalizePhone(phone string) string {
	var digits strings.Builder
	for _, r := range phone {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
	}
	return digits.String()
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

// PendingSession returns the session linked to this telegram chat, whatever that session is for -
// called when a contact arrives, and again when /start arrives, to find out which flow is running.
//
// it hands back the whole struct rather than a few named fields because the two flows read
// different ones: login wants the name and the role, deletion wants the phone. an accessor per
// purpose would be a second place to forget the "does it still exist" check.
func (sm *SessionManager) PendingSession(chatID int64) (sessionID string, data SessionData, exists bool) {
	val, found := sm.chatToSession.Load(chatID)
	if !found {
		return "", SessionData{}, false
	}
	sID := val.(string)

	sessionVal, sFound := sm.sessions.Load(sID)
	if !sFound {
		return sID, SessionData{}, false
	}

	return sID, sessionVal.(SessionData), true
}

// FinishDeletion writes the outcome of a deletion attempt onto the session the web page is polling,
// and unlinks the chat so the same shared contact cannot drive a second one.
//
// CreatedAt is carried over rather than refreshed: the sweeper evicts on age, and the page has read
// this answer within a couple of seconds of it being written.
func (sm *SessionManager) FinishDeletion(chatID int64, status string) (string, bool) {
	sessionID, data, exists := sm.PendingSession(chatID)
	if !exists {
		return sessionID, false
	}

	data.Status = status
	sm.sessions.Store(sessionID, data)
	sm.chatToSession.Delete(chatID)

	return sessionID, true
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
		Purpose:   PurposeLogin,
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
