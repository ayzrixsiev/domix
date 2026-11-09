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

	token, err := auth.GenerateJWT(userID, "998900000000", 0, testJWTSecret)
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
