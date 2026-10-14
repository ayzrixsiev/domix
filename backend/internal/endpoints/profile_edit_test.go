package endpoints

// editing an account that already exists: name and role through PATCH /api/me, the number through the
// two-step code flow at /api/me/phone. each rule here either costs money when it is wrong (a message
// sent for a change that cannot land) or hands one account another's identity, since users.phone is
// what every login looks a row up by.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"domix/backend/db"
	"domix/backend/internal/auth"
)

// authed runs a handler through the real RequireAuth with a real token for [userID], which is the
// only way the user id reaches the handler - it reads it off the context the middleware fills, so
// calling the handler directly would test a path the app never takes.
func authed(
	t *testing.T,
	ctx context.Context,
	queries *db.Queries,
	handler http.HandlerFunc,
	userID int64,
	method, target string,
	body map[string]any,
) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(userID, "998900000000", testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	var payload string
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("encoding the request: %v", err)
		}
		payload = string(encoded)
	}

	// the transaction-bound context, or dbctx.WithTimeout branches off Background and the query runs
	// on a connection the transaction does not own - see postAuthWithContext
	req := httptest.NewRequestWithContext(ctx, method, target, strings.NewReader(payload))
	req.Header.Set("Authorization", "Bearer "+token)

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, queries, handler)(rec, req)
	return rec
}

// a signed-in account to edit, built through the flow that really creates one.
func registeredUser(t *testing.T, ctx context.Context, p *PhoneAuth, sender *fakeSender, role string) (int64, string) {
	t.Helper()

	phone := unusedPhone()
	answer := signInWithACode(t, ctx, p, sender, phone, "Аброр", role)
	return answer.User.ID, answer.User.Phone
}

func storedUser(t *testing.T, ctx context.Context, queries *db.Queries, userID int64) db.GetUserByIDRow {
	t.Helper()

	user, err := queries.GetUserByID(ctx, userID)
	if err != nil {
		t.Fatalf("reading user %d back: %v", userID, err)
	}
	return user
}

// mistyped is a sent code with its last digit moved on by one: a realistic wrong guess, and one
// that can never happen to be the right code.
func mistyped(sent string) string {
	last := sent[len(sent)-1]
	if last == '9' {
		last = '0'
	} else {
		last++
	}
	return sent[:len(sent)-1] + string(last)
}

// ---------------------------------------------------------------------------------------------
// PATCH /api/me

func TestEditingTheProfileRenamesTheAccount(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	userID, _ := registeredUser(t, ctx, phoneAuth, sender, "customer")

	authEndpoints := &Auth{Queries: queries}
	rec := authed(t, ctx, queries, authEndpoints.RouteMe, userID,
		http.MethodPatch, "/api/me", map[string]any{"name": "  Азиз Рихсибой  "})

	if rec.Code != http.StatusOK {
		t.Fatalf("PATCH answered %d, want 200: %s", rec.Code, rec.Body.String())
	}
	// trimmed on the way in: a name padded with spaces is a blank-looking row in the admin panel
	if got := storedUser(t, ctx, queries, userID).Name.String; got != "Азиз Рихсибой" {
		t.Fatalf("the stored name is %q", got)
	}
}

// The one role change the app offers. A customer who registers a shop has to become a shop owner
// without signing out and back in, which is what this endpoint exists for.
func TestACustomerCanBecomeAShopOwner(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	userID, _ := registeredUser(t, ctx, phoneAuth, sender, "customer")

	authEndpoints := &Auth{Queries: queries}
	rec := authed(t, ctx, queries, authEndpoints.RouteMe, userID,
		http.MethodPatch, "/api/me", map[string]any{"role": "shop_owner"})

	if rec.Code != http.StatusOK {
		t.Fatalf("PATCH answered %d, want 200: %s", rec.Code, rec.Body.String())
	}
	if got := storedUser(t, ctx, queries, userID).Role; got != "shop_owner" {
		t.Fatalf("the stored role is %q, want shop_owner", got)
	}
}

// **The rule that keeps shops editable by the people who own them.** A demoted owner would keep
// every shop and lose the authorization to touch any of them, which is a state no screen in the app
// can get them out of - so the endpoint refuses rather than accepting and half-applying.
func TestARoleOnlyEverGoesUp(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	authEndpoints := &Auth{Queries: queries}

	cases := []struct {
		name string
		from string
		to   string
	}{
		{"an owner giving up their shops", "shop_owner", "customer"},
		{"an owner sidestepping into nothing", "shop_owner", "worker"},
		// the role that can delete anyone's shops is made in the database, never handed out here
		{"a customer promoting themselves to admin", "customer", "admin"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			userID, _ := registeredUser(t, ctx, phoneAuth, sender, c.from)

			rec := authed(t, ctx, queries, authEndpoints.RouteMe, userID,
				http.MethodPatch, "/api/me", map[string]any{"role": c.to})

			if rec.Code != http.StatusForbidden {
				t.Fatalf("PATCH answered %d, want 403: %s", rec.Code, rec.Body.String())
			}
			if got := errorCode(t, rec); got != "role_locked" {
				t.Fatalf("refused with %q, want role_locked", got)
			}
			if got := storedUser(t, ctx, queries, userID).Role; got != c.from {
				t.Fatalf("the role moved to %q anyway", got)
			}
		})
	}
}

// An omitted field is not a field set to empty. Without the distinction, saving a role change would
// blank the name of everyone who made one.
func TestAnOmittedFieldIsLeftAlone(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	userID, phone := registeredUser(t, ctx, phoneAuth, sender, "customer")

	authEndpoints := &Auth{Queries: queries}
	rec := authed(t, ctx, queries, authEndpoints.RouteMe, userID,
		http.MethodPatch, "/api/me", map[string]any{"role": "shop_owner"})
	if rec.Code != http.StatusOK {
		t.Fatalf("PATCH answered %d, want 200: %s", rec.Code, rec.Body.String())
	}

	after := storedUser(t, ctx, queries, userID)
	if after.Name.String != "Аброр" || after.Phone != phone {
		t.Fatalf("a role change touched the rest of the row: %+v", after)
	}
}

func TestAnEmptyNameIsRefused(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	userID, _ := registeredUser(t, ctx, phoneAuth, sender, "customer")

	authEndpoints := &Auth{Queries: queries}
	rec := authed(t, ctx, queries, authEndpoints.RouteMe, userID,
		http.MethodPatch, "/api/me", map[string]any{"name": "   "})

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("PATCH answered %d, want 400: %s", rec.Code, rec.Body.String())
	}
	if got := errorCode(t, rec); got != "name_required" {
		t.Fatalf("refused with %q, want name_required", got)
	}
}

// ---------------------------------------------------------------------------------------------
// the phone change

// changePhone walks both steps the app walks and returns the verify answer.
func changePhone(
	t *testing.T,
	ctx context.Context,
	p *PhoneAuth,
	sender *fakeSender,
	queries *db.Queries,
	userID int64,
	to string,
) *httptest.ResponseRecorder {
	t.Helper()

	rec := authed(t, ctx, queries, p.RequestPhoneChangeCode, userID,
		http.MethodPost, "/api/me/phone/request-code", map[string]any{"phone": to})
	if rec.Code != http.StatusOK {
		return rec
	}

	_, code, _ := sender.delivered()
	return authed(t, ctx, queries, p.VerifyPhoneChange, userID,
		http.MethodPost, "/api/me/phone/verify", map[string]any{"phone": to, "code": code})
}

// The whole point: the account moves onto the new number and stays the same account - same id, same
// shops, same name.
func TestAProvenNumberMovesTheAccount(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	userID, _ := registeredUser(t, ctx, phoneAuth, sender, "shop_owner")

	// a fresh manager, since signing in already spent this test's cooldown on the old number
	phoneAuth.Codes = auth.NewCodeManager(true)
	newPhone := unusedPhone()

	rec := changePhone(t, ctx, phoneAuth, sender, queries, userID, newPhone)
	if rec.Code != http.StatusOK {
		t.Fatalf("the change answered %d, want 200: %s", rec.Code, rec.Body.String())
	}

	after := storedUser(t, ctx, queries, userID)
	if after.Phone != newPhone {
		t.Fatalf("the stored number is %q, want %q", after.Phone, newPhone)
	}
	if after.Name.String != "Аброр" || after.Role != "shop_owner" {
		t.Fatalf("the change touched the rest of the row: %+v", after)
	}

	// and the code went to the number being claimed, never to the one being left - the old one
	// proves nothing the bearer token does not already prove
	delivered, _, _ := sender.delivered()
	if delivered != newPhone {
		t.Fatalf("the code went to %q, want the new number %q", delivered, newPhone)
	}
}

// users.phone is UNIQUE, so this would fail on the constraint anyway - but only *after* a message
// had been paid for. Refusing before the send is the whole reason the check is at request time.
func TestANumberAnotherAccountHoldsIsRefusedBeforeTheSend(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	_, taken := registeredUser(t, ctx, phoneAuth, sender, "customer")
	mover, _ := registeredUser(t, ctx, phoneAuth, sender, "customer")

	phoneAuth.Codes = auth.NewCodeManager(true)
	_, _, before := sender.delivered()

	rec := authed(t, ctx, queries, phoneAuth.RequestPhoneChangeCode, mover,
		http.MethodPost, "/api/me/phone/request-code", map[string]any{"phone": taken})

	if rec.Code != http.StatusConflict {
		t.Fatalf("request-code answered %d, want 409: %s", rec.Code, rec.Body.String())
	}
	if got := errorCode(t, rec); got != "phone_taken" {
		t.Fatalf("refused with %q, want phone_taken", got)
	}
	if _, _, after := sender.delivered(); after != before {
		t.Fatal("a message was paid for on a number the change could never land on")
	}
}

// The number they already have. Every send costs money, and there is nothing here to prove.
func TestChangingToTheSameNumberSendsNothing(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	userID, phone := registeredUser(t, ctx, phoneAuth, sender, "customer")

	phoneAuth.Codes = auth.NewCodeManager(true)
	_, _, before := sender.delivered()

	rec := authed(t, ctx, queries, phoneAuth.RequestPhoneChangeCode, userID,
		http.MethodPost, "/api/me/phone/request-code", map[string]any{"phone": phone})

	if got := errorCode(t, rec); got != "phone_unchanged" {
		t.Fatalf("refused with %q (%d), want phone_unchanged", got, rec.Code)
	}
	if _, _, after := sender.delivered(); after != before {
		t.Fatal("a message was paid for to confirm a number that was never changing")
	}
}

// **The purpose separation, at the http boundary.** A login code and a phone-change code are six
// digits sent to the same number by the same provider; if the endpoints could spend each other's,
// a number caught mid-signup would be movable onto somebody else's account by whoever talked its
// owner into reading out "their" code.
func TestALoginCodeCannotMoveAnAccount(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	userID, phone := registeredUser(t, ctx, phoneAuth, sender, "customer")

	phoneAuth.Codes = auth.NewCodeManager(true)
	target := unusedPhone()

	// a *login* code for the number, minted by the public endpoint
	rec := postAuthWithContext(t, ctx, phoneAuth.RequestCode, "/api/auth/request-code",
		map[string]string{"phone": target, "name": "Кто-то", "role": "customer"})
	if rec.Code != http.StatusOK {
		t.Fatalf("request-code answered %d, want 200: %s", rec.Code, rec.Body.String())
	}
	_, code, _ := sender.delivered()

	rec = authed(t, ctx, queries, phoneAuth.VerifyPhoneChange, userID,
		http.MethodPost, "/api/me/phone/verify", map[string]any{"phone": target, "code": code})

	if rec.Code == http.StatusOK {
		t.Fatal("a login code moved an account onto the number it was sent to")
	}
	if got := errorCode(t, rec); got != "code_not_found" {
		t.Fatalf("refused with %q, want code_not_found", got)
	}
	if got := storedUser(t, ctx, queries, userID).Phone; got != phone {
		t.Fatalf("the number moved to %q anyway", got)
	}
}

// A wrong code has to leave the account exactly where it was - and the endpoint has to say which
// kind of wrong it was, since "mistyped" sends the user back to the keypad and "dead" sends them
// back to request another.
func TestAWrongCodeLeavesTheNumberAlone(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)
	userID, phone := registeredUser(t, ctx, phoneAuth, sender, "customer")

	phoneAuth.Codes = auth.NewCodeManager(true)
	target := unusedPhone()

	rec := authed(t, ctx, queries, phoneAuth.RequestPhoneChangeCode, userID,
		http.MethodPost, "/api/me/phone/request-code", map[string]any{"phone": target})
	if rec.Code != http.StatusOK {
		t.Fatalf("request-code answered %d, want 200: %s", rec.Code, rec.Body.String())
	}

	// the sent code with its last digit moved on - a realistic mistype, rather than a constant that
	// is the real code once in a million runs
	_, sent, _ := sender.delivered()
	rec = authed(t, ctx, queries, phoneAuth.VerifyPhoneChange, userID,
		http.MethodPost, "/api/me/phone/verify", map[string]any{"phone": target, "code": mistyped(sent)})

	if got := errorCode(t, rec); got != "code_invalid" {
		t.Fatalf("refused with %q (%d), want code_invalid", got, rec.Code)
	}
	if got := storedUser(t, ctx, queries, userID).Phone; got != phone {
		t.Fatalf("the number moved to %q on a wrong code", got)
	}
}
