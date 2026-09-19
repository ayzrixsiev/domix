package endpoints

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/verify"
)

// the phone-code login: two posts and a jwt.
//
//	POST /api/auth/request-code  {phone, name, role} -> a code is delivered to that number
//	POST /api/auth/verify        {phone, code}       -> the account is created or found, jwt back
//
// **This replaces the telegram handshake, and the shape of the replacement is the point.** The old
// flow had three round trips and a detour through another app: init a session, open t.me, share a
// contact, then poll /api/auth/status every two seconds until a bot somewhere completed it. Every
// one of those steps was a place to lose a user, and the status poll was a public endpoint that
// hands out a jwt to whoever names a live session id. Here the proof of ownership is the code
// itself, so there is no session to poll, nothing to guess and nobody has to leave the app.
//
// The name and role travel with the *request* for the code rather than with the verification: by
// the time the code comes back the user is on a keypad screen, and asking them to retype their name
// there would be asking twice for something already given. They are held in ram with the code (see
// auth.CodeManager) and land in the database only once the number is proven - which is what keeps an
// abandoned signup from leaving a row behind.
type PhoneAuth struct {
	Queries   *db.Queries
	Codes     *auth.CodeManager
	Sender    verify.Sender
	JWTSecret string
}

// what an unnamed account is called. the app asks for a name, but an empty string in users.name is a
// blank line in the admin panel and in every support thread.
const defaultUserName = "Domix User"

// how long one delivery attempt gets. verify.Sender has its own client timeout; this is the
// endpoint's own ceiling on the whole attempt, so a provider that accepts a connection and then says
// nothing cannot hold this handler open.
const codeSendTimeout = 15 * time.Second

// POST /api/auth/request-code - mint a code for this number and hand it to the provider.
func (p *PhoneAuth) RequestCode(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Phone string `json:"phone"`
		Name  string `json:"name"`
		Role  string `json:"role"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	// normalized here *and* in Verify, with the same function. the pending codes are keyed by this
	// string, so two spellings of one number is a map miss that reads as "you never asked for a code"
	phone, ok := auth.CanonicalPhone(req.Phone)
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "invalid_phone", "that is not an uzbek phone number")
		return
	}

	// the same two rules the telegram flow applied: anything that is not shop_owner is a customer,
	// and an empty name gets a placeholder rather than a blank row.
	role := req.Role
	if role != "shop_owner" {
		role = "customer"
	}

	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = defaultUserName
	}
	if utf8.RuneCountInString(name) > maxUserNameLen {
		writeAPIError(w, http.StatusBadRequest, "name_too_long", "name is longer than the maximum allowed length")
		return
	}

	code, wait, err := p.Codes.Issue(phone, name, role)
	if err != nil {
		p.writeIssueError(w, err, wait)
		return
	}

	// **context.WithoutCancel, and this is a money decision.** A phone changing cell tower mid-request
	// cancels r.Context(), which would abort a send that the provider may already have accepted and
	// billed - and the code would then be dropped below, so the user receives a message whose digits
	// no longer work. Detaching means the attempt always runs to a real answer; the deadline is what
	// stops it running forever.
	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), codeSendTimeout)
	defer cancel()

	if err := p.Sender.Send(ctx, phone, code); err != nil {
		// the pending entry goes with the failure. leaving it would hold this number in a
		// sixty-second cooldown waiting for a message that was never sent.
		p.Codes.Drop(phone)
		log.Printf("WARNING: could not deliver a login code to %s: %v", auth.MaskPhone(phone), err)
		writeAPIError(w, http.StatusBadGateway, "code_not_sent", "could not send the code, try again")
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"sent":  true,
		"phone": phone, // echoed canonical, so the app sends back exactly what the code is keyed by
		// both in seconds, so the app can draw its own expiry and resend countdowns without
		// hardcoding numbers that then have to be changed in two repositories at once
		"expires_in":   int(auth.CodeTTL.Seconds()),
		"resend_after": int(auth.ResendCooldown.Seconds()),
	})
}

// the three ways minting a code can fail, each with its own machine-readable code because the app
// shows a different screen for each: wait and watch a countdown, give up for today, or an outage.
func (p *PhoneAuth) writeIssueError(w http.ResponseWriter, err error, wait time.Duration) {
	switch {
	case errors.Is(err, auth.ErrResendTooSoon):
		// rounded up, never to zero: "retry in 0 seconds" is what makes an app retry immediately
		retryAfter := int(wait/time.Second) + 1
		w.Header().Set("Retry-After", strconv.Itoa(retryAfter))
		w.WriteHeader(http.StatusTooManyRequests)
		// the standard {error, code} pair plus the countdown. a user who already has the sms in hand
		// can be sent straight to the code screen on this answer rather than being made to wait.
		json.NewEncoder(w).Encode(map[string]any{
			"error":       "a code was already sent to this number",
			"code":        "code_cooldown",
			"retry_after": retryAfter,
		})

	case errors.Is(err, auth.ErrSendBudget):
		writeAPIError(w, http.StatusTooManyRequests, "code_quota",
			"too many codes have been sent to this number, try again later")

	default:
		log.Printf("CRITICAL: could not mint a verification code: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not start the login")
	}
}

// PhoneAuthResponse is what a correct code buys: the token, and the account it belongs to.
//
// The user object is the same shape GET /api/me answers with, deliberately - the app stores one
// profile model, and a login that handed back a differently-shaped user would need a second parser
// for the same three fields.
type PhoneAuthResponse struct {
	Token string     `json:"token"`
	User  MeResponse `json:"user"`
}

// POST /api/auth/verify - check the code, create or find the account, mint the jwt.
func (p *PhoneAuth) Verify(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Phone string `json:"phone"`
		Code  string `json:"code"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	phone, ok := auth.CanonicalPhone(req.Phone)
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "invalid_phone", "that is not an uzbek phone number")
		return
	}

	// nothing touches the database until the code is right: an unproven number must not be able to
	// make this endpoint do work, and a wrong guess must not be distinguishable by how long it took.
	pending, err := p.Codes.Verify(phone, strings.TrimSpace(req.Code))
	if err != nil {
		writeCodeError(w, err)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	user, err := p.upsertUser(ctx, pending)
	if err != nil {
		log.Printf("CRITICAL: could not register %s after a correct code: %v", auth.MaskPhone(phone), err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not finish signing in")
		return
	}

	// role is deliberately not a claim - see internal/auth/jwt.go. a token lives four months and a
	// role can change inside that, so every check asks the database.
	token, err := auth.GenerateJWT(user.ID, user.Phone, p.JWTSecret)
	if err != nil {
		log.Printf("CRITICAL: could not sign a token for user %d: %v", user.ID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not finish signing in")
		return
	}

	log.Printf("User %d signed in with a code (role %s)", user.ID, user.Role)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(PhoneAuthResponse{Token: token, User: user})
}

// every way a typed code can be refused. four codes rather than one, because "that code is wrong"
// and "that code is dead, ask for another" send the user to different places - and a single
// message for both is how someone ends up typing into a box that will never accept anything.
func writeCodeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrNoPendingCode):
		writeAPIError(w, http.StatusBadRequest, "code_not_found", "no code was requested for this number")
	case errors.Is(err, auth.ErrCodeExpired):
		writeAPIError(w, http.StatusBadRequest, "code_expired", "that code has expired, request a new one")
	case errors.Is(err, auth.ErrTooManyAttempts):
		writeAPIError(w, http.StatusUnauthorized, "code_attempts_exhausted", "too many wrong attempts, request a new code")
	default:
		writeAPIError(w, http.StatusUnauthorized, "code_invalid", "that code is not correct")
	}
}

// upsertUser turns a proven number into an account row: found, upgraded, or created.
//
// The rules are the ones the telegram handler already applied, kept identical on purpose so the two
// flows cannot produce two different ideas of what logging in means while both are live:
//   - a role only ever goes up, customer -> shop_owner. a returning shop owner who happens to tap
//     "я покупатель" must not lose the shops they own.
//   - a name is taken as typed, either direction, because it is theirs to change.
func (p *PhoneAuth) upsertUser(ctx context.Context, pending auth.Pending) (MeResponse, error) {
	existing, found, err := p.findUser(ctx, pending.Phone)
	if err != nil {
		return MeResponse{}, err
	}

	if !found {
		created, err := p.Queries.CreateUser(ctx, db.CreateUserParams{
			Name:  pgtype.Text{String: pending.Name, Valid: pending.Name != ""},
			Phone: pending.Phone,
			Role:  pending.Role,
		})
		if err != nil {
			return MeResponse{}, err
		}
		log.Printf("Registered a new account for %s", auth.MaskPhone(pending.Phone))
		return meResponseOf(created), nil
	}

	roleChanged := existing.Role == "customer" && pending.Role == "shop_owner"
	nameChanged := pending.Name != "" && pending.Name != existing.Name.String
	if !roleChanged && !nameChanged {
		return meResponseOf(existing), nil
	}

	newRole := existing.Role
	if roleChanged {
		newRole = "shop_owner"
	}
	newName := existing.Name.String
	if nameChanged {
		newName = pending.Name
	}

	updated, err := p.Queries.UpdateUserProfile(ctx, db.UpdateUserProfileParams{
		ID:   existing.ID,
		Name: pgtype.Text{String: newName, Valid: newName != ""},
		Role: newRole,
	})
	if err != nil {
		// the profile edit failed but the login itself did not - the account exists and the number is
		// proven, so signing them in with what is stored beats refusing over a changed display name
		log.Printf("WARNING: could not update the profile of user %d while signing in: %v", existing.ID, err)
		return meResponseOf(existing), nil
	}

	return meResponseOf(updated), nil
}

// findUser looks a proven number up under both spellings it could have been stored as.
//
// **This is a migration detail with a very sharp edge.** users.phone holds whatever telegram
// reported at registration, and telegram sends some clients' numbers with a leading '+'. The
// canonical form has none, and users.phone is UNIQUE - so looking up only the canonical spelling
// would miss a user registered through the old flow and register them a *second* time, on a row
// that owns none of their shops, while the original row keeps the name they are known by.
//
// Two primary-key lookups instead of one, and it can go the day the old rows are normalized (a
// one-line UPDATE, once the telegram flow is gone and nothing is writing the '+' form any more).
func (p *PhoneAuth) findUser(ctx context.Context, phone string) (db.User, bool, error) {
	for _, spelling := range []string{phone, "+" + phone} {
		user, err := p.Queries.GetUserByPhone(ctx, spelling)
		if err == nil {
			return user, true, nil
		}
		// errors.Is against pgx's sentinel, never a substring match on the message - a database that
		// just fell over must not be read as "this user does not exist" and send us into CreateUser
		if !errors.Is(err, pgx.ErrNoRows) {
			return db.User{}, false, err
		}
	}
	return db.User{}, false, nil
}

func meResponseOf(user db.User) MeResponse {
	return MeResponse{
		ID:    user.ID,
		Name:  user.Name.String,
		Phone: user.Phone,
		Role:  user.Role,
	}
}
