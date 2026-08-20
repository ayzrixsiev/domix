package endpoints

// the json contract behind the home screen, checked at the http boundary rather than at the query
// boundary (db/home_queries_test.go does that part).
//
// what these are really guarding is the *shape*: field names, and which of them may be null. the
// flutter side decodes this by hand, so a renamed key or a `null` where a list was expected is a
// runtime crash in the app with nothing on the server to show for it - and that is precisely the
// class of bug that only appears once there is no data, which is the state the database is in right
// now.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/joho/godotenv"

	"domix/backend/db"
	"domix/backend/internal/catalog"
)

func homeUnderTest(t *testing.T) (*Home, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	if os.Getenv("DB_URL") == "" {
		_ = godotenv.Load(filepath.Join("..", "..", "..", ".env"))
	}
	dbURL := os.Getenv("DB_URL")
	if dbURL == "" {
		t.Skip("DB_URL is not set - skipping the tests that need a real database")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	t.Cleanup(cancel)

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		t.Skipf("cannot reach the database (%v) - skipping", err)
	}
	t.Cleanup(func() { _ = conn.Close(context.Background()) })

	tx, err := conn.Begin(ctx)
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	t.Cleanup(func() { _ = tx.Rollback(context.Background()) })

	q := db.New(tx)
	loadTemplates(t, ctx, q)
	return &Home{Queries: q}, ctx, tx, q
}

// the handler reads its deadline off the *request* context, so the request has to carry the
// transaction-bound one or dbctx.WithTimeout would branch off context.Background() and the query
// would run on a connection the transaction doesn't own.
func getJSON(t *testing.T, ctx context.Context, handler http.HandlerFunc, target string, into any) *httptest.ResponseRecorder {
	t.Helper()

	req := httptest.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	rec := httptest.NewRecorder()
	handler(rec, req)

	if into != nil && rec.Code == http.StatusOK {
		if err := json.Unmarshal(rec.Body.Bytes(), into); err != nil {
			t.Fatalf("decoding %s: %v\nbody: %s", target, err, rec.Body.String())
		}
	}
	return rec
}

// the state the app is actually in today: a database with no shops in it. every list has to come
// back as `[]` and not `null`, or `jsonDecode(body) as List` throws on the very first launch.
func TestHomeWithNoShopsReturnsEmptyListsNotNulls(t *testing.T) {
	home, ctx, tx, _ := homeUnderTest(t)

	// there are no shops in the founder's local database, but a test must not depend on that
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops inside the transaction: %v", err)
	}

	// decoded into a raw map first, so this checks the json literally rather than checking what
	// Go's decoder was willing to coerce - `null` unmarshals into a nil []ShopResponse without
	// complaint, which is exactly the failure being tested for
	var raw map[string]json.RawMessage
	rec := getJSON(t, ctx, home.Get, "/api/home", &raw)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	for _, key := range []string{"vip_shops", "best_offers"} {
		value, ok := raw[key]
		if !ok {
			t.Fatalf("response has no %q key: %s", key, rec.Body.String())
		}
		if string(value) == "null" {
			t.Fatalf("%q came back as null - the app decodes it as a list and would throw", key)
		}
	}

	var payload HomeResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(payload.VipShops) != 0 || len(payload.BestOffers) != 0 {
		t.Fatalf("no shops exist, so both shop sections must be empty")
	}

	// the twelve category tiles are not in this payload at all - they are a fixed list the app
	// already holds, so there is nothing to fetch and nothing that can arrive wrong
	if _, present := raw["categories"]; present {
		t.Fatal("categories should not be serialized - the app owns that list")
	}
}

func TestHomeSerializesAbsentIndexAsNull(t *testing.T) {
	// this one exercises Shops.List rather than the home endpoint - the map is where an unpriced
	// shop still has to appear - so the Home handler the fixture builds goes unused here
	_, ctx, tx, q := homeUnderTest(t)

	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	// a shop with nothing priced. it appears on the map (ListShops is a LEFT JOIN) but has no
	// basket index, and the app must see null rather than 0 - an index of 0 would read as "free"
	// printed on a map pin.
	shops := &Shops{Queries: q}
	makeSeededShop(t, ctx, tx, q, "Unpriced", catalog.CategoryUniversal, false)

	var raw []map[string]json.RawMessage
	rec := getJSON(t, ctx, shops.List, "/api/shops", &raw)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if len(raw) != 1 {
		t.Fatalf("want 1 shop, got %d", len(raw))
	}
	for _, key := range []string{"basket_price", "price_tier", "price_difference_percent"} {
		if got := string(raw[0][key]); got != "null" {
			t.Fatalf("an unpriced shop must serialize %s as null, got %s", key, got)
		}
	}
	// the raw index is not on the wire at all - it is used for ranking and for choosing the tier,
	// both server-side, and "96" is not something a customer should be asked to interpret
	if _, present := raw[0]["price_index"]; present {
		t.Fatal("price_index must not be serialized - the app renders a tier, never the number")
	}
	if got := string(raw[0]["is_vip"]); got != "false" {
		t.Fatalf("want is_vip false, got %s", got)
	}
}

func TestHomeRanksAndCountsRealData(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)

	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	// three universal shops, so the market clears internal/pricing.MinMarketSize and badges publish.
	// per-item prices of 80/100/120 thousand average out to 100 thousand whatever the template's
	// size, so the three indices are 80/100/120 - see the comment on the worked-example test in
	// db/home_queries_test.go for why the index is size-independent and the basket is not.
	cheap := makeSeededShop(t, ctx, tx, q, "Cheap", catalog.CategoryUniversal, false)
	middling := makeSeededShop(t, ctx, tx, q, "Middling", catalog.CategoryUniversal, false)
	pricey := makeSeededShop(t, ctx, tx, q, "Pricey", catalog.CategoryUniversal, true)

	priceAll(t, ctx, tx, cheap, 80_000)
	priceAll(t, ctx, tx, middling, 100_000)
	priceAll(t, ctx, tx, pricey, 120_000)

	var payload HomeResponse
	rec := getJSON(t, ctx, home.Get, "/api/home", &payload)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	if len(payload.VipShops) != 1 || payload.VipShops[0].ID != pricey {
		t.Fatalf("want only the vip shop in the carousel, got %+v", payload.VipShops)
	}
	if !payload.VipShops[0].IsVIP {
		t.Fatal("a shop in the vip carousel should report is_vip true")
	}

	// one tab, because only one shop category has anything in it
	if len(payload.BestOffers) != 1 || payload.BestOffers[0].Category != string(catalog.CategoryUniversal) {
		t.Fatalf("want a single универсальный tab, got %+v", payload.BestOffers)
	}
	offers := payload.BestOffers[0].Shops
	if len(offers) != 3 || offers[0].ID != cheap {
		t.Fatalf("best offers should lead with the cheapest shop, got %+v", offers)
	}

	// the badge, not the number
	if offers[0].PriceTier == nil || *offers[0].PriceTier != "cheaper" {
		t.Fatalf("an index of 80 should read as cheaper, got %v", offers[0].PriceTier)
	}
	if offers[0].PriceDifferencePercent == nil || *offers[0].PriceDifferencePercent != 20 {
		t.Fatalf("want 20%% below market, got %v", offers[0].PriceDifferencePercent)
	}
	if offers[1].PriceTier == nil || *offers[1].PriceTier != "average" {
		t.Fatalf("an index of exactly 100 should read as average, got %v", offers[1].PriceTier)
	}
	if offers[2].PriceTier == nil || *offers[2].PriceTier != "dearer" {
		t.Fatalf("an index of 120 should read as dearer, got %v", offers[2].PriceTier)
	}
	wantBasket := int64(len(catalog.Template(string(catalog.CategoryUniversal)))) * 80_000
	if offers[0].BasketPrice == nil || *offers[0].BasketPrice != wantBasket {
		t.Fatalf("want a basket of %d alongside the badge, got %v", wantBasket, offers[0].BasketPrice)
	}

}

// the wire half of the LEFT JOIN: a shop that has been granted a placement is in the carousel from
// the moment it is granted, carrying explicit nulls rather than being missing.
//
// this is the same shape TestHomeSerializesAbsentIndexAsNull checks for the map, and it is here as
// well because the two lists used to disagree - the map showed an unfinished shop and the carousel,
// which is the one somebody paid for, silently did not.
func TestAPaidPlacementIsInTheCarouselWithOrWithoutAPrice(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)

	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	unfinished := makeSeededShop(t, ctx, tx, q, "Unfinished", catalog.CategoryUniversal, true)

	var raw struct {
		VipShops []map[string]json.RawMessage `json:"vip_shops"`
	}
	if rec := getJSON(t, ctx, home.Get, "/api/home", &raw); rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	if len(raw.VipShops) != 1 {
		t.Fatalf("a granted placement must appear whatever its catalogue looks like, got %d cards",
			len(raw.VipShops))
	}
	if got := string(raw.VipShops[0]["id"]); got != strconv.FormatInt(unfinished, 10) {
		t.Fatalf("want shop %d in the carousel, got id %s", unfinished, got)
	}
	if got := string(raw.VipShops[0]["is_vip"]); got != "true" {
		t.Fatalf("a card in the carousel must report is_vip true, got %s", got)
	}
	// nulls, not zeroes: the app draws no price and no badge, which is the truth about a shop that
	// has not finished. a 0 would render as a free basket and "100% дешевле рынка".
	for _, key := range []string{"basket_price", "price_tier", "price_difference_percent"} {
		if got := string(raw.VipShops[0][key]); got != "null" {
			t.Fatalf("an unpriced VIP shop must serialize %s as null, got %s", key, got)
		}
	}
	// and the raw index stays server-side here too (§5)
	if _, present := raw.VipShops[0]["price_index"]; present {
		t.Fatal("price_index must not be serialized - the app renders a tier, never the number")
	}

	// it is *not* in Лучшие предложения, which is a price ranking and has nothing to rank it on
	var payload HomeResponse
	getJSON(t, ctx, home.Get, "/api/home", &payload)
	for _, group := range payload.BestOffers {
		for _, shop := range group.Shops {
			if shop.ID == unfinished {
				t.Fatal("a shop with no basket was ranked in Лучшие предложения")
			}
		}
	}
}

// four tabs, in the canonical order, and only for categories that have shops.
func TestHomeGroupsBestOffersByShopCategory(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)

	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	universal := makeSeededShop(t, ctx, tx, q, "Uni", catalog.CategoryUniversal, false)
	wallpaper := makeSeededShop(t, ctx, tx, q, "Paper", catalog.CategoryWallpaper, false)
	priceAll(t, ctx, tx, universal, 100_000)
	priceAll(t, ctx, tx, wallpaper, 300_000)

	var payload HomeResponse
	if rec := getJSON(t, ctx, home.Get, "/api/home", &payload); rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// universal before wallpaper - catalog.AllShopCategories order, not whatever postgres returned
	got := []string{}
	for _, group := range payload.BestOffers {
		got = append(got, group.Category)
	}
	want := []string{string(catalog.CategoryUniversal), string(catalog.CategoryWallpaper)}
	if len(got) != len(want) {
		t.Fatalf("want tabs %v, got %v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("want tabs %v in that order, got %v", want, got)
		}
	}

	// сантехника and дерево have no shops, so they are not tabs - an empty tab is a dead end
	for _, group := range payload.BestOffers {
		if len(group.Shops) == 0 {
			t.Fatalf("%q was sent as a tab with no shops in it", group.Category)
		}
	}
}

func TestProductsByCategoryRejectsAnUnknownCode(t *testing.T) {
	home, ctx, _, _ := homeUnderTest(t)

	req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/api/categories/not-a-category/products", nil)
	req.SetPathValue("code", "not-a-category")
	rec := httptest.NewRecorder()
	home.ProductsByCategory(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("an unknown category should be a 404, got %d: %s", rec.Code, rec.Body.String())
	}

	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if body["code"] != "unknown_category" {
		t.Fatalf("want the machine-readable code the app switches on, got %q", body["code"])
	}
}

func TestProductsByCategoryReturnsPricedProductsWithTheirShop(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)

	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}

	shop := makeSeededShop(t, ctx, tx, q, "Sliced", catalog.CategoryUniversal, false)

	// one of the twelve product categories, and how many rows of it the универсальный template
	// holds - counted off the template rather than written down, since /products.md is the founder's
	// to edit and the counts move whenever it does. the guard matters: if изоляция ever left the
	// list, `want` would be 0 and the assertion below would pass against an empty response.
	const browseCategory = "insulation"
	want := 0
	for _, item := range catalog.Template(string(catalog.CategoryUniversal)) {
		if string(item.Category) == browseCategory {
			want++
		}
	}
	if want == 0 {
		t.Fatalf("the универсальный template has no %q rows to browse - pick another category", browseCategory)
	}

	if _, err := tx.Exec(ctx,
		`UPDATE products SET price = 70000 WHERE shop_id = $1 AND category = $2`, shop, browseCategory); err != nil {
		t.Fatalf("price %s: %v", browseCategory, err)
	}

	req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/api/categories/"+browseCategory+"/products", nil)
	req.SetPathValue("code", browseCategory)
	rec := httptest.NewRecorder()
	home.ProductsByCategory(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var products []CategoryProductResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &products); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(products) != want {
		t.Fatalf("want the %d priced %s rows, got %d", want, browseCategory, len(products))
	}
	for _, product := range products {
		if product.Price == nil || *product.Price != 70_000 {
			t.Fatalf("want a priced row, got %v", product.Price)
		}
		if product.ShopName != "Sliced" {
			t.Fatalf("every row must name its shop, got %q", product.ShopName)
		}
		if product.Category != browseCategory {
			t.Fatalf("a %q row leaked in", product.Category)
		}
	}

	// the embedded ProductResponse is flattened, not nested - the app decodes this with the same
	// Product.fromJson it uses everywhere else, and a `{"ProductResponse": {...}}` shape would break it
	var raw []map[string]json.RawMessage
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatalf("decode raw: %v", err)
	}
	for _, key := range []string{"id", "shop_id", "name", "price", "unit", "shop_name"} {
		if _, present := raw[0][key]; !present {
			t.Fatalf("the product row has no %q key: %s", key, rec.Body.String())
		}
	}
}

// -- fixtures ------------------------------------------------------------------------------------

func makeSeededShop(t *testing.T, ctx context.Context, tx pgx.Tx, q *db.Queries, name string, category catalog.Category, vip bool) int64 {
	t.Helper()

	user, err := q.CreateUser(ctx, db.CreateUserParams{
		Name:  pgtype.Text{String: name, Valid: true},
		Phone: "+99890" + name,
		Role:  "shop_owner",
	})
	if err != nil {
		t.Fatalf("create user: %v", err)
	}

	shop, err := q.CreateShop(ctx, db.CreateShopParams{
		UserID:        user.ID,
		Name:          name,
		ContactPhone:  "+998901112233",
		Address:       "Tashkent",
		Category:      string(category),
		StMakepoint:   69.2401,
		StMakepoint_2: 41.2995,
	})
	if err != nil {
		t.Fatalf("create shop: %v", err)
	}

	for _, item := range catalog.Template(string(category)) {
		if err := q.SeedTemplateProduct(ctx, db.SeedTemplateProductParams{
			ShopID:      shop.ID,
			Name:        item.Name,
			Category:    string(item.Category),
			Unit:        item.Unit,
			TemplateKey: pgtype.Text{String: item.Key, Valid: true},
			ImagePath:   pgtype.Text{String: item.ImagePath, Valid: item.ImagePath != ""},
		}); err != nil {
			t.Fatalf("seed %q: %v", item.Key, err)
		}
	}

	if vip {
		if _, err := q.SetShopVIP(ctx, db.SetShopVIPParams{
			ID:       shop.ID,
			VipUntil: pgtype.Timestamptz{Time: time.Now().Add(30 * 24 * time.Hour), Valid: true},
		}); err != nil {
			t.Fatalf("grant vip: %v", err)
		}
	}

	return shop.ID
}

func priceAll(t *testing.T, ctx context.Context, tx pgx.Tx, shopID int64, price int64) {
	t.Helper()
	if _, err := tx.Exec(ctx,
		"UPDATE products SET price = $2 WHERE shop_id = $1 AND template_key IS NOT NULL", shopID, price); err != nil {
		t.Fatalf("price products: %v", err)
	}
}

// the templates live in `product_templates` since migration 000014 and are held in memory by
// internal/catalog, loaded once at startup by main.go. tests do not run main.go, so every harness
// that seeds a shop has to load them first - without it catalog.Template returns nothing and every
// shop is created with an empty catalogue, which fails as a wrong *count* three assertions later
// rather than as a missing setup step.
func loadTemplates(t *testing.T, ctx context.Context, q *db.Queries) {
	t.Helper()

	rows, err := q.ListProductTemplates(ctx)
	if err != nil {
		t.Fatalf("read product_templates: %v", err)
	}
	if len(rows) == 0 {
		t.Fatal("product_templates is empty - run `migrate -database \"$DB_URL\" -path db/migrations up`")
	}

	loaded := make([]catalog.Row, 0, len(rows))
	for _, row := range rows {
		loaded = append(loaded, catalog.Row{
			ShopCategory: row.ShopCategory, Key: row.TemplateKey, Name: row.Name,
			Category: row.Category, Unit: row.Unit, ImagePath: row.ImagePath.String,
		})
	}
	catalog.Load(loaded)
}
