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
// Both kinds of session travel this way - login from the app, deletion from the web page - so both
// prefixes are checked here rather than only the one that has broken before.
func TestSessionIDFitsATelegramDeepLink(t *testing.T) {
	sm := NewSessionManager()

	for _, id := range []string{sm.InitSession("test", "customer"), sm.InitDeletion("998901234567")} {
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
}

// The number typed into a browser and the number telegram reports for a shared contact are
// formatted by different software, and the deletion flow's second question - "is this the same
// number?" - is a string compare between the two. This pins the pair that makes that compare work:
// InitDeletion has to store the normalized form, because the handler normalizes only the telegram
// side before comparing.
//
// If they ever drift apart the flow does not break loudly: every honest attempt is refused as a
// mismatch, and nobody can delete their account from the web page at all.
func TestATypedNumberMatchesTheOneTelegramReports(t *testing.T) {
	sm := NewSessionManager()

	const chatID = int64(4242)
	if !sm.LinkChat(chatID, sm.InitDeletion("+998 90 123 45 67")) {
		t.Fatal("could not link a chat to a fresh deletion session")
	}

	_, session, ok := sm.PendingSession(chatID)
	if !ok {
		t.Fatal("the linked deletion session is not readable from its chat")
	}

	for _, reported := range []string{"998901234567", "+998901234567"} {
		if NormalizePhone(reported) != session.Phone {
			t.Fatalf("telegram reporting %q does not match the typed number stored as %q", reported, session.Phone)
		}
	}
	if NormalizePhone("+998901234568") == session.Phone {
		t.Fatal("a different number matched the one typed on the page")
	}
}
