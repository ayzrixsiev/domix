package endpoints

// account deletion (a Google Play requirement) and product search. deletion has to take the shops and
// products with it; search has to find what the person meant and nothing more.

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
	"domix/backend/internal/imagestore"
)

func accountUnderTest(t *testing.T) (*Auth, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	_, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}
	return &Auth{Queries: q}, ctx, tx, q
}

// through the real RequireAuth with a real token: the handler reads its user id off the context the
// middleware fills, so calling it directly would test a path the app never takes.
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

// **The policy promises the photos go with the account**, and the cascade cannot keep that promise:
// it takes the rows, and the files live in a bucket no transaction reaches.
func TestDeletingAnAccountDeletesThePhotosItsOwnerUploaded(t *testing.T) {
	authEndpoints, ctx, tx, q := accountUnderTest(t)

	store, err := imagestore.NewDisk(t.TempDir())
	if err != nil {
		t.Fatalf("imagestore.NewDisk: %v", err)
	}
	authEndpoints.Images = store

	shopID := makeSeededShop(t, ctx, tx, q, "Photographer", catalog.CategoryWallpaper, false)
	ownerID := shopOwner(t, ctx, tx, shopID)

	uploaded, err := store.Save(ctx, imagestore.Photo{Master: []byte("master"), Thumb: []byte("thumb")})
	if err != nil {
		t.Fatalf("saving the owner's photo: %v", err)
	}
	if _, err := tx.Exec(ctx, `UPDATE products SET image_path = $2
		WHERE id = (SELECT id FROM products WHERE shop_id = $1 ORDER BY id LIMIT 1)`, shopID, uploaded); err != nil {
		t.Fatalf("pointing a product at the upload: %v", err)
	}

	rec := requestMe(t, ctx, authEndpoints, http.MethodDelete, ownerID)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	left, err := store.List(ctx, imagestore.UploadDir)
	if err != nil {
		t.Fatalf("listing the store: %v", err)
	}
	if len(left) != 0 {
		names := make([]string, 0, len(left))
		for _, obj := range left {
			names = append(names, obj.Path)
		}
		t.Fatalf("the account is gone but its photos are not: %v", names)
	}
}

// there is no revocation list: what stops a deleted user's token is RequireAuth reading the row on
// every request. the code has to be `account_deleted` - the one the app wipes its storage on.
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

// deleting twice is not an error: two devices pressing the same button must not leave one of them
// staring at a failure about an account that is, as requested, gone.
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

// a shop whose product names this file chooses, so the assertions are about matching rather than
// about whatever the template holds.
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

// QueryEscape, not interpolation: a literal `%` in a query would otherwise start a percent-escape.
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

// the catalogue is typed by hand, so both "Цемент" and "цемент" are in there.
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

// an unpriced row answers nothing in a cross-shop list, and a fresh shop has a hundred of them.
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

// what somebody types is text, not a pattern: unescaped, "50%" or ".*" would match the whole
// catalogue and read as a broken search rather than as a bug.
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

	// the empty string, whitespace that trims to nothing, one and two letters, and several words none
	// of which reaches three. two Cyrillic letters are four bytes, so a byte-length floor would have
	// let "це" through - the case that makes counting runes load-bearing rather than a style choice.
	for _, query := range []string{"", "   ", "ц", "це", "м 4 кг"} {
		rec := getJSON(t, ctx, home.SearchProducts, searchURL(query), nil)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("query %q: want 400, got %d: %s", query, rec.Code, rec.Body.String())
		}
	}

	// one word of three letters is enough, however short the others are
	for _, query := range []string{"цем", "цем 4"} {
		rec := getJSON(t, ctx, home.SearchProducts, searchURL(query), nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("query %q must be acceptable, got %d: %s", query, rec.Code, rec.Body.String())
		}
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

// almost nobody types ё, and 19 catalogue names are spelled with it. both directions have to work.
func TestSearchTreatsYoAsYe(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	price := int64(30000)
	makeSearchableShop(t, ctx, tx, q, map[string]*int64{
		"Шпатлёвка гипсовая": &price,
		"Пленка техническая": &price,
	})

	if names := searchNames(t, ctx, home, "шпатлевка"); !containsName(names, "Шпатлёвка гипсовая") {
		t.Fatalf("a query typed with е missed a name spelled with ё: %v", names)
	}
	if names := searchNames(t, ctx, home, "ПЛЁНКА"); !containsName(names, "Пленка техническая") {
		t.Fatalf("a query typed with Ё missed a name spelled with е: %v", names)
	}
}

// every word has to be in the name, in any order - people type "пвс кабель" as often as the reverse.
func TestSearchMatchesEveryWordInAnyOrder(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	price := int64(7000)
	makeSearchableShop(t, ctx, tx, q, map[string]*int64{
		"Кабель медный ПВС 2х1,5": &price,
		"Кабель алюминиевый":      &price,
	})

	names := searchNames(t, ctx, home, "пвс кабель")
	if !containsName(names, "Кабель медный ПВС 2х1,5") {
		t.Fatalf("the words in reverse order missed the product: %v", names)
	}
	if containsName(names, "Кабель алюминиевый") {
		t.Fatalf("a name missing one of the words matched anyway: %v", names)
	}
}

// sizes live in the description now, so a word from each half has to find the row together
func TestSearchReadsTheNameAndTheSpecsTogether(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	shopID := makeSearchableShop(t, ctx, tx, q, map[string]*int64{})
	for _, specs := range []string{"125 мм · 1ADP · EPA", "180 мм · 1ADP · EPA"} {
		if _, err := tx.Exec(ctx,
			`INSERT INTO products (shop_id, name, specs, category, unit, price, availability)
			 VALUES ($1, 'Алмазный диск', $2, 'tools', 'шт', 90000, 'in_stock')`,
			shopID, specs); err != nil {
			t.Fatalf("insert: %v", err)
		}
	}

	var results []CategoryProductResponse
	getJSON(t, ctx, home.SearchProducts, searchURL("диск 125"), &results)
	if len(results) != 1 || results[0].Specs != "125 мм · 1ADP · EPA" {
		t.Fatalf("want only the 125 mm disc, got %+v", results)
	}
}

// the cheapest row is no use if it cannot be bought, so «нет в наличии» goes last whatever its price.
func TestSearchPutsUnavailableProductsLast(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	cheap, dear := int64(1000), int64(9000)
	shopID := makeSearchableShop(t, ctx, tx, q, map[string]*int64{
		"Грунтовка дешёвая": &cheap,
		"Грунтовка дорогая": &dear,
	})
	if _, err := tx.Exec(ctx,
		`UPDATE products SET availability = 'unavailable' WHERE shop_id = $1 AND name = $2`,
		shopID, "Грунтовка дешёвая"); err != nil {
		t.Fatalf("marking a product unavailable: %v", err)
	}

	names := searchNames(t, ctx, home, "грунтовка")
	if want := []string{"Грунтовка дорогая", "Грунтовка дешёвая"}; !slices.Equal(names, want) {
		t.Fatalf("want %v, got %v", want, names)
	}
}

// the pure half of search: what the typed words become before they reach the database.
func TestSearchPatterns(t *testing.T) {
	anchor, patterns, ok := searchPatterns("  ПВС   Кабель  Чёрный ")
	if !ok {
		t.Fatal("a query with a six-letter word was refused")
	}
	// lowercased, ё written as е, longest word as the anchor
	if anchor != "кабель" {
		t.Fatalf("want the anchor кабель, got %q", anchor)
	}
	if want := []string{"пвс", "кабель", "черный"}; !slices.Equal(patterns, want) {
		t.Fatalf("want %v, got %v", want, patterns)
	}

	// a latin word carries its cyrillic spelling as an alternative
	if _, patterns, _ := searchPatterns("kabel"); !slices.Equal(patterns, []string{"(kabel|кабел)"}) {
		t.Fatalf("latin word: got %v", patterns)
	}

	// regex characters in what somebody typed stay characters
	if _, patterns, _ := searchPatterns("50%.*"); !slices.Equal(patterns, []string{`50%\.\*`}) {
		t.Fatalf("want the symbols escaped, got %v", patterns)
	}

	if _, _, ok := searchPatterns("м 4 кг"); ok {
		t.Fatal("a query with no word of three letters was accepted")
	}
}

// a customer typing latin finds the cyrillic catalogue: "kabel" comes from the letter rules,
// "sement" from the alias list (the rules alone would spell it "семент").
func TestSearchFindsAProductTypedInLatin(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	price := int64(20000)
	makeSearchableShop(t, ctx, tx, q, map[string]*int64{
		"Кабель медный ПВС 2х1,5": &price,
		"Цемент М400":             &price,
	})

	if names := searchNames(t, ctx, home, "kabel"); !containsName(names, "Кабель медный ПВС 2х1,5") {
		t.Fatalf("a latin query missed the cyrillic product: %v", names)
	}
	if names := searchNames(t, ctx, home, "sement"); !containsName(names, "Цемент М400") {
		t.Fatalf("the alias list did not reach цемент: %v", names)
	}
}
