package endpoints

// the two endpoints added for the store launch: deleting your own account, and searching products
// from the home screen.
//
// they share a file because they share nothing else - this is not a resource, it is the pair of
// things that had to exist before shop owners could be handed the app. what each one is guarding:
//
//   - deletion is a Google Play requirement, and the way it fails is *quietly incomplete*: a user
//     row that goes while its shops stay behind leaves pins on the map pointing at a business
//     nobody owns, and leaves the owner's phone number in `shops.contact_phone` after they asked to
//     be forgotten. the cascade is declared in the schema, so what these check is that it is
//     actually reached, not that ON DELETE CASCADE works.
//   - search is a pattern language pointed at user text, and the way *that* fails is by matching
//     more than the person typed. `%` is not a character to LIKE, it is an instruction.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"slices"
	"testing"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
)

func accountUnderTest(t *testing.T) (*Auth, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	_, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}
	return &Auth{Queries: q}, ctx, tx, q
}

// goes through the real auth.RequireAuth with a real signed token rather than calling DeleteMe
// directly, for the same reason the product tests do: the handler reads its user id out of a context
// the middleware puts it in, so calling it directly would test a code path the app never takes.
func requestMe(t *testing.T, ctx context.Context, a *Auth, method string, asUserID int64) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "+998900000000", testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	req := httptest.NewRequestWithContext(ctx, method, "/api/me", nil)
	req.Header.Set("Authorization", "Bearer "+token)

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, a.Queries, a.RouteMe)(rec, req)
	return rec
}

func countRows(t *testing.T, ctx context.Context, tx pgx.Tx, sql string, args ...any) int64 {
	t.Helper()

	var n int64
	if err := tx.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
		t.Fatalf("counting (%s): %v", sql, err)
	}
	return n
}

func shopOwner(t *testing.T, ctx context.Context, tx pgx.Tx, shopID int64) int64 {
	t.Helper()

	var ownerID int64
	if err := tx.QueryRow(ctx, "SELECT user_id FROM shops WHERE id = $1", shopID).Scan(&ownerID); err != nil {
		t.Fatalf("read shop owner: %v", err)
	}
	return ownerID
}

// the whole point of the endpoint: one call and nothing of theirs is left.
//
// Обои rather than Универсальный because ten seeded rows make the assertion readable, and the
// cascade does not care which template it is walking.
func TestDeletingAnAccountTakesItsShopsAndProductsWithIt(t *testing.T) {
	authEndpoints, ctx, tx, q := accountUnderTest(t)

	shopID := makeSeededShop(t, ctx, tx, q, "Deleter", catalog.CategoryWallpaper, false)
	ownerID := shopOwner(t, ctx, tx, shopID)

	// the state before, so a cascade that deletes nothing cannot pass by deleting nothing twice
	if got := countRows(t, ctx, tx, "SELECT COUNT(*) FROM products WHERE shop_id = $1", shopID); got == 0 {
		t.Fatal("the fixture seeded no products - the cascade assertion below would be vacuous")
	}

	rec := requestMe(t, ctx, authEndpoints, http.MethodDelete, ownerID)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	if got := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE id = $1", ownerID); got != 0 {
		t.Fatalf("the account is still there (%d rows)", got)
	}
	if got := countRows(t, ctx, tx, "SELECT COUNT(*) FROM shops WHERE id = $1", shopID); got != 0 {
		t.Fatalf("the shop outlived its owner (%d rows) - it is still a pin on the map", got)
	}
	if got := countRows(t, ctx, tx, "SELECT COUNT(*) FROM products WHERE shop_id = $1", shopID); got != 0 {
		t.Fatalf("%d products outlived the shop", got)
	}
}

// there is no revocation list, so the token this request arrived with is still a valid signature
// over a real user id. what stops it is RequireAuth reading the row on every request and finding it
// gone. this pins that the two halves line up - and specifically that the answer is the
// `account_deleted` code, which is the one the app wipes its storage on.
func TestTheTokenStopsWorkingTheRequestAfterDeletion(t *testing.T) {
	authEndpoints, ctx, tx, q := accountUnderTest(t)

	shopID := makeSeededShop(t, ctx, tx, q, "Ghost", catalog.CategoryWallpaper, false)
	ownerID := shopOwner(t, ctx, tx, shopID)

	if rec := requestMe(t, ctx, authEndpoints, http.MethodDelete, ownerID); rec.Code != http.StatusOK {
		t.Fatalf("delete: want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	rec := requestMe(t, ctx, authEndpoints, http.MethodGet, ownerID)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("the same token still works after deletion: got %d: %s", rec.Code, rec.Body.String())
	}

	var body struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v\nbody: %s", err, rec.Body.String())
	}
	if body.Code != "account_deleted" {
		t.Fatalf("want code account_deleted (the app clears its storage on that one), got %q", body.Code)
	}
}

// deleting is idempotent on purpose - see the DeleteUser query. checked at the query rather than at
// the http boundary because that is where the property lives: through RequireAuth a second attempt
// never reaches the handler at all, it is the 401 above. what this rules out is the version of
// DeleteUser that reports "0 rows affected" as an error, which would turn two devices pressing the
// same button into one of them staring at a failure about an account that is, as requested, gone.
func TestDeletingTwiceIsNotAnError(t *testing.T) {
	_, ctx, tx, q := accountUnderTest(t)

	shopID := makeSeededShop(t, ctx, tx, q, "Twice", catalog.CategoryWallpaper, false)
	ownerID := shopOwner(t, ctx, tx, shopID)

	for attempt := 1; attempt <= 2; attempt++ {
		if err := q.DeleteUser(ctx, ownerID); err != nil {
			t.Fatalf("attempt %d: %v", attempt, err)
		}
	}
}

// a shop with products whose names this file chooses, so the search assertions are about the
// matching rather than about whatever the template happens to contain.
func makeSearchableShop(t *testing.T, ctx context.Context, tx pgx.Tx, q *db.Queries, named map[string]*int64) int64 {
	t.Helper()

	shopID := makeSeededShop(t, ctx, tx, q, "Searchable", catalog.CategoryWallpaper, false)

	for name, price := range named {
		if _, err := tx.Exec(ctx,
			`INSERT INTO products (shop_id, name, category, unit, price, availability)
			 VALUES ($1, $2, 'mixes', 'шт', $3, 'in_stock')`,
			shopID, name, price); err != nil {
			t.Fatalf("insert %q: %v", name, err)
		}
	}
	return shopID
}

// url.QueryEscape, not raw interpolation: every query in this file is Cyrillic, and one of them is
// a literal `%`. Pasted straight into a url string, `%` starts a percent-escape and turns the rest
// of the query into a parse error rather than a search term.
func searchURL(query string) string {
	return "/api/products/search?q=" + url.QueryEscape(query)
}

func searchNames(t *testing.T, ctx context.Context, home *Home, query string) []string {
	t.Helper()

	var results []CategoryProductResponse
	rec := getJSON(t, ctx, home.SearchProducts, searchURL(query), &results)
	if rec.Code != http.StatusOK {
		t.Fatalf("search %q: want 200, got %d: %s", query, rec.Code, rec.Body.String())
	}

	names := make([]string, 0, len(results))
	for _, row := range results {
		names = append(names, row.Name)
	}
	return names
}

func containsName(names []string, want string) bool {
	return slices.Contains(names, want)
}

// the catalogue is typed in by hand, so "Цемент" and "цемент" are both going to be in there. a
// case-sensitive LIKE would find whichever one the customer happened to capitalise the same way.
func TestSearchIsCaseInsensitiveAndMatchesInsideAName(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	price := int64(50000)
	makeSearchableShop(t, ctx, tx, q, map[string]*int64{
		"Цемент М400, 50 кг": &price,
		"Клей для плитки":    &price,
	})

	// lowercase query against a capitalised name
	if names := searchNames(t, ctx, home, "цемент"); !containsName(names, "Цемент М400, 50 кг") {
		t.Fatalf("a lowercase query missed a capitalised product: %v", names)
	}

	// a word from the middle of the name, which is what the leading wildcard buys
	if names := searchNames(t, ctx, home, "плитки"); !containsName(names, "Клей для плитки") {
		t.Fatalf("a mid-name substring was not found: %v", names)
	}
}

// the same rule the category drill-down follows: a product with no price answers nothing in a
// cross-shop list. the seeded template rows are all unpriced here, so this also checks a fresh
// shop's hundred blanks stay out of everyone's search results.
func TestSearchExcludesUnpricedProducts(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	price := int64(9000)
	makeSearchableShop(t, ctx, tx, q, map[string]*int64{
		"Грунтовка приценённая": &price,
		"Грунтовка без цены":    nil,
	})

	names := searchNames(t, ctx, home, "Грунтовка")
	if !containsName(names, "Грунтовка приценённая") {
		t.Fatalf("the priced product is missing: %v", names)
	}
	if containsName(names, "Грунтовка без цены") {
		t.Fatalf("an unpriced product came back in a customer-facing search: %v", names)
	}
}

// `%` and `_` are instructions to LIKE, not characters. unescaped, a customer searching for "50%"
// gets the entire catalogue - which looks like a broken search, not like a security problem, which
// is exactly why it would survive review.
func TestSearchTreatsWildcardsAsLiteralText(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	price := int64(12000)
	makeSearchableShop(t, ctx, tx, q, map[string]*int64{
		"Спирт 50% раствор": &price,
		"Шпатель зубчатый":  &price,
	})

	names := searchNames(t, ctx, home, "50%")
	if !containsName(names, "Спирт 50% раствор") {
		t.Fatalf("the literal percent sign was not found: %v", names)
	}
	if containsName(names, "Шпатель зубчатый") {
		t.Fatalf("`%%` matched everything - it is being read as a wildcard: %v", names)
	}
}

func TestSearchRejectsAQueryTooShortToMeanAnything(t *testing.T) {
	home, ctx, tx, _ := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	// the empty string, whitespace that trims to nothing, and one letter
	for _, query := range []string{"", "   ", "ц"} {
		rec := getJSON(t, ctx, home.SearchProducts, searchURL(query), nil)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("query %q: want 400, got %d: %s", query, rec.Code, rec.Body.String())
		}
	}

	// one Cyrillic letter is two bytes, so a byte-length floor of 2 would let it through. this is
	// the case that makes RuneCountInString load-bearing rather than a style choice.
	rec := getJSON(t, ctx, home.SearchProducts, searchURL("це"), nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("two cyrillic letters must be an acceptable query, got %d: %s", rec.Code, rec.Body.String())
	}
}

// the same `null` vs `[]` trap the home endpoint has: the app decodes this with
// `jsonDecode(body) as List`, so a search that found nothing must still be a list.
func TestSearchWithNoMatchesReturnsAnEmptyListNotNull(t *testing.T) {
	home, ctx, tx, _ := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	rec := getJSON(t, ctx, home.SearchProducts, searchURL("нетакоготовара"), nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if body := rec.Body.String(); body != "[]\n" {
		t.Fatalf("want an empty json array, got %q", body)
	}
}

func TestEscapeLikePatternLeavesOrdinaryTextAlone(t *testing.T) {
	cases := map[string]string{
		"цемент":   "цемент",
		"50%":      `50\%`,
		"М_400":    `М\_400`,
		`c:\путь`:  `c:\\путь`,
		`100%_a\b`: `100\%\_a\\b`,
	}

	for input, want := range cases {
		if got := escapeLikePattern(input); got != want {
			t.Errorf("escapeLikePattern(%q) = %q, want %q", input, got, want)
		}
	}
}

// belt and braces on the numbers the endpoints hand the database: a limit that arrived as 0 would
// return nothing at all and read to the app as an empty catalogue.
func TestSearchAndCategoryLimitsAreNonZero(t *testing.T) {
	if searchResultsLimit <= 0 || categoryProductsLimit <= 0 {
		t.Fatalf("limits must be positive: search=%d category=%d", searchResultsLimit, categoryProductsLimit)
	}
	if minSearchQueryLen < 1 || maxSearchQueryLen <= minSearchQueryLen {
		t.Fatalf("query length bounds are inverted: min=%d max=%d", minSearchQueryLen, maxSearchQueryLen)
	}
}
