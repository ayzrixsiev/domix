package endpoints

// the /delete-account page's two endpoints. neither touches the database - the whole flow lives in
// the session manager and finishes inside the telegram handler - so unlike the rest of this package
// these run without a local postgres.

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"domix/backend/internal/auth"
)

func deletionUnderTest() (*AccountDeletion, *auth.SessionManager) {
	sm := auth.NewSessionManager()
	return &AccountDeletion{SessionMgr: sm, BotUsername: "domixbot"}, sm
}

func statusOf(t *testing.T, d *AccountDeletion, sessionID string) string {
	t.Helper()

	req := httptest.NewRequest(http.MethodGet, "/api/account-deletion/status?session_id="+sessionID, nil)
	rec := httptest.NewRecorder()
	d.Status(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status endpoint answered %d, want 200", rec.Code)
	}

	var body struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decoding the status response: %v", err)
	}
	return body.Status
}

// A completed *login* session also reports `status: "success"` - and this page renders that word as
// "your account has been deleted". Without the purpose check in Status, anyone who finished logging
// in and pasted their own session id here would be told their account was gone while it sat
// perfectly intact, which is the worst possible thing for this page to be wrong about.
func TestALoginSessionIsInvisibleToTheDeletionPage(t *testing.T) {
	d, sm := deletionUnderTest()

	if got := statusOf(t, d, sm.InitSession("Тест", "customer")); got != "not_found" {
		t.Fatalf("a login session reads as %q through the deletion page, want not_found", got)
	}
	if got := statusOf(t, d, sm.InitDeletion("998901234567")); got != "pending" {
		t.Fatalf("a fresh deletion session reads as %q, want pending", got)
	}
	if got := statusOf(t, d, "del_nothing"); got != "not_found" {
		t.Fatalf("an unknown id reads as %q, want not_found", got)
	}
}

// The number is never looked up, so the only thing standing between a typo and a session sitting in
// memory for ten minutes is this length check.
func TestInitRefusesSomethingThatIsNotAPhoneNumber(t *testing.T) {
	d, _ := deletionUnderTest()

	for _, phone := range []string{"", "12345", "9989012345678901234"} {
		req := httptest.NewRequest(http.MethodPost, "/api/account-deletion/init",
			strings.NewReader(`{"phone":"`+phone+`"}`))
		rec := httptest.NewRecorder()
		d.Init(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("phone %q answered %d, want 400", phone, rec.Code)
		}
	}
}

// A deep link is what carries this id to telegram, exactly as it carries a login id, so it is under
// the same 64-character limit - see TestSessionIDFitsATelegramDeepLink for what breaks past it.
func TestInitHandsBackADeepLinkTelegramWillAccept(t *testing.T) {
	d, _ := deletionUnderTest()

	req := httptest.NewRequest(http.MethodPost, "/api/account-deletion/init", strings.NewReader(`{"phone":"+998 90 123 45 67"}`))
	rec := httptest.NewRecorder()
	d.Init(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("init answered %d, want 200: %s", rec.Code, rec.Body.String())
	}

	var body struct {
		SessionID   string `json:"session_id"`
		TelegramURL string `json:"telegram_url"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decoding the init response: %v", err)
	}
	if len(body.SessionID) > 64 {
		t.Fatalf("session id is %d chars, telegram drops the start param over 64: %q", len(body.SessionID), body.SessionID)
	}
	if want := "https://t.me/domixbot?start=" + body.SessionID; body.TelegramURL != want {
		t.Fatalf("deep link is %q, want %q", body.TelegramURL, want)
	}
}
