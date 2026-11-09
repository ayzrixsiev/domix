package auth

import (
	"testing"
	"time"
)

// The handshake's rules that hold without a database: when a session can still be completed, that it
// is completed once, and that a deletion session can never be collected as a login.

const testChat int64 = 4242

// a manager whose clock the test moves, and whose sweeper is the test's to run
func sessionsAt(start time.Time) (*SessionManager, *time.Time) {
	clock := start
	m := &SessionManager{now: func() time.Time { return clock }}
	return m, &clock
}

func TestAnExpiredSessionCannotBeCompleted(t *testing.T) {
	m, clock := sessionsAt(time.Now())
	id, err := m.Start(HandshakeLogin, "Аброр", "customer", "ru")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := m.Link(testChat, id); !ok {
		t.Fatal("a fresh session refused its own /start")
	}

	*clock = clock.Add(SessionTTL + time.Second)

	if _, _, ok := m.Claim(testChat); ok {
		t.Fatal("a contact completed a session past its ttl")
	}
	if _, ok := m.Link(testChat+1, id); ok {
		t.Fatal("an expired session accepted a /start")
	}
	if got := m.Collect(HandshakeLogin, id).Status; got != SessionExpired {
		t.Fatalf("the poll says %q, want %q", got, SessionExpired)
	}
}

// the session the contact came for is the one that finishes, and only once: two contacts racing,
// from one chat or from two that opened the same link, must not both sign in or both delete
func TestASessionIsClaimedOnce(t *testing.T) {
	m, _ := sessionsAt(time.Now())
	id, _ := m.Start(HandshakeLogin, "", "customer", "ru")
	m.Link(testChat, id)
	m.Link(testChat+1, id)

	if _, _, ok := m.Claim(testChat); !ok {
		t.Fatal("the first contact was refused")
	}
	if _, _, ok := m.Claim(testChat); ok {
		t.Fatal("the same chat claimed the session twice")
	}
	if _, _, ok := m.Claim(testChat + 1); ok {
		t.Fatal("a second chat claimed a session already being completed")
	}
	if got := m.Collect(HandshakeLogin, id).Status; got != SessionPending {
		t.Fatalf("a claimed, unfinished session polls as %q, want pending", got)
	}
}

// a token is handed out once: the second poll finds nothing, so a copied id is worth nothing late
func TestAFinishedSessionIsCollectedOnce(t *testing.T) {
	m, clock := sessionsAt(time.Now())
	id, _ := m.Start(HandshakeLogin, "", "customer", "ru")
	m.Link(testChat, id)
	m.Claim(testChat)

	// finished in its last second, collected a minute later: the window counts from the finish
	*clock = clock.Add(SessionTTL - time.Second)
	m.Finish(id, SessionData{Status: SessionSignedIn, Token: "t", UserID: 7})
	*clock = clock.Add(time.Minute)

	first := m.Collect(HandshakeLogin, id)
	if first.Status != SessionSignedIn || first.Token != "t" {
		t.Fatalf("the first poll got %+v", first)
	}
	if again := m.Collect(HandshakeLogin, id); again.Status != SessionExpired || again.Token != "" {
		t.Fatalf("the token was handed out twice: %+v", again)
	}
	if m.live.Load() != 0 {
		t.Fatalf("%d sessions still counted live", m.live.Load())
	}
}

// **a deletion confirmation can never be spent as a login**, whichever way round the ids are asked for
func TestAPurposeIsNotCollectedAsTheOther(t *testing.T) {
	m, _ := sessionsAt(time.Now())
	deletion, _ := m.Start(HandshakeDeletion, "", "", "ru")
	login, _ := m.Start(HandshakeLogin, "", "customer", "ru")

	m.Finish(deletion, SessionData{Status: SessionDeleted})
	m.Finish(login, SessionData{Status: SessionSignedIn, Token: "t"})

	if got := m.Collect(HandshakeLogin, deletion); got.Status != SessionExpired || got.Token != "" {
		t.Fatalf("a deletion session polled as a login: %+v", got)
	}
	if got := m.Collect(HandshakeDeletion, login); got.Status != SessionExpired {
		t.Fatalf("a login session polled as a deletion: %+v", got)
	}

	// and neither wrong-purpose ask spent the real outcome
	if got := m.Collect(HandshakeDeletion, deletion).Status; got != SessionDeleted {
		t.Fatalf("the deletion's own poll got %q", got)
	}
	if got := m.Collect(HandshakeLogin, login).Token; got != "t" {
		t.Fatal("the login's own poll lost its token")
	}
}

func TestTheSweeperForgetsExpiredSessionsAndTheirChats(t *testing.T) {
	m, clock := sessionsAt(time.Now())
	id, _ := m.Start(HandshakeLogin, "", "customer", "ru")
	m.Link(testChat, id)

	*clock = clock.Add(SessionTTL + time.Second)
	m.sweepOnce()

	if _, ok := m.sessions.Load(id); ok {
		t.Fatal("an expired session survived the sweep")
	}
	if _, ok := m.chatToSession.Load(testChat); ok {
		t.Fatal("the chat still points at a swept session")
	}
	if m.live.Load() != 0 {
		t.Fatalf("%d sessions still counted live", m.live.Load())
	}
}

func TestStartRefusesPastTheCeiling(t *testing.T) {
	m, _ := sessionsAt(time.Now())
	m.live.Store(maxLiveSessions)

	if _, err := m.Start(HandshakeLogin, "", "customer", "ru"); err != ErrTooManySessions {
		t.Fatalf("got %v, want ErrTooManySessions", err)
	}
	if m.live.Load() != maxLiveSessions {
		t.Fatal("a refused start was counted")
	}
}

// t.me drops a start parameter longer than 64 characters or outside [A-Za-z0-9_-], silently
func TestASessionIDFitsATelegramStartParameter(t *testing.T) {
	m, _ := sessionsAt(time.Now())
	id, _ := m.Start(HandshakeLogin, "", "customer", "ru")
	if len(id) > 64 {
		t.Fatalf("id is %d characters", len(id))
	}
	for _, r := range id {
		ok := r == '_' || r == '-' || (r >= '0' && r <= '9') || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')
		if !ok {
			t.Fatalf("id %q carries %q", id, r)
		}
	}
}
