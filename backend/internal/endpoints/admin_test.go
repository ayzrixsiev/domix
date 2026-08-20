package endpoints

// the admin api is the only place in this service where one caller acts on another user's data, so
// what these tests pin is almost entirely the boundary rather than the output.
//
// the shape of the bug they exist to catch: every one of these endpoints is correct-looking on its
// own, and the whole security model is a single `role != "admin"` comparison in a middleware that
// something else has to remember to wrap them in. a route registered without RequireAdmin still
// compiles, still returns json, and hands the shop list to any logged-in customer.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
)

// every test here runs inside the transaction homeUnderTest opens and t.Cleanup rolls back, so the
// DELETE below never reaches committed data - it only clears the rows this test's own view can see.
// it is here because the statistics are counts over whole tables: with the developer's own rows
// visible, "two users" would be "two plus whatever is in the local database" and the assertions
// would pass or fail depending on whose laptop ran them.
//
// deleting users is enough to clear all three tables - shops and products cascade off it.
func adminUnderTest(t *testing.T) (*Admin, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	_, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM users"); err != nil {
		t.Fatalf("clearing users: %v", err)
	}
	return &Admin{Queries: q}, ctx, tx, q
}

func makeUser(t *testing.T, ctx context.Context, q *db.Queries, name, role string) int64 {
	t.Helper()

	user, err := q.CreateUser(ctx, db.CreateUserParams{
		Name:  pgtype.Text{String: name, Valid: true},
		Phone: "+99890" + name,
		Role:  role,
	})
	if err != nil {
		t.Fatalf("create %s %q: %v", role, name, err)
	}
	return user.ID
}

// drives a handler through the *real* middleware chain - RequireAuth then RequireAdmin - with a
// real signed token, because that composition is the thing under test. calling the handler directly
// would exercise a path no request ever takes and would pass with the authorization removed.
func requestAdmin(t *testing.T, ctx context.Context, a *Admin, method, target string, asUserID int64, handler http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "+998900000000", testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	req := httptest.NewRequestWithContext(ctx, method, target, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	// httptest does not populate the mux's path wildcards, so the id the handler reads has to be
	// set the way the router would have set it
	if id := lastPathSegment(target); id != "" {
		req.SetPathValue("id", id)
	}

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, a.Queries, a.RequireAdmin(handler))(rec, req)
	return rec
}

func lastPathSegment(target string) string {
	for i := len(target) - 1; i >= 0; i-- {
		if target[i] == '/' {
			seg := target[i+1:]
			if _, err := strconv.ParseInt(seg, 10, 64); err == nil {
				return seg
			}
			return ""
		}
	}
	return ""
}

func decodeBody(t *testing.T, rec *httptest.ResponseRecorder, into any) {
	t.Helper()
	if err := json.Unmarshal(rec.Body.Bytes(), into); err != nil {
		t.Fatalf("decode %s: %v", rec.Body.String(), err)
	}
}

// ─────────────────────────── the boundary ───────────────────────────

// the one that matters. a customer and a shop owner are both fully authenticated - they hold a
// valid signed token for a live account - and RequireAuth lets both through, which is exactly why
// the role check cannot live there.
func TestOnlyAnAdminReachesTheAdminAPI(t *testing.T) {
	adminEndpoints, ctx, _, q := adminUnderTest(t)

	customerID := makeUser(t, ctx, q, "Customer", "customer")
	ownerID := makeUser(t, ctx, q, "Owner", "shop_owner")
	adminID := makeUser(t, ctx, q, "Admin", "admin")

	routes := []struct {
		name    string
		method  string
		target  string
		handler http.HandlerFunc
	}{
		{"stats", http.MethodGet, "/api/admin/stats", adminEndpoints.Stats},
		{"users", http.MethodGet, "/api/admin/users", adminEndpoints.ListUsers},
		{"shops", http.MethodGet, "/api/admin/shops", adminEndpoints.ListShops},
		// the support inbox is the one route here that reads what a *user* wrote in confidence, so
		// it is also the one whose leak would be worst
		{"support inbox", http.MethodGet, "/api/admin/support/threads", adminEndpoints.SupportThreads},
	}

	for _, route := range routes {
		for _, caller := range []struct {
			role string
			id   int64
		}{{"customer", customerID}, {"shop_owner", ownerID}} {
			rec := requestAdmin(t, ctx, adminEndpoints, route.method, route.target, caller.id, route.handler)
			if rec.Code != http.StatusForbidden {
				t.Errorf("%s as %s = %d, want 403", route.name, caller.role, rec.Code)
			}

			var body map[string]string
			decodeBody(t, rec, &body)
			if body["code"] != "forbidden_role" {
				t.Errorf("%s as %s returned code %q, want forbidden_role", route.name, caller.role, body["code"])
			}
		}

		if rec := requestAdmin(t, ctx, adminEndpoints, route.method, route.target, adminID, route.handler); rec.Code != http.StatusOK {
			t.Errorf("%s as admin = %d (%s), want 200", route.name, rec.Code, rec.Body.String())
		}
	}
}

// the reason jwt.go carries no role claim, stated as a test. a token is a signed snapshot of the
// moment it was issued and it lives four months; if the role were read out of it, demoting an
// administrator would take effect whenever their token happened to expire.
func TestARevokedAdminLosesAccessOnTheNextRequest(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "Demoted", "admin")

	if rec := requestAdmin(t, ctx, adminEndpoints, http.MethodGet, "/api/admin/stats", adminID, adminEndpoints.Stats); rec.Code != http.StatusOK {
		t.Fatalf("as admin = %d, want 200", rec.Code)
	}

	if _, err := tx.Exec(ctx, "UPDATE users SET role = 'customer' WHERE id = $1", adminID); err != nil {
		t.Fatalf("demote: %v", err)
	}

	// the same token, unchanged and still cryptographically valid
	if rec := requestAdmin(t, ctx, adminEndpoints, http.MethodGet, "/api/admin/stats", adminID, adminEndpoints.Stats); rec.Code != http.StatusForbidden {
		t.Errorf("after demotion = %d, want 403 - the role was read from the token, not the database", rec.Code)
	}
}

// ─────────────────────────── deleting users ───────────────────────────

// the panel's delete button is the same cascade DELETE /api/me runs, reached by a different caller.
// what this checks is that it is actually reached: a user row that goes while its shops stay behind
// leaves pins on a map pointing at a business nobody owns.
func TestAdminDeletingAUserTakesTheirShopsAndProducts(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "Boss", "admin")
	shopID := makeSeededShop(t, ctx, tx, q, "Doomed", catalog.CategoryWallpaper, false)
	ownerID := shopOwner(t, ctx, tx, shopID)

	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM products WHERE shop_id = $1", shopID); n != int64(len(catalog.Template(string(catalog.CategoryWallpaper)))) {
		t.Fatalf("shop seeded with %d products, want %d", n, len(catalog.Template(string(catalog.CategoryWallpaper))))
	}

	rec := requestAdmin(t, ctx, adminEndpoints, http.MethodDelete,
		"/api/admin/users/"+strconv.FormatInt(ownerID, 10), adminID, adminEndpoints.DeleteUser)
	if rec.Code != http.StatusOK {
		t.Fatalf("delete user = %d (%s), want 200", rec.Code, rec.Body.String())
	}

	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE id = $1", ownerID); n != 0 {
		t.Errorf("user rows left: %d", n)
	}
	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM shops WHERE user_id = $1", ownerID); n != 0 {
		t.Errorf("shop rows left: %d", n)
	}
	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM products WHERE shop_id = $1", shopID); n != 0 {
		t.Errorf("product rows left: %d", n)
	}
}

// a panel whose delete button can remove the last administrator is a tool that can destroy itself,
// and the recovery is SQL against production. the guard covers the caller's own row too, which is
// the realistic way it gets hit - an admin scrolling their own user list.
func TestAnAdminAccountCannotBeDeletedThroughThePanel(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "First", "admin")
	otherAdminID := makeUser(t, ctx, q, "Second", "admin")

	for _, target := range []struct {
		name string
		id   int64
	}{{"another admin", otherAdminID}, {"themselves", adminID}} {
		rec := requestAdmin(t, ctx, adminEndpoints, http.MethodDelete,
			"/api/admin/users/"+strconv.FormatInt(target.id, 10), adminID, adminEndpoints.DeleteUser)

		if rec.Code != http.StatusForbidden {
			t.Errorf("deleting %s = %d, want 403", target.name, rec.Code)
		}
		var body map[string]string
		decodeBody(t, rec, &body)
		if body["code"] != "cannot_delete_admin" {
			t.Errorf("deleting %s returned code %q, want cannot_delete_admin", target.name, body["code"])
		}
		if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE id = $1", target.id); n != 1 {
			t.Errorf("deleting %s actually removed the row", target.name)
		}
	}
}

func TestDeletingAMissingUserIsA404(t *testing.T) {
	adminEndpoints, ctx, _, q := adminUnderTest(t)
	adminID := makeUser(t, ctx, q, "Boss2", "admin")

	rec := requestAdmin(t, ctx, adminEndpoints, http.MethodDelete, "/api/admin/users/999999999", adminID, adminEndpoints.DeleteUser)
	if rec.Code != http.StatusNotFound {
		t.Errorf("delete missing user = %d, want 404", rec.Code)
	}
}

// ─────────────────────────── deleting shops ───────────────────────────

// the asymmetry with deleting a user, and the reason the panel says so in the confirm dialog: a
// shop is one of an owner's possessions, not the owner.
func TestAdminDeletingAShopLeavesTheOwnerAlone(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "Boss3", "admin")
	shopID := makeSeededShop(t, ctx, tx, q, "Closing", catalog.CategoryWood, false)
	ownerID := shopOwner(t, ctx, tx, shopID)

	rec := requestAdmin(t, ctx, adminEndpoints, http.MethodDelete,
		"/api/admin/shops/"+strconv.FormatInt(shopID, 10), adminID, adminEndpoints.DeleteShop)
	if rec.Code != http.StatusOK {
		t.Fatalf("delete shop = %d (%s), want 200", rec.Code, rec.Body.String())
	}

	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM shops WHERE id = $1", shopID); n != 0 {
		t.Errorf("shop rows left: %d", n)
	}
	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM products WHERE shop_id = $1", shopID); n != 0 {
		t.Errorf("product rows left: %d", n)
	}
	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE id = $1", ownerID); n != 1 {
		t.Errorf("the owner was deleted along with their shop")
	}
}

// ─────────────────────────── statistics ───────────────────────────

// `shops_ranked` is the number the dashboard leads with, and it means one specific thing after
// migration 000013: shops that have priced their *entire* template. a shop one row short of
// finished contributes nothing - not a partial index, not a share of the market average - so a
// dashboard that counted it would report the comparison as working when it is empty.
func TestStatsCountsOnlyCompleteBasketsAsRanked(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "Boss4", "admin")
	full := makeSeededShop(t, ctx, tx, q, "Full", catalog.CategoryWallpaper, false)
	partial := makeSeededShop(t, ctx, tx, q, "Partial", catalog.CategoryWallpaper, false)

	priceAll(t, ctx, tx, full, 100000)
	priceAll(t, ctx, tx, partial, 100000)
	// one row unpriced is the whole difference between being in the comparison and not
	if _, err := tx.Exec(ctx,
		`UPDATE products SET price = NULL WHERE id = (
		   SELECT id FROM products WHERE shop_id = $1 AND template_key IS NOT NULL LIMIT 1)`, partial); err != nil {
		t.Fatalf("unprice one row: %v", err)
	}

	rec := requestAdmin(t, ctx, adminEndpoints, http.MethodGet, "/api/admin/stats", adminID, adminEndpoints.Stats)
	if rec.Code != http.StatusOK {
		t.Fatalf("stats = %d (%s)", rec.Code, rec.Body.String())
	}

	var stats adminStatsResponse
	decodeBody(t, rec, &stats)

	if stats.Shops.Total != 2 {
		t.Errorf("shops.total = %d, want 2", stats.Shops.Total)
	}
	if stats.Shops.Ranked != 1 {
		t.Errorf("shops.ranked = %d, want 1 - one shop is a single unpriced row short of complete", stats.Shops.Ranked)
	}

	wantPriced := int64(len(catalog.Template(string(catalog.CategoryWallpaper)))*2 - 1)
	if stats.Products.Priced != wantPriced {
		t.Errorf("products.priced = %d, want %d", stats.Products.Priced, wantPriced)
	}

	// thirty days including today, empty days included - the gap is what makes the chart readable
	if len(stats.Signups) != 30 {
		t.Errorf("signups has %d days, want 30", len(stats.Signups))
	}
}

// the shop list is the one place the raw index leaves the server, and it must arrive null rather
// than zero for a shop that has no index - a panel reading 0 would render "cheapest on the market".
func TestShopListSendsANullIndexForAnIncompleteCatalogue(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "Boss5", "admin")
	priced := makeSeededShop(t, ctx, tx, q, "Priced", catalog.CategoryWallpaper, false)
	makeSeededShop(t, ctx, tx, q, "Blank", catalog.CategoryWallpaper, false)
	priceAll(t, ctx, tx, priced, 50000)

	rec := requestAdmin(t, ctx, adminEndpoints, http.MethodGet, "/api/admin/shops", adminID, adminEndpoints.ListShops)
	if rec.Code != http.StatusOK {
		t.Fatalf("shops = %d (%s)", rec.Code, rec.Body.String())
	}

	var body struct {
		Shops []adminShopResponse `json:"shops"`
		Limit int32               `json:"limit"`
	}
	decodeBody(t, rec, &body)

	if len(body.Shops) != 2 {
		t.Fatalf("got %d shops, want 2", len(body.Shops))
	}
	for _, shop := range body.Shops {
		complete := shop.TemplateTotal > 0 && shop.TemplatePriced == shop.TemplateTotal
		if complete && shop.PriceIndex == nil {
			t.Errorf("%q has a complete catalogue but no index", shop.Name)
		}
		if !complete && shop.PriceIndex != nil {
			t.Errorf("%q has %d/%d priced but carries index %d", shop.Name, shop.TemplatePriced, shop.TemplateTotal, *shop.PriceIndex)
		}
		// the view has no partial state, so these two are null together or present together
		if (shop.PriceIndex == nil) != (shop.BasketPrice == nil) {
			t.Errorf("%q has index and basket price disagreeing about nullness", shop.Name)
		}
	}
}

// a list endpoint that hands back whatever `limit` a caller asks for is the one place in the api
// where a typo in a url bar pulls the whole database into memory.
func TestListLimitIsClamped(t *testing.T) {
	adminEndpoints, ctx, _, q := adminUnderTest(t)
	adminID := makeUser(t, ctx, q, "Boss6", "admin")

	for _, tc := range []struct {
		query string
		want  int32
	}{
		{"?limit=999999", adminListMaxLimit},
		{"?limit=0", adminListDefaultLimit},
		{"?limit=abc", adminListDefaultLimit},
		{"", adminListDefaultLimit},
		{"?limit=25", 25},
	} {
		rec := requestAdmin(t, ctx, adminEndpoints, http.MethodGet, "/api/admin/users"+tc.query, adminID, adminEndpoints.ListUsers)
		var body struct {
			Limit int32 `json:"limit"`
		}
		decodeBody(t, rec, &body)
		if body.Limit != tc.want {
			t.Errorf("users%s -> limit %d, want %d", tc.query, body.Limit, tc.want)
		}
	}
}

// ─────────────────────────── vip ───────────────────────────

// §7 deleted this endpoint once and said adding it back needed a conversation. it is back because
// the founder asked for it, so what is worth pinning is the part that was never in question: a date
// grants, and the *absence* of one revokes, through the same statement.
func TestVIPIsGrantedAndRevokedThroughOneEndpoint(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "VipBoss", "admin")
	shopID := makeSeededShop(t, ctx, tx, q, "Paying", catalog.CategoryWood, false)

	grant := requestAdminBody(t, ctx, adminEndpoints, http.MethodPut,
		"/api/admin/shops/"+strconv.FormatInt(shopID, 10)+"/vip", adminID,
		`{"days":90}`, adminEndpoints.SetVIP)
	if grant.Code != http.StatusOK {
		t.Fatalf("grant = %d (%s)", grant.Code, grant.Body.String())
	}
	var granted struct {
		IsVIP    bool   `json:"is_vip"`
		VipUntil string `json:"vip_until"`
	}
	decodeBody(t, grant, &granted)
	if !granted.IsVIP || granted.VipUntil == "" {
		t.Errorf("after a 90 day grant: is_vip=%v until=%q", granted.IsVIP, granted.VipUntil)
	}

	revoke := requestAdminBody(t, ctx, adminEndpoints, http.MethodPut,
		"/api/admin/shops/"+strconv.FormatInt(shopID, 10)+"/vip", adminID,
		`{"days":0}`, adminEndpoints.SetVIP)
	var revoked struct {
		IsVIP bool `json:"is_vip"`
	}
	decodeBody(t, revoke, &revoked)
	if revoked.IsVIP {
		t.Error("days:0 left the placement in place - revoking has to go through the same call")
	}

	// a slipped keypress should not sell somebody a placement until the next century
	tooLong := requestAdminBody(t, ctx, adminEndpoints, http.MethodPut,
		"/api/admin/shops/"+strconv.FormatInt(shopID, 10)+"/vip", adminID,
		`{"days":99999}`, adminEndpoints.SetVIP)
	if tooLong.Code != http.StatusBadRequest {
		t.Errorf("days:99999 = %d, want 400", tooLong.Code)
	}
}

// ─────────────────────────── editing ───────────────────────────

// the invariant §7 states, as a test: no path reachable over the network may grant `admin`. this
// endpoint is behind RequireAdmin, so only an administrator could ever call it - it stays closed
// anyway, because "there is no code path" survives a stolen token and a mistake in the middleware
// wiring, where "an attacker cannot reach it" does not.
func TestAdminRoleCannotBeAssignedOverTheAPI(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "EditBoss", "admin")
	targetID := makeUser(t, ctx, q, "Hopeful", "customer")

	rec := requestAdminBody(t, ctx, adminEndpoints, http.MethodPut,
		"/api/admin/users/"+strconv.FormatInt(targetID, 10), adminID,
		`{"name":"Hopeful","role":"admin"}`, adminEndpoints.UpdateUser)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("assigning admin = %d, want 400", rec.Code)
	}

	var role string
	if err := tx.QueryRow(ctx, "SELECT role FROM users WHERE id = $1", targetID).Scan(&role); err != nil {
		t.Fatalf("read role: %v", err)
	}
	if role != "customer" {
		t.Errorf("role is now %q - the api granted admin", role)
	}

	// and the mirror: an existing admin cannot be demoted here either, or the panel would have a
	// one-click path to locking every administrator out of itself
	demote := requestAdminBody(t, ctx, adminEndpoints, http.MethodPut,
		"/api/admin/users/"+strconv.FormatInt(adminID, 10), adminID,
		`{"name":"EditBoss","role":"customer"}`, adminEndpoints.UpdateUser)
	if demote.Code != http.StatusForbidden {
		t.Errorf("demoting an admin = %d, want 403", demote.Code)
	}
}

// ─────────────────────────── anomalies ───────────────────────────

// the report exists because §6 accepts a mean for the index and says bad data gets caught
// operationally instead. what it must not do is flag an honest market: three shops agreeing on a
// price and one that does not is exactly one anomaly, not four.
func TestAnomaliesFlagThePriceThatDisagreesWithTheMedian(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "AnomBoss", "admin")
	var shops []int64
	for _, name := range []string{"AnomA", "AnomB", "AnomC"} {
		id := makeSeededShop(t, ctx, tx, q, name, catalog.CategoryWallpaper, false)
		priceAll(t, ctx, tx, id, 100_000)
		shops = append(shops, id)
	}

	// one shop types an extra zero on one line
	var typoProductID int64
	if err := tx.QueryRow(ctx,
		`UPDATE products SET price = 1000000
		   WHERE id = (SELECT id FROM products WHERE shop_id = $1 AND template_key IS NOT NULL ORDER BY id LIMIT 1)
		 RETURNING id`, shops[0]).Scan(&typoProductID); err != nil {
		t.Fatalf("introduce the typo: %v", err)
	}

	rec := requestAdmin(t, ctx, adminEndpoints, http.MethodGet, "/api/admin/anomalies", adminID, adminEndpoints.Anomalies)
	if rec.Code != http.StatusOK {
		t.Fatalf("anomalies = %d (%s)", rec.Code, rec.Body.String())
	}

	var body struct {
		Anomalies []adminAnomaly `json:"anomalies"`
	}
	decodeBody(t, rec, &body)

	if len(body.Anomalies) != 1 {
		t.Fatalf("got %d anomalies, want exactly 1 - the other rows all agree", len(body.Anomalies))
	}
	found := body.Anomalies[0]
	if found.ProductID != typoProductID {
		t.Errorf("flagged product %d, want %d", found.ProductID, typoProductID)
	}
	// the median of {1000000, 100000, 100000} is 100000, which is the point of using it: a mean
	// would be 400000 and would make the typo look like a 150% deviation instead of a 900% one
	if found.MedianPrice != 100_000 {
		t.Errorf("median = %d, want 100000 - the baseline was dragged by the outlier it is hunting", found.MedianPrice)
	}
	if found.DeviationPercent != 900 {
		t.Errorf("deviation = %d%%, want 900%%", found.DeviationPercent)
	}
}

// below the minimum, "the market" is one or two shops and every disagreement looks like an anomaly.
func TestAnomaliesIgnoreALineTooFewShopsHavePriced(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "ThinBoss", "admin")
	a := makeSeededShop(t, ctx, tx, q, "ThinA", catalog.CategoryWallpaper, false)
	b := makeSeededShop(t, ctx, tx, q, "ThinB", catalog.CategoryWallpaper, false)
	priceAll(t, ctx, tx, a, 100_000)
	priceAll(t, ctx, tx, b, 5_000_000)

	rec := requestAdmin(t, ctx, adminEndpoints, http.MethodGet, "/api/admin/anomalies", adminID, adminEndpoints.Anomalies)
	var body struct {
		Anomalies []adminAnomaly `json:"anomalies"`
	}
	decodeBody(t, rec, &body)

	if len(body.Anomalies) != 0 {
		t.Errorf("got %d anomalies from a two-shop market, want 0", len(body.Anomalies))
	}
}

// like requestAdmin but with a json body, for the PUT routes.
func requestAdminBody(t *testing.T, ctx context.Context, a *Admin, method, target string, asUserID int64, body string, handler http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "+998900000000", testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	req := httptest.NewRequestWithContext(ctx, method, target, strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	// the mux is not in play here, so the {id} wildcard has to be set the way it would have set it.
	// "/api/admin/shops/12/vip" ends in a word, so the id is the segment before it.
	if id := adminTestPathID(target); id != "" {
		req.SetPathValue("id", id)
	}

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, a.Queries, a.RequireAdmin(handler))(rec, req)
	return rec
}

// pulls the numeric segment out of a path, wherever it sits: ".../users/42" and ".../shops/42/vip"
// both yield "42".
func adminTestPathID(target string) string {
	for _, seg := range strings.Split(strings.SplitN(target, "?", 2)[0], "/") {
		if _, err := strconv.ParseInt(seg, 10, 64); err == nil && seg != "" {
			return seg
		}
	}
	return ""
}

// ─────────────────────────── template sync ───────────────────────────

// the sync is tested at the query level rather than through SyncTemplate, because the handler opens
// its own transaction off a *pgxpool.Pool and these tests run inside one already. that is not a gap:
// the handler is three calls and a commit, and every rule worth breaking lives in the SQL.

func syncPayload(t *testing.T, items []catalog.Item) ([]byte, []string) {
	t.Helper()

	keys := make([]string, 0, len(items))
	rows := make([]adminTemplateSyncRow, 0, len(items))
	for _, item := range items {
		keys = append(keys, item.Key)
		rows = append(rows, adminTemplateSyncRow{
			TemplateKey: item.Key, Name: item.Name, Category: string(item.Category),
			Unit: item.Unit, ImagePath: item.ImagePath,
		})
	}
	payload, err := json.Marshal(rows)
	if err != nil {
		t.Fatalf("encode template: %v", err)
	}
	return payload, keys
}

// **the property the whole feature stands on.** a sync that reset prices would destroy hundreds of
// hand-typed numbers with no undo, and it would do it silently - the rows would still be there.
func TestSyncRestoresMissingRowsAndKeepsEveryPrice(t *testing.T) {
	adminEndpoints, ctx, tx, q := adminUnderTest(t)
	_ = adminEndpoints

	shopID := makeSeededShop(t, ctx, tx, q, "Drifted", catalog.CategoryWood, false)
	priceAll(t, ctx, tx, shopID, 55_000)

	items := catalog.Template(string(catalog.CategoryWood))
	payload, keys := syncPayload(t, items)

	// a shop created before three products were added to the template
	dropped := []string{items[0].Key, items[1].Key, items[2].Key}
	if _, err := tx.Exec(ctx,
		"DELETE FROM products WHERE shop_id = $1 AND template_key = ANY($2::text[])", shopID, dropped); err != nil {
		t.Fatalf("drop rows: %v", err)
	}
	// and a row whose wording drifted, holding a price
	if _, err := tx.Exec(ctx,
		"UPDATE products SET name = 'ИСПОРЧЕНО', unit = 'кг' WHERE shop_id = $1 AND template_key = $2",
		shopID, items[3].Key); err != nil {
		t.Fatalf("mangle a row: %v", err)
	}

	inserted, err := q.AdminSyncTemplateInsert(ctx, db.AdminSyncTemplateInsertParams{
		Category: string(catalog.CategoryWood), Column2: payload,
	})
	if err != nil {
		t.Fatalf("sync insert: %v", err)
	}
	updated, err := q.AdminSyncTemplateUpdate(ctx, db.AdminSyncTemplateUpdateParams{
		Category: string(catalog.CategoryWood), Column2: payload, Column3: true,
	})
	if err != nil {
		t.Fatalf("sync update: %v", err)
	}
	if _, err := q.AdminSyncTemplateDelete(ctx, db.AdminSyncTemplateDeleteParams{
		Category: string(catalog.CategoryWood), Column2: keys,
	}); err != nil {
		t.Fatalf("sync delete: %v", err)
	}

	if inserted != int64(len(dropped)) {
		t.Errorf("inserted %d rows, want %d", inserted, len(dropped))
	}
	if updated != 1 {
		t.Errorf("updated %d rows, want 1 - only the mangled one differs from the template", updated)
	}

	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM products WHERE shop_id = $1 AND template_key IS NOT NULL", shopID); n != int64(len(items)) {
		t.Errorf("shop holds %d template rows, want %d", n, len(items))
	}

	// the wording is fixed and the price is untouched
	var name, unit string
	var price *int64
	if err := tx.QueryRow(ctx,
		"SELECT name, unit, price FROM products WHERE shop_id = $1 AND template_key = $2",
		shopID, items[3].Key).Scan(&name, &unit, &price); err != nil {
		t.Fatalf("read the repaired row: %v", err)
	}
	if name != items[3].Name || unit != items[3].Unit {
		t.Errorf("row not repaired: name=%q unit=%q", name, unit)
	}
	if price == nil || *price != 55_000 {
		t.Fatalf("the sync destroyed a price: %v", price)
	}

	// the three restored rows come back unpriced, which is the truth - nobody has typed one - and is
	// also why adding a product to a template drops every shop out of the comparison until they do
	if n := countRows(t, ctx, tx,
		"SELECT COUNT(*) FROM products WHERE shop_id = $1 AND template_key = ANY($2::text[]) AND price IS NULL",
		shopID, dropped); n != int64(len(dropped)) {
		t.Errorf("%d of the restored rows are unpriced, want %d", n, len(dropped))
	}
}

func TestSyncRemovesRowsTheTemplateNoLongerHas(t *testing.T) {
	_, ctx, tx, q := adminUnderTest(t)

	shopID := makeSeededShop(t, ctx, tx, q, "Stale", catalog.CategoryWood, false)
	items := catalog.Template(string(catalog.CategoryWood))
	_, keys := syncPayload(t, items)

	// a row from a template revision that no longer exists, plus one of the owner's own products
	if _, err := tx.Exec(ctx,
		`INSERT INTO products (shop_id, name, category, unit, template_key, price)
		 VALUES ($1, 'Снятый с шаблона', 'lumber', 'шт', 'wood.retired', 999)`, shopID); err != nil {
		t.Fatalf("insert stale row: %v", err)
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO products (shop_id, name, category, unit, price) VALUES ($1, 'Свой товар', 'lumber', 'шт', 12345)`,
		shopID); err != nil {
		t.Fatalf("insert own product: %v", err)
	}

	deleted, err := q.AdminSyncTemplateDelete(ctx, db.AdminSyncTemplateDeleteParams{
		Category: string(catalog.CategoryWood), Column2: keys,
	})
	if err != nil {
		t.Fatalf("sync delete: %v", err)
	}
	if deleted != 1 {
		t.Errorf("deleted %d rows, want 1", deleted)
	}

	// the owner's own product is not the template's to manage, and must survive
	if n := countRows(t, ctx, tx,
		"SELECT COUNT(*) FROM products WHERE shop_id = $1 AND template_key IS NULL", shopID); n != 1 {
		t.Errorf("the sync deleted the owner's own product")
	}
}

// an обои row's name is the owner's real wallpaper; the template's is a placeholder saying what
// belongs in the slot. syncing names into that category would replace every обои shop's catalogue
// with ten copies of "Обои премиум (Россия)".
func TestSyncLeavesOwnerNamedSlotsAlone(t *testing.T) {
	_, ctx, tx, q := adminUnderTest(t)

	shopID := makeSeededShop(t, ctx, tx, q, "Slots", catalog.CategoryWallpaper, false)
	items := catalog.Template(string(catalog.CategoryWallpaper))
	payload, _ := syncPayload(t, items)

	const ownersName = "Palitra Deluxe 1204-3"
	if _, err := tx.Exec(ctx,
		"UPDATE products SET name = $3 WHERE shop_id = $1 AND template_key = $2",
		shopID, items[0].Key, ownersName); err != nil {
		t.Fatalf("name the slot: %v", err)
	}

	// false is what the handler passes for an owner-named category, off catalog.IsOwnerNamedCategory
	if !catalog.IsOwnerNamedCategory(string(catalog.CategoryWallpaper)) {
		t.Fatal("wallpaper is no longer owner-named - this test is checking the wrong thing")
	}
	if _, err := q.AdminSyncTemplateUpdate(ctx, db.AdminSyncTemplateUpdateParams{
		Category: string(catalog.CategoryWallpaper), Column2: payload, Column3: false,
	}); err != nil {
		t.Fatalf("sync update: %v", err)
	}

	var name string
	if err := tx.QueryRow(ctx, "SELECT name FROM products WHERE shop_id = $1 AND template_key = $2",
		shopID, items[0].Key).Scan(&name); err != nil {
		t.Fatalf("read slot: %v", err)
	}
	if name != ownersName {
		t.Errorf("slot name is now %q - the sync overwrote the owner's own product", name)
	}
}
