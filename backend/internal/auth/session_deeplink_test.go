package auth

import "testing"

// A session id has to survive a t.me deep link, and telegram's rules for the `start=` parameter are
// **64 characters, [A-Za-z0-9_-]**. Over the limit it does not error: it drops the parameter, opens
// the bot chat, and sends no /start - so the app polls a session that nothing will ever complete and
// eventually reports it expired, while the backend logs the user as having found the bot by hand.
//
// This is pinned as a test because the length is a *consequence* of two decisions made separately -
// how many random bytes (32, for entropy) and how they are encoded (base64url, 43 chars) - and
// raising the first or moving back to hex silently breaks login on every phone. Hex was what broke
// it: 32 bytes became 64 characters, and "sess_" made 69.
func TestSessionIDFitsATelegramDeepLink(t *testing.T) {
	sm := NewSessionManager()
	id := sm.InitSession("test", "customer")
	if len(id) > 64 {
		t.Fatalf("session id is %d chars, telegram drops the start param over 64: %q", len(id), id)
	}
	for _, r := range id {
		ok := r == '_' || r == '-' ||
			(r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
		if !ok {
			t.Fatalf("session id contains %q, outside telegram's allowed set: %q", r, id)
		}
	}
	t.Logf("session id is %d chars: %s", len(id), id)
}
