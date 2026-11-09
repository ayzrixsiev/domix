package auth

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"log"
	"runtime/debug"
	"sync"
	"sync/atomic"
	"time"
)

// the telegram bot handshake: a caller starts a session, opens the bot on a t.me link carrying its id,
// shares their contact there, and polls the session until it holds the outcome.
//
// **sessions live in ram, never in postgres**, like pending codes: an abandoned signup leaves no row,
// and a restart dropping someone mid-login is accepted. two sync.Maps - session id -> data, telegram
// chat -> session id - because every step is one key's read or one key's swap: the steps that must
// happen once (claiming a session, collecting its token) are LoadAndDelete and CompareAndSwap.

// HandshakePurpose is what a session ends in. **a deletion session can never mint a token**: the
// webhook branches on it and Collect refuses an id asked for under the other purpose.
type HandshakePurpose string

const (
	HandshakeLogin    HandshakePurpose = "login"
	HandshakeDeletion HandshakePurpose = "deletion"
)

// the statuses a poll can answer with. the app and both web pages draw one sentence per value.
const (
	SessionPending    = "pending"
	SessionSignedIn   = "success"    // login: Token and the account fields are set
	SessionDeleted    = "deleted"    // deletion: the account and everything under it is gone
	SessionNoAccount  = "no_account" // deletion: the number is proven, nobody is registered on it
	SessionNotUzbek   = "not_uzbek"  // the shared number is not 998..., which no account can hold
	SessionFailed     = "failed"     // the database refused; nothing changed
	SessionExpired    = "expired"    // no such session: timed out, collected, or never existed
	sessionInProgress = "working"    // claimed by a contact, outcome not written yet; polls see pending
)

const (
	SessionTTL = 10 * time.Minute

	// how long a finished session waits to be collected. counted from the finish, not the start, so a
	// login completed in its tenth minute is still there for the next poll.
	sessionCollectWindow = 2 * time.Minute

	// **the ceiling on what an unauthenticated flood can hold in ram**, at a few hundred bytes each.
	// reaching it refuses new sign-ins until the sweeper frees some: accepted, like dailySendBudget.
	maxLiveSessions = 20_000

	sessionSweepInterval = time.Minute
)

var ErrTooManySessions = errors.New("auth: too many sign-ins in progress")

// SessionData is one handshake. Name, Role and Lang come from the caller; the outcome fields are
// written once by Finish.
type SessionData struct {
	Purpose HandshakePurpose
	Status  string

	Name string // empty means "keep the account's own name"
	Role string
	Lang string // ru, uz or en: the language the bot answers this session in

	Token  string
	UserID int64
	Phone  string

	expiresAt time.Time
}

type SessionManager struct {
	sessions      sync.Map // session id -> SessionData
	chatToSession sync.Map // telegram chat id -> session id
	live          atomic.Int64

	now func() time.Time // time.Now, swapped only by this package's tests
}

func NewSessionManager() *SessionManager {
	m := &SessionManager{now: time.Now}
	go m.sweep()
	return m
}

// Start opens a session and returns its id. **The id is the only secret in the handshake**: whoever
// holds it can poll the token, so it is 32 random bytes. base64url without padding because it rides
// in t.me's `start=` parameter, which allows 64 characters of [A-Za-z0-9_-] and silently drops
// anything longer - hex would be exactly 64 and any prefix pushes it over.
func (m *SessionManager) Start(purpose HandshakePurpose, name, role, lang string) (string, error) {
	if m.live.Add(1) > maxLiveSessions {
		m.live.Add(-1)
		return "", ErrTooManySessions
	}

	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		m.live.Add(-1)
		return "", err
	}
	id := base64.RawURLEncoding.EncodeToString(raw)

	m.sessions.Store(id, SessionData{
		Purpose:   purpose,
		Status:    SessionPending,
		Name:      name,
		Role:      role,
		Lang:      lang,
		expiresAt: m.now().Add(SessionTTL),
	})
	return id, nil
}

// Link ties the chat that pressed /start to the session its link carried. A chat links to one
// session at a time, the latest: pressing the app's button twice leaves the second one in charge.
func (m *SessionManager) Link(chatID int64, id string) (SessionData, bool) {
	data, ok := m.pending(id)
	if !ok {
		return SessionData{}, false
	}
	m.chatToSession.Store(chatID, id)
	return data, true
}

// Linked is the live session this chat is in, for re-prompting a user who typed instead of tapping.
func (m *SessionManager) Linked(chatID int64) (SessionData, bool) {
	id, ok := m.chatToSession.Load(chatID)
	if !ok {
		return SessionData{}, false
	}
	return m.pending(id.(string))
}

// Claim takes the session this chat is in, for the contact that just arrived. **Exactly one contact
// wins**: the chat link is taken out with LoadAndDelete, and the session itself moves out of pending
// with CompareAndSwap, so two contacts - from one chat or from two chats that both opened the link -
// cannot both sign in or both delete.
func (m *SessionManager) Claim(chatID int64) (string, SessionData, bool) {
	value, ok := m.chatToSession.LoadAndDelete(chatID)
	if !ok {
		return "", SessionData{}, false
	}
	id := value.(string)

	data, ok := m.pending(id)
	if !ok {
		return "", SessionData{}, false
	}
	claimed := data
	claimed.Status = sessionInProgress
	if !m.sessions.CompareAndSwap(id, data, claimed) {
		return "", SessionData{}, false
	}
	return id, data, true
}

// Finish writes a claimed session's outcome. Purpose and Lang are kept from the session, whatever
// the caller passes.
func (m *SessionManager) Finish(id string, outcome SessionData) {
	value, ok := m.sessions.Load(id)
	if !ok {
		return
	}
	stored := value.(SessionData)
	outcome.Purpose = stored.Purpose
	outcome.Lang = stored.Lang
	outcome.expiresAt = m.now().Add(sessionCollectWindow)
	m.sessions.Store(id, outcome)
}

// Collect is the poll. A finished session is handed out **once** and deleted, so a token is never
// read twice; an id asked for under the wrong purpose is answered exactly like an unknown one.
func (m *SessionManager) Collect(purpose HandshakePurpose, id string) SessionData {
	value, ok := m.sessions.Load(id)
	if !ok {
		return SessionData{Status: SessionExpired}
	}
	data := value.(SessionData)
	if data.Purpose != purpose || m.now().After(data.expiresAt) {
		return SessionData{Status: SessionExpired}
	}

	switch data.Status {
	case SessionPending, sessionInProgress:
		return SessionData{Purpose: data.Purpose, Status: SessionPending}
	}

	// of two polls racing for one outcome, the one that deletes it is the one that gets it
	if _, loaded := m.sessions.LoadAndDelete(id); !loaded {
		return SessionData{Status: SessionExpired}
	}
	m.live.Add(-1)
	return data
}

// pending is a session that a contact may still complete
func (m *SessionManager) pending(id string) (SessionData, bool) {
	value, ok := m.sessions.Load(id)
	if !ok {
		return SessionData{}, false
	}
	data := value.(SessionData)
	if data.Status != SessionPending || m.now().After(data.expiresAt) {
		return SessionData{}, false
	}
	return data, true
}

func (m *SessionManager) sweep() {
	ticker := time.NewTicker(sessionSweepInterval)
	defer ticker.Stop()
	for range ticker.C {
		m.sweepOnce()
	}
}

func (m *SessionManager) sweepOnce() {
	// an unrecovered panic in a goroutine takes the whole process with it, api included
	defer func() {
		if problem := recover(); problem != nil {
			log.Printf("CRITICAL: panic sweeping sign-in sessions: %v\n%s", problem, debug.Stack())
		}
	}()

	now := m.now()
	m.sessions.Range(func(key, value any) bool {
		if now.After(value.(SessionData).expiresAt) {
			if _, loaded := m.sessions.LoadAndDelete(key); loaded {
				m.live.Add(-1)
			}
		}
		return true
	})

	// a chat that never shared its contact still points at the session just swept
	m.chatToSession.Range(func(chat, id any) bool {
		if _, ok := m.sessions.Load(id); !ok {
			m.chatToSession.Delete(chat)
		}
		return true
	})
}
