package endpoints

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"runtime/debug"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
	"domix/backend/internal/ratelimit"
	"domix/backend/internal/telegram"
)

// every sign-in and the /delete-account page: one button, the bot, a shared contact.
//
//	POST /api/auth/init               {name, role, lang} -> {session, link, expires_in}
//	POST /api/auth/status             {session}          -> {status[, token, user]}
//	POST /api/account-deletion/start  {lang}             -> {session, link, expires_in}
//	POST /api/account-deletion/status {session}          -> {status}
//	POST /api/telegram/webhook        an update from telegram
//
// the status reads are POSTs so the session id, which is what the token is collected with, never
// lands in an access log the way a query string does.
type TelegramAuth struct {
	Queries   *db.Queries
	Sessions  *auth.SessionManager
	Bot       Messenger
	Secret    string
	JWTSecret string

	// deleting an account deletes its owner's photos - see eraseAccount
	Images *imagestore.Disk

	// **spent after the secret is checked, on one key**: telegram is the only honest caller, and a
	// bucket in front of the check would let anybody without the secret starve it
	Updates *ratelimit.Limiter
}

// the bot's one outbound call, an interface so the tests read what it would have said
type Messenger interface {
	Send(ctx context.Context, reply telegram.Reply) error
}

// what telegram's longest honest update is plus room; a contact message is a few hundred bytes
const maxUpdateBody = 64 << 10

const botReplyTimeout = 10 * time.Second

// POST /api/auth/init
func (t *TelegramAuth) Init(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Name string `json:"name"`
		Role string `json:"role"`
		Lang string `json:"lang"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	// empty is allowed and renames nothing: the admin panel signs in with no name to give
	name := strings.TrimSpace(req.Name)
	if utf8.RuneCountInString(name) > maxUserNameLen {
		writeAPIError(w, http.StatusBadRequest, "name_too_long", "name is longer than the maximum allowed length")
		return
	}
	role := req.Role
	if role != "shop_owner" {
		role = "customer"
	}

	t.start(w, auth.HandshakeLogin, name, role, req.Lang)
}

// POST /api/account-deletion/start - nothing is typed on the page: the contact shared in telegram is
// the number, and the account on it is the one that goes.
func (t *TelegramAuth) StartDeletion(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Lang string `json:"lang"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	t.start(w, auth.HandshakeDeletion, "", "", req.Lang)
}

func (t *TelegramAuth) start(w http.ResponseWriter, purpose auth.HandshakePurpose, name, role, lang string) {
	id, err := t.Sessions.Start(purpose, name, role, botLanguage(lang))
	if err != nil {
		if errors.Is(err, auth.ErrTooManySessions) {
			log.Printf("WARNING: refused a sign-in, %v", err)
			writeAPIError(w, http.StatusServiceUnavailable, "busy", "too many sign-ins in progress, try again shortly")
			return
		}
		log.Printf("CRITICAL: could not start a telegram session: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not start")
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"session":    id,
		"link":       telegram.DeepLink(id),
		"expires_in": int(auth.SessionTTL.Seconds()),
	})
}

// POST /api/auth/status - polled every two seconds by everybody signing in, so it reads ram only
func (t *TelegramAuth) Status(w http.ResponseWriter, r *http.Request) {
	session, ok := t.readSession(w, r)
	if !ok {
		return
	}

	data := t.Sessions.Collect(auth.HandshakeLogin, session)
	answer := map[string]any{"status": data.Status}
	if data.Status == auth.SessionSignedIn {
		answer["token"] = data.Token
		answer["user"] = MeResponse{ID: data.UserID, Name: data.Name, Phone: data.Phone, Role: data.Role}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(answer)
}

// POST /api/account-deletion/status
func (t *TelegramAuth) DeletionStatus(w http.ResponseWriter, r *http.Request) {
	session, ok := t.readSession(w, r)
	if !ok {
		return
	}

	data := t.Sessions.Collect(auth.HandshakeDeletion, session)
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": data.Status})
}

func (t *TelegramAuth) readSession(w http.ResponseWriter, r *http.Request) (string, bool) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return "", false
	}
	var req struct {
		Session string `json:"session"`
	}
	if !decodeJSONBody(w, r, &req) {
		return "", false
	}
	if req.Session == "" {
		writeAPIError(w, http.StatusBadRequest, "missing_session", "session is required")
		return "", false
	}
	return req.Session, true
}

// POST /api/telegram/webhook
//
// **every update telegram can parse is answered 200, handled or not**: anything else and telegram
// redelivers it, over and over, ahead of every update behind it.
func (t *TelegramAuth) Webhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if !telegram.SecretMatches(r, t.Secret) {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not telegram")
		return
	}
	// a 429 is what telegram backs off on, and it redelivers the update later
	if !t.Updates.Allow("telegram") {
		ratelimit.Refuse(w, t.Updates.RetryAfter())
		return
	}

	var update telegram.Update
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxUpdateBody)).Decode(&update); err != nil {
		log.Printf("WARNING: dropped a telegram update that does not decode: %v", err)
		w.WriteHeader(http.StatusOK)
		return
	}

	// detached: telegram hanging up must not abandon a sign-in halfway through its writes
	t.handleUpdate(context.WithoutCancel(r.Context()), update)
	w.WriteHeader(http.StatusOK)
}

func (t *TelegramAuth) handleUpdate(ctx context.Context, update telegram.Update) {
	// one malformed update is logged and dropped, never a 500 telegram would redeliver forever
	defer func() {
		if problem := recover(); problem != nil {
			log.Printf("CRITICAL: panic handling telegram update %d: %v\n%s", update.UpdateID, problem, debug.Stack())
		}
	}()

	msg := update.Message
	if msg == nil || msg.From == nil || msg.Chat.Type != "private" {
		return
	}

	switch {
	case msg.Contact != nil:
		t.handleContact(ctx, msg)
	case msg.Text == "/start" || strings.HasPrefix(msg.Text, "/start "):
		t.handleStart(ctx, msg)
	default:
		// typed instead of tapped: show the button again if there is something to press it for
		if session, ok := t.Sessions.Linked(msg.Chat.ID); ok {
			t.prompt(ctx, msg.Chat.ID, session)
			return
		}
		t.reply(ctx, msg.Chat.ID, botCopyFor(msg.From.LanguageCode).startFromApp, "")
	}
}

func (t *TelegramAuth) handleStart(ctx context.Context, msg *telegram.Message) {
	payload := strings.TrimSpace(strings.TrimPrefix(msg.Text, "/start"))
	if payload == "" {
		// found the bot by hand: there is no session for it to finish
		t.reply(ctx, msg.Chat.ID, botCopyFor(msg.From.LanguageCode).startFromApp, "")
		return
	}

	session, ok := t.Sessions.Link(msg.Chat.ID, payload)
	if !ok {
		t.reply(ctx, msg.Chat.ID, botCopyFor(msg.From.LanguageCode).expired, "")
		return
	}
	t.prompt(ctx, msg.Chat.ID, session)
}

// the same button collects the same contact either way, but one of the two deletes an account, and
// asking for a number "to sign in" one tap before that would be a lie at the worst moment
func (t *TelegramAuth) prompt(ctx context.Context, chatID int64, session auth.SessionData) {
	words := botCopyFor(session.Lang)
	if session.Purpose == auth.HandshakeDeletion {
		t.reply(ctx, chatID, words.deletePrompt, words.deleteButton)
		return
	}
	t.reply(ctx, chatID, words.loginPrompt, words.loginButton)
}

func (t *TelegramAuth) handleContact(ctx context.Context, msg *telegram.Message) {
	chatID := msg.Chat.ID

	// **the check that makes a contact a proof rather than a claim.** telegram also lets anybody send
	// any card from their address book, which arrives here looking the same; user_id is the telegram
	// account the number belongs to (zero for a non-user), so a forwarded card fails this and its
	// sender cannot sign in as, or delete, the person on it.
	if msg.Contact.UserID != msg.From.ID {
		log.Printf("SECURITY: chat %d shared a contact that is not their own - refused", chatID)
		session, ok := t.Sessions.Linked(chatID)
		if !ok {
			t.reply(ctx, chatID, botCopyFor(msg.From.LanguageCode).expired, "")
			return
		}
		words := botCopyFor(session.Lang)
		button := words.loginButton
		if session.Purpose == auth.HandshakeDeletion {
			button = words.deleteButton
		}
		t.reply(ctx, chatID, words.notYourContact, button)
		return
	}

	id, session, ok := t.Sessions.Claim(chatID)
	if !ok {
		t.reply(ctx, chatID, botCopyFor(msg.From.LanguageCode).expired, "")
		return
	}
	words := botCopyFor(session.Lang)

	phone, ok := auth.CanonicalPhone(msg.Contact.PhoneNumber)
	if !ok {
		t.Sessions.Finish(id, auth.SessionData{Status: auth.SessionNotUzbek})
		t.reply(ctx, chatID, words.notUzbek, "")
		return
	}

	if session.Purpose == auth.HandshakeDeletion {
		t.finishDeletion(ctx, chatID, id, phone, words)
		return
	}
	t.finishLogin(ctx, chatID, id, phone, session, words)
}

// finishLogin is /api/auth/verify's tail on a number telegram proved: find or create, then the jwt.
func (t *TelegramAuth) finishLogin(ctx context.Context, chatID int64, id, phone string, session auth.SessionData, words botCopy) {
	dbCtx, cancel := dbctx.WithTimeout(ctx)
	defer cancel()

	user, err := upsertUser(dbCtx, t.Queries, auth.Pending{
		Purpose: auth.CodeLogin,
		Phone:   phone,
		Name:    session.Name,
		Role:    session.Role,
	})
	if err != nil {
		log.Printf("CRITICAL: could not register %s after telegram proved the number: %v", auth.MaskPhone(phone), err)
		t.Sessions.Finish(id, auth.SessionData{Status: auth.SessionFailed})
		t.reply(ctx, chatID, words.failed, "")
		return
	}

	// role is deliberately not a claim (internal/auth/jwt.go): a token outlives a role change
	token, err := auth.GenerateJWT(user.ID, user.Phone, user.TokenVersion, t.JWTSecret)
	if err != nil {
		log.Printf("CRITICAL: could not sign a token for user %d: %v", user.ID, err)
		t.Sessions.Finish(id, auth.SessionData{Status: auth.SessionFailed})
		t.reply(ctx, chatID, words.failed, "")
		return
	}

	t.Sessions.Finish(id, auth.SessionData{
		Status: auth.SessionSignedIn,
		Token:  token,
		UserID: user.ID,
		Name:   user.Name.String,
		Phone:  user.Phone,
		Role:   user.Role,
	})
	log.Printf("User %d signed in through telegram (role %s)", user.ID, user.Role)
	t.reply(ctx, chatID, words.signedIn, "")
}

// finishDeletion: the contact is the sender's own, so the account on that number is theirs to delete.
// **saying "no account" is safe here and nowhere before**: they have just proved they own the number.
func (t *TelegramAuth) finishDeletion(ctx context.Context, chatID int64, id, phone string, words botCopy) {
	dbCtx, cancel := dbctx.WithTimeout(ctx)
	defer cancel()

	user, err := t.Queries.GetUserByPhone(dbCtx, phone)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			t.Sessions.Finish(id, auth.SessionData{Status: auth.SessionNoAccount})
			t.reply(ctx, chatID, words.noAccount, "")
			return
		}
		log.Printf("CRITICAL: deletion lookup failed for %s: %v", auth.MaskPhone(phone), err)
		t.Sessions.Finish(id, auth.SessionData{Status: auth.SessionFailed})
		t.reply(ctx, chatID, words.failed, "")
		return
	}

	if err := eraseAccount(dbCtx, t.Queries, t.Images, user.ID); err != nil {
		log.Printf("CRITICAL: failed to delete user %d from the deletion page: %v", user.ID, err)
		t.Sessions.Finish(id, auth.SessionData{Status: auth.SessionFailed})
		t.reply(ctx, chatID, words.failed, "")
		return
	}

	// the id and nothing else: every other field was data the user just asked us to forget
	log.Printf("User %d deleted their account from the deletion page", user.ID)
	t.Sessions.Finish(id, auth.SessionData{Status: auth.SessionDeleted})
	t.reply(ctx, chatID, words.deleted, "")
}

// reply sends and logs a failure instead of returning it: the outcome is already in the session, and
// the app learns it from the poll whether or not the message arrives
func (t *TelegramAuth) reply(ctx context.Context, chatID int64, text, contactButton string) {
	sendCtx, cancel := context.WithTimeout(ctx, botReplyTimeout)
	defer cancel()

	if err := t.Bot.Send(sendCtx, telegram.Reply{ChatID: chatID, Text: text, ContactButton: contactButton}); err != nil {
		log.Printf("WARNING: could not answer telegram chat %d: %v", chatID, err)
	}
}
