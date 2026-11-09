package endpoints

// The bot handshake end to end: the app's init, telegram's webhook calls, the app's poll. Every test
// walks the same requests production sees, with telegram's side played by posting updates.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/ratelimit"
	"domix/backend/internal/telegram"
)

const testWebhookSecret = "test-webhook-secret-0123456789abcdef"

// fakeBot records what the bot would have said instead of saying it
type fakeBot struct {
	mu      sync.Mutex
	replies []telegram.Reply
}

func (f *fakeBot) Send(_ context.Context, reply telegram.Reply) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.replies = append(f.replies, reply)
	return nil
}

func (f *fakeBot) last() telegram.Reply {
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.replies) == 0 {
		return telegram.Reply{}
	}
	return f.replies[len(f.replies)-1]
}

func telegramUnderTest(t *testing.T) (*TelegramAuth, *fakeBot, context.Context, *db.Queries) {
	t.Helper()

	_, ctx, _, q := homeUnderTest(t)
	bot := &fakeBot{}
	return &TelegramAuth{
		Queries:   q,
		Sessions:  auth.NewSessionManager(),
		Bot:       bot,
		Secret:    testWebhookSecret,
		JWTSecret: testJWTSecret,
		Updates:   ratelimit.New(1000, 1000, time.Hour),
	}, bot, ctx, q
}

func postJSON(t *testing.T, ctx context.Context, handler http.HandlerFunc, body any) map[string]any {
	t.Helper()

	encoded, _ := json.Marshal(body)
	req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/", strings.NewReader(string(encoded)))
	rec := httptest.NewRecorder()
	handler(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("answered %d: %s", rec.Code, rec.Body.String())
	}

	var answer map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &answer); err != nil {
		t.Fatalf("decode %s: %v", rec.Body, err)
	}
	return answer
}

// deliver posts one update to the webhook the way telegram does, secret header included
func deliver(t *testing.T, ctx context.Context, h *TelegramAuth, update telegram.Update) int {
	t.Helper()

	encoded, _ := json.Marshal(map[string]any{"update_id": 1, "message": messageJSON(update.Message)})
	req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/api/telegram/webhook", strings.NewReader(string(encoded)))
	req.Header.Set(telegram.SecretHeader, testWebhookSecret)
	rec := httptest.NewRecorder()
	h.Webhook(rec, req)
	return rec.Code
}

// the wire shape telegram sends, written out rather than marshalled from our own structs, so a json
// tag typo in internal/telegram fails here
func messageJSON(m *telegram.Message) map[string]any {
	out := map[string]any{
		"from": map[string]any{"id": m.From.ID, "language_code": m.From.LanguageCode},
		"chat": map[string]any{"id": m.Chat.ID, "type": "private"},
	}
	if m.Text != "" {
		out["text"] = m.Text
	}
	if m.Contact != nil {
		out["contact"] = map[string]any{"phone_number": m.Contact.PhoneNumber, "user_id": m.Contact.UserID}
	}
	return out
}

func startMessage(chatID int64, payload string) telegram.Update {
	return telegram.Update{Message: &telegram.Message{
		From: &telegram.User{ID: chatID, LanguageCode: "ru"},
		Chat: telegram.Chat{ID: chatID},
		Text: "/start " + payload,
	}}
}

func contactMessage(chatID, contactOwner int64, phone string) telegram.Update {
	return telegram.Update{Message: &telegram.Message{
		From:    &telegram.User{ID: chatID},
		Chat:    telegram.Chat{ID: chatID},
		Contact: &telegram.Contact{PhoneNumber: phone, UserID: contactOwner},
	}}
}

// signInThroughTelegram walks what the app and the user do: init, open the link, share the number,
// poll. It returns the poll's answer.
func signInThroughTelegram(t *testing.T, ctx context.Context, h *TelegramAuth, chatID int64, phone, name, role string) map[string]any {
	t.Helper()

	started := postJSON(t, ctx, h.Init, map[string]string{"name": name, "role": role, "lang": "uz"})
	session := started["session"].(string)
	if link := started["link"].(string); link != "https://t.me/domix_manager_bot?start="+session {
		t.Fatalf("the link is %q", link)
	}

	deliver(t, ctx, h, startMessage(chatID, session))
	// telegram writes the number its own way, with the plus
	deliver(t, ctx, h, contactMessage(chatID, chatID, "+"+phone))

	return postJSON(t, ctx, h.Status, map[string]string{"session": session})
}

func TestTheHandshakeCreatesAnAccountAndThenFindsIt(t *testing.T) {
	h, bot, ctx, q := telegramUnderTest(t)
	phone := unusedPhone()

	first := signInThroughTelegram(t, ctx, h, 101, phone, "Аброр", "customer")
	if first["status"] != auth.SessionSignedIn {
		t.Fatalf("the poll answered %v", first)
	}
	if bot.last().Text != botCopies["uz"].signedIn {
		t.Fatalf("the bot did not answer in the session's language: %q", bot.last().Text)
	}

	firstUser := first["user"].(map[string]any)
	claims, err := auth.ValidateJWT(first["token"].(string), testJWTSecret)
	if err != nil {
		t.Fatalf("the token does not validate: %v", err)
	}
	if int64(firstUser["id"].(float64)) != claims.UserID || firstUser["phone"] != phone || firstUser["name"] != "Аброр" {
		t.Fatalf("signed in as %v with claims %+v", firstUser, claims)
	}

	// the same number again, now registering a shop: the same row, the role upgraded
	second := signInThroughTelegram(t, ctx, h, 101, phone, "Аброр", "shop_owner")
	secondUser := second["user"].(map[string]any)
	if secondUser["id"] != firstUser["id"] {
		t.Fatalf("a second account %v for one number, the first was %v", secondUser["id"], firstUser["id"])
	}
	if secondUser["role"] != "shop_owner" {
		t.Fatalf("the role is %v, want shop_owner", secondUser["role"])
	}
	if stored, err := q.GetUserByPhone(ctx, phone); err != nil || stored.Role != "shop_owner" {
		t.Fatalf("stored %+v (%v)", stored, err)
	}
}

// an empty name, as the admin panel signs in with, renames nobody
func TestASignInWithNoNameKeepsTheAccountsName(t *testing.T) {
	h, _, ctx, q := telegramUnderTest(t)
	phone := unusedPhone()

	signInThroughTelegram(t, ctx, h, 102, phone, "Аброр", "customer")
	signInThroughTelegram(t, ctx, h, 102, phone, "", "customer")

	if stored, _ := q.GetUserByPhone(ctx, phone); stored.Name.String != "Аброр" {
		t.Fatalf("the name became %q", stored.Name.String)
	}
}

// **without this check, anybody holding your number in their contacts signs in as you**
func TestAForwardedContactIsRefused(t *testing.T) {
	h, bot, ctx, q := telegramUnderTest(t)
	victim := unusedPhone()

	started := postJSON(t, ctx, h.Init, map[string]string{"name": "Злоумышленник", "role": "customer", "lang": "ru"})
	session := started["session"].(string)
	deliver(t, ctx, h, startMessage(103, session))

	// a card from the address book: telegram user 999 owns the number, chat 103 sent it
	if code := deliver(t, ctx, h, contactMessage(103, 999, victim)); code != http.StatusOK {
		t.Fatalf("the webhook answered %d, want 200 so telegram does not redeliver", code)
	}
	// and an address-book entry that is no telegram user at all
	deliver(t, ctx, h, contactMessage(103, 0, victim))

	if got := postJSON(t, ctx, h.Status, map[string]string{"session": session}); got["status"] != auth.SessionPending || got["token"] != nil {
		t.Fatalf("a forwarded contact finished the session: %v", got)
	}
	if _, found, _ := findUser(ctx, q, victim); found {
		t.Fatal("a forwarded contact registered the number it carried")
	}
	if reply := bot.last(); reply.Text != botCopies["ru"].notYourContact || reply.ContactButton == "" {
		t.Fatalf("the bot answered %+v", reply)
	}

	// the session is still there for the user's own number
	own := unusedPhone()
	deliver(t, ctx, h, contactMessage(103, 103, own))
	if got := postJSON(t, ctx, h.Status, map[string]string{"session": session}); got["status"] != auth.SessionSignedIn {
		t.Fatalf("the user's own contact afterwards was refused: %v", got)
	}
}

// **a deletion confirmation can never be spent as a login**: its session never mints a token and is
// not readable from the login poll, and the account goes
func TestADeletionCannotBeUsedAsALogin(t *testing.T) {
	h, bot, ctx, q := telegramUnderTest(t)
	phone := unusedPhone()
	signInThroughTelegram(t, ctx, h, 104, phone, "Аброр", "shop_owner")

	started := postJSON(t, ctx, h.StartDeletion, map[string]string{"lang": "en"})
	session := started["session"].(string)
	deliver(t, ctx, h, startMessage(104, session))
	if reply := bot.last(); reply.Text != botCopies["en"].deletePrompt || reply.ContactButton != botCopies["en"].deleteButton {
		t.Fatalf("the deletion prompt was %+v", reply)
	}
	deliver(t, ctx, h, contactMessage(104, 104, phone))

	if got := postJSON(t, ctx, h.Status, map[string]string{"session": session}); got["status"] != auth.SessionExpired || got["token"] != nil {
		t.Fatalf("the login poll answered a deletion session with %v", got)
	}
	if got := postJSON(t, ctx, h.DeletionStatus, map[string]string{"session": session}); got["status"] != auth.SessionDeleted {
		t.Fatalf("the deletion poll answered %v", got)
	}
	if _, found, _ := findUser(ctx, q, phone); found {
		t.Fatal("the account survived its deletion")
	}

	// and the reverse: a login session read from the deletion poll says nothing
	login := postJSON(t, ctx, h.Init, map[string]string{"role": "customer"})["session"].(string)
	if got := postJSON(t, ctx, h.DeletionStatus, map[string]string{"session": login}); got["status"] != auth.SessionExpired {
		t.Fatalf("the deletion poll answered a login session with %v", got)
	}
}

// said only after the number is proven, so it tells nobody anything they could not find out
func TestDeletingANumberWithNoAccountSaysSo(t *testing.T) {
	h, _, ctx, _ := telegramUnderTest(t)

	session := postJSON(t, ctx, h.StartDeletion, map[string]string{"lang": "ru"})["session"].(string)
	deliver(t, ctx, h, startMessage(105, session))
	deliver(t, ctx, h, contactMessage(105, 105, unusedPhone()))

	if got := postJSON(t, ctx, h.DeletionStatus, map[string]string{"session": session}); got["status"] != auth.SessionNoAccount {
		t.Fatalf("answered %v", got)
	}
}

func TestAContactWithNoSessionCreatesNothing(t *testing.T) {
	h, bot, ctx, q := telegramUnderTest(t)
	phone := unusedPhone()

	deliver(t, ctx, h, startMessage(106, "made-up-session-id"))
	deliver(t, ctx, h, contactMessage(106, 106, phone))

	if _, found, _ := findUser(ctx, q, phone); found {
		t.Fatal("a contact with no session behind it registered an account")
	}
	if bot.last().Text != botCopies["ru"].expired {
		t.Fatalf("the bot answered %q", bot.last().Text)
	}
}

func TestAForeignNumberIsRefused(t *testing.T) {
	h, _, ctx, _ := telegramUnderTest(t)

	session := postJSON(t, ctx, h.Init, map[string]string{"role": "customer"})["session"].(string)
	deliver(t, ctx, h, startMessage(107, session))
	deliver(t, ctx, h, contactMessage(107, 107, "+79161234567"))

	if got := postJSON(t, ctx, h.Status, map[string]string{"session": session}); got["status"] != auth.SessionNotUzbek {
		t.Fatalf("answered %v", got)
	}
}

// the url is public: an update without telegram's secret must change nothing
func TestTheWebhookRefusesACallWithoutTheSecret(t *testing.T) {
	h, bot, ctx, q := telegramUnderTest(t)
	phone := unusedPhone()

	session := postJSON(t, ctx, h.Init, map[string]string{"role": "customer"})["session"].(string)
	deliver(t, ctx, h, startMessage(108, session))

	for _, secret := range []string{"", "wrong-secret-0123456789abcdef0123456789"} {
		encoded, _ := json.Marshal(map[string]any{"update_id": 2, "message": messageJSON(contactMessage(108, 108, phone).Message)})
		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/api/telegram/webhook", strings.NewReader(string(encoded)))
		if secret != "" {
			req.Header.Set(telegram.SecretHeader, secret)
		}
		rec := httptest.NewRecorder()
		h.Webhook(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("secret %q answered %d, want 401", secret, rec.Code)
		}
	}

	if _, found, _ := findUser(ctx, q, phone); found {
		t.Fatal("a forged update registered an account")
	}
	if got := postJSON(t, ctx, h.Status, map[string]string{"session": session}); got["status"] != auth.SessionPending {
		t.Fatalf("a forged update moved the session: %v", got)
	}
	if len(bot.replies) != 1 {
		t.Fatalf("the bot spoke %d times, want only the prompt", len(bot.replies))
	}
}
