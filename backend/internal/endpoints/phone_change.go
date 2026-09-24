package endpoints

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
)

// moving an existing account onto a different number: two posts and the same six-digit code.
//
//	POST /api/me/phone/request-code  {phone}        -> a code goes to the *new* number
//	POST /api/me/phone/verify        {phone, code}  -> users.phone is moved, nothing else changes
//
// **the code goes to the new number, and that is the whole proof** - sending it to the old one would
// prove only what the bearer token already says. the token is not re-issued: its phone claim is
// decorative, RequireAuth authorizes on user_id alone.

// POST /api/me/phone/request-code - send a code to the number the caller wants to move onto.
func (p *PhoneAuth) RequestPhoneChangeCode(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
		return
	}

	var req struct {
		Phone string `json:"phone"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	phone, ok := auth.CanonicalPhone(req.Phone)
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "invalid_phone", "that is not an uzbek phone number")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// **both checks happen before a message is paid for.** neither is a security boundary - five
	// minutes pass before verify, which repeats them - they exist to not spend an sms on a refusal.
	switch owner, err := p.phoneOwner(ctx, phone); {
	case err != nil:
		log.Printf("CRITICAL: could not check who owns %s: %v", auth.MaskPhone(phone), err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not start the change")
		return
	case owner == userID:
		// the number they already have - the app still needs to say why nothing is happening
		writeAPIError(w, http.StatusBadRequest, "phone_unchanged", "this is already your number")
		return
	case owner != 0:
		writeAPIError(w, http.StatusConflict, "phone_taken", "another account already uses this number")
		return
	}

	code, wait, err := p.Codes.Issue(auth.Pending{Purpose: auth.CodePhoneChange, Phone: phone})
	if err != nil {
		writeIssueError(w, err, wait)
		return
	}

	// detached from the request for the same money reason the login's send is
	sendCtx, cancelSend := context.WithTimeout(context.WithoutCancel(r.Context()), codeSendTimeout)
	defer cancelSend()

	if err := p.Sender.Send(sendCtx, phone, code); err != nil {
		p.Codes.Drop(phone)
		log.Printf("WARNING: could not deliver a phone-change code to %s: %v", auth.MaskPhone(phone), err)
		writeAPIError(w, http.StatusBadGateway, "code_not_sent", "could not send the code, try again")
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"sent":         true,
		"phone":        phone,
		"expires_in":   int(auth.CodeTTL.Seconds()),
		"resend_after": int(auth.ResendCooldown.Seconds()),
	})
}

// POST /api/me/phone/verify - the code was right, so the number is theirs. Move the account onto it.
func (p *PhoneAuth) VerifyPhoneChange(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
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

	// CodePhoneChange is what stops a login code for this number being spent here
	if _, err := p.Codes.Verify(auth.CodePhoneChange, phone, strings.TrimSpace(req.Code)); err != nil {
		writeCodeError(w, err)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	updated, err := p.Queries.UpdateUserPhone(ctx, db.UpdateUserPhoneParams{ID: userID, Phone: phone})
	if err != nil {
		// **the UNIQUE constraint is what is trusted here**, not the check at request time: five
		// minutes is long enough for somebody else to have registered on this number since
		if isUniqueViolation(err) {
			writeAPIError(w, http.StatusConflict, "phone_taken", "another account already uses this number")
			return
		}
		log.Printf("CRITICAL: could not move user %d onto %s: %v", userID, auth.MaskPhone(phone), err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not save the number")
		return
	}

	log.Printf("User %d moved onto %s", userID, auth.MaskPhone(phone))

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(meResponseOf(updated))
}

// phoneOwner answers which account holds this number, or 0 for nobody
func (p *PhoneAuth) phoneOwner(ctx context.Context, phone string) (int64, error) {
	user, found, err := p.findUser(ctx, phone)
	if err != nil || !found {
		return 0, err
	}
	return user.ID, nil
}

// 23505 is the SQLSTATE for a UNIQUE violation - matched on the code, not the message, which is
// localized by the server's lc_messages
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
