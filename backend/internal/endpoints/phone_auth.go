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
// the app's second sign-in, «Войти по номеру телефона», under the telegram button. **until Gateway's
// $100 balance is paid only the Play review account gets a code** (auth.CodeManager.CanDeliver); every
// other number is refused with sms_unavailable and the app sends it to telegram. paying for it is the
// whole switch-over: neither this nor the screen changes.
type PhoneAuth struct {
	Queries   *db.Queries
	Codes     *auth.CodeManager
	Sender    verify.Sender
	JWTSecret string
}

// an empty users.name is a blank line on every screen in the admin panel
const defaultUserName = "Domix User"

// the endpoint's own ceiling on one delivery attempt, so a provider that accepts a connection and
// then says nothing cannot hold this handler open
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

	// the pending codes are keyed by this string, so two spellings of one number would be a map miss
	// that reads as "you never asked for a code" - hence the same function here and in Verify
	phone, ok := auth.CanonicalPhone(req.Phone)
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "invalid_phone", "that is not an uzbek phone number")
		return
	}

	// before anything is minted: an unpaid sender would answer "sent" and print the code into the log
	if !p.Codes.CanDeliver(phone) {
		writeAPIError(w, http.StatusForbidden, "sms_unavailable", "sms sign-in is not available yet, use telegram")
		return
	}

	// anything that is not shop_owner is a customer, and an empty name gets a placeholder
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

	code, wait, err := p.Codes.Issue(auth.Pending{
		Purpose: auth.CodeLogin,
		Phone:   phone,
		Name:    name,
		Role:    role,
	})
	if err != nil {
		writeIssueError(w, err, wait)
		return
	}

	// the review account's code is a constant Google already has - see CodeManager.WithReviewAccount
	if p.Codes.NeedsDelivery(phone) {
		// **WithoutCancel is a money decision**: a phone changing cell tower would otherwise abort a send
		// the provider has already billed, and the code would be dropped - so the user gets an sms whose
		// digits no longer work. the deadline is what stops the detached attempt running forever.
		ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), codeSendTimeout)
		defer cancel()

		if err := p.Sender.Send(ctx, phone, code); err != nil {
			// leaving it would hold this number in a cooldown waiting for a message that was never sent
			p.Codes.Drop(phone)
			log.Printf("WARNING: could not deliver a login code to %s: %v", auth.MaskPhone(phone), err)
			writeAPIError(w, http.StatusBadGateway, "code_not_sent", "could not send the code, try again")
			return
		}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"sent":  true,
		"phone": phone, // echoed canonical, so the app sends back exactly what the code is keyed by
		// seconds, so the app draws its countdowns without hardcoding numbers in two repositories
		"expires_in":   int(auth.CodeTTL.Seconds()),
		"resend_after": int(auth.ResendCooldown.Seconds()),
	})
}

// the three ways minting a code can fail, each with its own code - the app shows a different screen
// for each: wait and watch a countdown, give up for today, or an outage
func writeIssueError(w http.ResponseWriter, err error, wait time.Duration) {
	switch {
	case errors.Is(err, auth.ErrResendTooSoon):
		// rounded up, never to zero: "retry in 0 seconds" is what makes an app retry immediately
		retryAfter := int(wait/time.Second) + 1
		w.Header().Set("Retry-After", strconv.Itoa(retryAfter))
		w.WriteHeader(http.StatusTooManyRequests)
		// the standard pair plus the countdown: a user who already has the sms can be sent straight
		// to the code screen on this answer
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

// what a correct code buys: the token, and the account it belongs to. the user is the same shape
// GET /api/me answers with, so the app has one profile model and one parser.
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
	// make this endpoint do work
	pending, err := p.Codes.Verify(auth.CodeLogin, phone, strings.TrimSpace(req.Code))
	if err != nil {
		writeCodeError(w, err)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	user, err := upsertUser(ctx, p.Queries, pending)
	if err != nil {
		log.Printf("CRITICAL: could not register %s after a correct code: %v", auth.MaskPhone(phone), err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not finish signing in")
		return
	}

	// role is deliberately not a claim (internal/auth/jwt.go): a token outlives a role change
	token, err := auth.GenerateJWT(user.ID, user.Phone, user.TokenVersion, p.JWTSecret)
	if err != nil {
		log.Printf("CRITICAL: could not sign a token for user %d: %v", user.ID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not finish signing in")
		return
	}

	log.Printf("User %d signed in with a code (role %s)", user.ID, user.Role)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(PhoneAuthResponse{Token: token, User: meResponseOf(user)})
}

// four codes rather than one: "that code is wrong" and "that code is dead" send the user to
// different places, and one message for both is how somebody keeps typing into a dead box
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

// upsertUser turns a proven number into an account row: found, upgraded, or created. a role only
// ever goes up (a returning owner who tapped "я покупатель" must not lose their shops); a name is
// taken as typed, and an empty one renames nothing. **it is why signing in and registering are one
// button**: whichever the user meant, a proven number lands here.
func upsertUser(ctx context.Context, q *db.Queries, pending auth.Pending) (db.User, error) {
	existing, found, err := findUser(ctx, q, pending.Phone)
	if err != nil {
		return db.User{}, err
	}

	if !found {
		name := pending.Name
		if name == "" {
			name = defaultUserName
		}
		created, err := q.CreateUser(ctx, db.CreateUserParams{
			Name:  pgtype.Text{String: name, Valid: true},
			Phone: pending.Phone,
			Role:  pending.Role,
		})
		if err != nil {
			return db.User{}, err
		}
		log.Printf("Registered a new account for %s", auth.MaskPhone(pending.Phone))
		return created, nil
	}

	roleChanged := existing.Role == "customer" && pending.Role == "shop_owner"
	nameChanged := pending.Name != "" && pending.Name != existing.Name.String
	if !roleChanged && !nameChanged {
		return existing, nil
	}

	newRole := existing.Role
	if roleChanged {
		newRole = "shop_owner"
	}
	newName := existing.Name.String
	if nameChanged {
		newName = pending.Name
	}

	updated, err := q.UpdateUserProfile(ctx, db.UpdateUserProfileParams{
		ID:   existing.ID,
		Name: pgtype.Text{String: newName, Valid: newName != ""},
		Role: newRole,
	})
	if err != nil {
		// the login itself did not fail, so signing them in with what is stored beats refusing over
		// a changed display name
		log.Printf("WARNING: could not update the profile of user %d while signing in: %v", existing.ID, err)
		return existing, nil
	}

	return updated, nil
}

// findUser looks a proven number up, by the one canonical spelling every row is written in.
func findUser(ctx context.Context, q *db.Queries, phone string) (db.User, bool, error) {
	user, err := q.GetUserByPhone(ctx, phone)
	if err != nil {
		// errors.Is, never a substring match: a database that fell over must not be read as "no such
		// user" and send us into CreateUser
		if errors.Is(err, pgx.ErrNoRows) {
			return db.User{}, false, nil
		}
		return db.User{}, false, err
	}
	return user, true, nil
}

func meResponseOf(user db.User) MeResponse {
	return MeResponse{
		ID:    user.ID,
		Name:  user.Name.String,
		Phone: user.Phone,
		Role:  user.Role,
	}
}
