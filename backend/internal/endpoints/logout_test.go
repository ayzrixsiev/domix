package endpoints

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
)

func tokenAt(t *testing.T, userID int64, version int32) string {
	t.Helper()

	token, err := auth.GenerateJWT(userID, "998900000000", version, testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}
	return token
}

func withToken(t *testing.T, ctx context.Context, a *Auth, handler http.HandlerFunc, method, target, token string) *httptest.ResponseRecorder {
	t.Helper()

	req := httptest.NewRequestWithContext(ctx, method, target, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, a.Queries, handler)(rec, req)
	return rec
}

// a revoked token must be refused as `unauthorized`, the code an expired one gets: that is what sends
// the app to the login screen, where any other refusal would be drawn as an error.
func TestALoggedOutTokenIsRefusedAndANewOneIsNot(t *testing.T) {
	authEndpoints, ctx, tx, q := accountUnderTest(t)
	userID := shopOwner(t, ctx, tx, makeSeededShop(t, ctx, tx, q, "Logout", catalog.CategoryWallpaper, false))

	old := tokenAt(t, userID, 0)
	if rec := withToken(t, ctx, authEndpoints, authEndpoints.Logout, http.MethodPost, "/api/me/logout", old); rec.Code != http.StatusOK {
		t.Fatalf("logout: want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	rec := withToken(t, ctx, authEndpoints, authEndpoints.RouteMe, http.MethodGet, "/api/me", old)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("the logged-out token still works: got %d: %s", rec.Code, rec.Body.String())
	}
	if got := errorCode(t, rec); got != "unauthorized" {
		t.Fatalf("refused with %q, want unauthorized - the code the app signs out on", got)
	}

	if rec := withToken(t, ctx, authEndpoints, authEndpoints.RouteMe, http.MethodGet, "/api/me", tokenAt(t, userID, 1)); rec.Code != http.StatusOK {
		t.Fatalf("a token minted after the logout is refused: got %d: %s", rec.Code, rec.Body.String())
	}
}
