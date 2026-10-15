package db_test

// the home screen's correctness is a *number* - "which shop is cheapest" is either right or silently
// wrong, and looking at the app tells you nothing. so these run against a real postgres with the real
// schema: a mock of the database would check what this test believes it computes.
//
// every test opens a transaction and rolls it back, so each sees only the rows it inserted, which is
// what lets them assert on exact list contents.

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/joho/godotenv"

	"domix/backend/db"
	"domix/backend/internal/catalog"
)

// t.Skip rather than t.Fatal when there is no database: `go test ./...` has to stay runnable on a
// machine that has never set one up, so a missing DB_URL means "not applicable here", not "broken".
func beginTx(t *testing.T) (context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	if os.Getenv("DB_URL") == "" {
		// the same ../.env the api itself loads, resolved from this package's directory
		_ = godotenv.Load(filepath.Join("..", "..", ".env"))
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
	// rolled back unconditionally: there is no commit anywhere in this file, so this is how every
	// row these tests write stops existing
	t.Cleanup(func() { _ = tx.Rollback(context.Background()) })

	// the index compares a shop against every other shop in its market, so it cannot be asserted on
	// without controlling the whole population: one shop left over on this laptop shifts every index
	// below, and the failure reads as arithmetic being wrong rather than data being present. the
	// transaction never commits, but it does hold row locks on shops while the test runs.
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clear shops for the duration of the transaction: %v", err)
	}

	q := db.New(tx)
	loadTemplates(t, ctx, q)
	return ctx, tx, q
}

// a shop owner plus a shop of the given category, seeded with that category's whole template -
// exactly what Shops.Create does, so the tests are looking at rows of the shape the app produces.
func makeShopTx(t *testing.T, ctx context.Context, conn pgx.Tx, q *db.Queries, name string, category catalog.Category, vip bool) int64 {
	t.Helper()

	// phone is the unique identity column, so it has to differ per shop the test creates
	user, err := q.CreateUser(ctx, db.CreateUserParams{
		Name:  pgtype.Text{String: name + " owner", Valid: true},
		Phone: "+998" + name,
		Role:  "shop_owner",
	})
	if err != nil {
		t.Fatalf("create user: %v", err)
	}

	shop, err := q.CreateShop(ctx, db.CreateShopParams{
		UserID:       user.ID,
		Name:         name,
		ContactPhone: "+998901234567",
		Address:      "Tashkent",
		Category:     string(category),
		// tashkent, and in (longitude, latitude) order - the reverse of how they are spoken
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
			// copied from the template exactly as Shops.Create does: a helper that hardcoded these
			// would stop testing the thing the app actually writes
			InBasket: item.InBasket,
			Specs:    item.Specs,
			Section:  item.Section,
		}); err != nil {
			t.Fatalf("seed %q: %v", item.Key, err)
		}
	}

	if vip {
		setVIP(t, ctx, q, shop.ID, time.Now().Add(30*24*time.Hour))
	}

	return shop.ID
}

// grants (or, with a past date, expires) a paid placement through the same query the admin endpoint
// uses - so these tests exercise the real statement rather than a hand-written UPDATE that could
// drift away from it.
func setVIP(t *testing.T, ctx context.Context, q *db.Queries, shopID int64, until time.Time) {
	t.Helper()

	if _, err := q.SetShopVIP(ctx, db.SetShopVIPParams{
		ID:       shopID,
		VipUntil: pgtype.Timestamptz{Time: until, Valid: true},
	}); err != nil {
		t.Fatalf("set vip on shop %d: %v", shopID, err)
	}
}

// prices the first n template products of a shop at the given price. returns nothing - the point is
// the side effect on shop_basket_index.
func priceProducts(t *testing.T, ctx context.Context, conn pgx.Tx, shopID int64, n int, price int64) {
	t.Helper()

	_, err := conn.Exec(ctx, `
		UPDATE products SET price = $3
		WHERE id IN (
			SELECT id FROM products
			WHERE shop_id = $1 AND template_key IS NOT NULL
			ORDER BY id LIMIT $2
		)`, shopID, n, price)
	if err != nil {
		t.Fatalf("price products: %v", err)
	}
}

// The point of products.in_basket: extending the catalogue must not cost every shop its badge, and
// voting the new row in must.
//
// **both halves fail in a way nobody would report.** without the in_basket filter in
// refresh_basket_index, adding a product makes every badge in the market quietly disappear; without
// in_basket in basket_index_after_product_update's watch list, a vote leaves the index answering about
// the old basket until some unrelated write moves it.
func TestAProductOutsideTheBasketDoesNotCostAnybodyTheirBadge(t *testing.T) {
	ctx, conn, q := beginTx(t)

	full := len(catalog.Template(string(catalog.CategoryUniversal)))

	first := makeShopTx(t, ctx, conn, q, "insider", catalog.CategoryUniversal, false)
	priceProducts(t, ctx, conn, first, full, 100_000)
	second := makeShopTx(t, ctx, conn, q, "outsider", catalog.CategoryUniversal, false)
	priceProducts(t, ctx, conn, second, full, 106_000)

	indexed := func(shopID int64, when string) bool {
		t.Helper()
		shops, err := q.ListShops(ctx)
		if err != nil {
			t.Fatalf("list shops %s: %v", when, err)
		}
		return findShop(t, shops, shopID).PriceIndex.Valid
	}

	if !indexed(first, "before the template grew") || !indexed(second, "before the template grew") {
		t.Fatalf("both shops priced their whole basket and should be in the comparison")
	}

	// the sync pushes a new product into both shops, outside the basket and unpriced
	for _, shop := range []int64{first, second} {
		if err := q.SeedTemplateProduct(ctx, db.SeedTemplateProductParams{
			ShopID:      shop,
			Name:        "новый товар",
			Category:    "tools",
			Unit:        "шт",
			TemplateKey: pgtype.Text{String: "universal.new_row", Valid: true},
			InBasket:    false,
		}); err != nil {
			t.Fatalf("seed the new row into shop %d: %v", shop, err)
		}
	}

	if !indexed(first, "after the template grew") || !indexed(second, "after the template grew") {
		t.Fatalf("a product outside the basket left unpriced has cost a shop its index")
	}

	// the founder votes it in while it is still unpriced - which is the mistake the coverage number in
	// the panel exists to prevent, and the comparison has to react to it immediately
	if _, err := conn.Exec(ctx,
		`UPDATE products SET in_basket = TRUE WHERE template_key = 'universal.new_row'`); err != nil {
		t.Fatalf("vote the row into the basket: %v", err)
	}

	if indexed(first, "after the row joined the basket") {
		t.Fatalf("an unpriced basket row must take the shop out of the comparison")
	}

	// and pricing it in both shops puts them back
	if _, err := conn.Exec(ctx,
		`UPDATE products SET price = 5000 WHERE template_key = 'universal.new_row'`); err != nil {
		t.Fatalf("price the new basket row: %v", err)
	}
	if !indexed(first, "after pricing the new basket row") || !indexed(second, "after pricing the new basket row") {
		t.Fatalf("every basket row is priced again and both shops should be back in the comparison")
	}
}

// the worked example, run against the real view: four shops at 100 / 106 / 98 / 96 thousand per item
// average to 100 thousand, so the indices are 100 / 106 / 98 / 96.
//
// **the indices are literals while the baskets are computed, and that asymmetry is the content of the
// example**: a basket is n items and moves when the template does, but the index divides one basket by
// the average of the others and n cancels. an index that changed when a product was added would mean
// the view is measuring the wrong thing.
// how many of a template's rows the basket is - **not its length**: a product voted out of the basket
// is still priced like any other and counts towards nobody's total.
func basketSize(category catalog.Category) int64 {
	var rows int64
	for _, item := range catalog.Template(string(category)) {
		if item.InBasket {
			rows++
		}
	}
	return rows
}

func TestBasketIndexReproducesTheWorkedExample(t *testing.T) {
	ctx, conn, q := beginTx(t)

	full := len(catalog.Template(string(catalog.CategoryUniversal)))

	cases := []struct {
		name      string
		unitPrice int64
		index     int64
	}{
		{"a", 100_000, 100},
		{"b", 106_000, 106},
		{"c", 98_000, 98},
		{"d", 96_000, 96},
	}

	ids := make(map[string]int64, len(cases))
	for _, c := range cases {
		id := makeShopTx(t, ctx, conn, q, c.name, catalog.CategoryUniversal, false)
		priceProducts(t, ctx, conn, id, full, c.unitPrice)
		ids[c.name] = id
	}

	shops, err := q.ListShops(ctx)
	if err != nil {
		t.Fatalf("list shops: %v", err)
	}

	for _, c := range cases {
		wantBasket := basketSize(catalog.CategoryUniversal) * c.unitPrice

		row := findShop(t, shops, ids[c.name])
		if !row.BasketPrice.Valid || row.BasketPrice.Int64 != wantBasket {
			t.Errorf("store %s: want basket %d, got %+v", c.name, wantBasket, row.BasketPrice)
		}
		if !row.PriceIndex.Valid || row.PriceIndex.Int64 != c.index {
			t.Errorf("store %s: want index %d, got %+v", c.name, c.index, row.PriceIndex)
		}
	}
}

// a shop with one unpriced product is out of the index *and* out of the market it would have been
// averaged into. the second half is the part worth pinning: the partial shop here is priced at a tenth
// of the market, so a half-empty basket leaking into the average would have the finished shop
// advertise "дороже рынка" against a market that is really one unfinished neighbour.
func TestBasketIndexExcludesShopsWithAnIncompleteBasket(t *testing.T) {
	ctx, conn, q := beginTx(t)

	full := len(catalog.Template(string(catalog.CategoryUniversal)))

	finished := makeShopTx(t, ctx, conn, q, "finished", catalog.CategoryUniversal, false)
	partial := makeShopTx(t, ctx, conn, q, "partial", catalog.CategoryUniversal, false)

	priceProducts(t, ctx, conn, finished, full, 100_000)
	// one short of the whole template, and dirt cheap - the most tempting row to let in
	priceProducts(t, ctx, conn, partial, full-1, 10_000)

	shops, err := q.ListShops(ctx)
	if err != nil {
		t.Fatalf("list shops: %v", err)
	}

	got := findShop(t, shops, partial)
	if got.BasketPrice.Valid || got.PriceIndex.Valid {
		t.Fatalf("%d of %d priced is an incomplete basket and must publish nothing, got basket %+v "+
			"index %+v", full-1, full, got.BasketPrice, got.PriceIndex)
	}

	// the finished shop is now the only member of its market, so it is its own average: exactly 100.
	// any other value means the excluded shop was still counted somewhere.
	finishedRow := findShop(t, shops, finished)
	if !finishedRow.PriceIndex.Valid || finishedRow.PriceIndex.Int64 != 100 {
		t.Fatalf("the only complete basket in the category is the market, so it should read 100, "+
			"got %+v - the incomplete shop is still in the average", finishedRow.PriceIndex)
	}
	if wantBasket := basketSize(catalog.CategoryUniversal) * 100_000; finishedRow.BasketPrice.Int64 != wantBasket {
		t.Errorf("want a basket of %d, got %d", wantBasket, finishedRow.BasketPrice.Int64)
	}
}

// the boundary is the last product, straddled from both sides: "all of them" sounds like a rule with no
// off-by-one in it, but the view expresses it as `COUNT(price) = COUNT(*)`, and a `>=` slipped in there
// would pass every test that prices a comfortable amount on each side of a line.
func TestBasketIndexNeedsEveryTemplateProductPriced(t *testing.T) {
	ctx, conn, q := beginTx(t)

	full := len(catalog.Template(string(catalog.CategoryUniversal)))

	// a second, fully priced shop so there is a market to be indexed against at all
	reference := makeShopTx(t, ctx, conn, q, "reference", catalog.CategoryUniversal, false)
	priceProducts(t, ctx, conn, reference, full, 100_000)

	shop := makeShopTx(t, ctx, conn, q, "under", catalog.CategoryUniversal, false)
	priceProducts(t, ctx, conn, shop, full-1, 100_000)

	shops, err := q.ListShops(ctx)
	if err != nil {
		t.Fatalf("list shops: %v", err)
	}
	if row := findShop(t, shops, shop); row.PriceIndex.Valid {
		t.Fatalf("%d of %d priced should publish no index, got %d", full-1, full, row.PriceIndex.Int64)
	}

	// the last one is what tips it over
	priceProducts(t, ctx, conn, shop, full, 100_000)

	shops, err = q.ListShops(ctx)
	if err != nil {
		t.Fatalf("list shops after pricing: %v", err)
	}
	if row := findShop(t, shops, shop); !row.PriceIndex.Valid {
		t.Fatalf("all %d priced is a complete basket and should publish an index", full)
	}
}

// the direction the other tests never travel: a shop that **is** in the comparison and stops being in
// it, because the template grew under it. This is what AdminSyncTemplateInsert does to every shop in a
// market the moment a row is added to a template.
//
// **It is here because of how the index is kept up to date.** The insert trigger deliberately does not
// recompute when an unpriced template row arrives at a shop with no index row - that is what stops
// Shops.Create's hundred seeding inserts recomputing the market a hundred times in one transaction. The
// guard is sound in that direction only, and a clause too wide would leave the old badge standing on
// the map: not missing, which somebody would notice, but *wrong*, which nobody would.
func TestAGrowingTemplateTakesAShopOutOfTheComparison(t *testing.T) {
	ctx, conn, q := beginTx(t)

	full := len(catalog.Template(string(catalog.CategoryUniversal)))

	// a second fully priced shop, so there is a market to be indexed against at all
	reference := makeShopTx(t, ctx, conn, q, "reference", catalog.CategoryUniversal, false)
	priceProducts(t, ctx, conn, reference, full, 100_000)

	shop := makeShopTx(t, ctx, conn, q, "grower", catalog.CategoryUniversal, false)
	priceProducts(t, ctx, conn, shop, full, 100_000)

	shops, err := q.ListShops(ctx)
	if err != nil {
		t.Fatalf("list shops: %v", err)
	}
	if row := findShop(t, shops, shop); !row.PriceIndex.Valid {
		t.Fatalf("a fully priced catalogue should publish an index before the template grows")
	}

	// the same statement the sync endpoint runs: one unpriced row into a shop that is currently ranked.
	//
	// **in_basket: true is what makes this the losing case** - a row added outside the basket is the
	// default and leaves every badge standing, which is the test below.
	if err := q.SeedTemplateProduct(ctx, db.SeedTemplateProductParams{
		ShopID:      shop,
		Name:        "новый товар",
		Category:    "tools",
		Unit:        "шт",
		TemplateKey: pgtype.Text{String: "universal.grown_row", Valid: true},
		InBasket:    true,
	}); err != nil {
		t.Fatalf("seed the new template row: %v", err)
	}

	shops, err = q.ListShops(ctx)
	if err != nil {
		t.Fatalf("list shops after the template grew: %v", err)
	}
	if row := findShop(t, shops, shop); row.PriceIndex.Valid {
		t.Fatalf("one unpriced row is an incomplete basket, but the index survived as %d", row.PriceIndex.Int64)
	}

	// and pricing it puts the shop back
	priceProducts(t, ctx, conn, shop, full+1, 100_000)

	shops, err = q.ListShops(ctx)
	if err != nil {
		t.Fatalf("list shops after pricing the new row: %v", err)
	}
	if row := findShop(t, shops, shop); !row.PriceIndex.Valid {
		t.Fatalf("the basket is complete again and should publish an index")
	}
}

// ─────────────────────────── the paid placements ───────────────────────────

// **the one that would cost real money if it broke**: ListVipShops LEFT JOINs the basket index, so a
// placement that has been paid for appears in the carousel whether or not its owner has priced every
// template row. an inner join hides it there while leaving it on the map, which is invisible.
func TestAPaidPlacementAppearsBeforeItsCatalogueIsPriced(t *testing.T) {
	ctx, conn, q := beginTx(t)

	full := len(catalog.Template(string(catalog.CategoryUniversal)))

	// bought a placement, has priced nothing at all
	blank := makeShopTx(t, ctx, conn, q, "blank", catalog.CategoryUniversal, true)
	// bought a placement, one row short of a complete basket - the state most shops are in early on
	nearly := makeShopTx(t, ctx, conn, q, "nearly", catalog.CategoryUniversal, true)
	priceProducts(t, ctx, conn, nearly, full-1, 100_000)
	// bought a placement and finished
	done := makeShopTx(t, ctx, conn, q, "done", catalog.CategoryUniversal, true)
	priceProducts(t, ctx, conn, done, full, 100_000)

	shops, err := q.ListVipShops(ctx, 5)
	if err != nil {
		t.Fatalf("list vip shops: %v", err)
	}

	got := vipIDs(shops)
	if len(got) != 3 {
		t.Fatalf("three shops hold a live placement, want all three in the carousel, got %v", got)
	}
	for _, id := range []int64{blank, nearly, done} {
		if !slices.Contains(got, id) {
			t.Errorf("shop %d paid for a placement and is missing from the carousel (%v)", id, got)
		}
	}

	// and the price columns tell the truth about each of them rather than being faked to fill a card
	for _, shop := range shops {
		switch shop.ID {
		case blank, nearly:
			if shop.BasketPrice.Valid || shop.PriceIndex.Valid {
				t.Errorf("shop %d has an incomplete basket and must publish no price, got %d",
					shop.ID, shop.BasketPrice.Int64)
			}
		case done:
			if !shop.BasketPrice.Valid {
				t.Errorf("shop %d priced its whole template and should carry a basket", shop.ID)
			}
		}
	}
}

// the centre of the carousel is the position being sold, so which row leads is a commercial decision
// rather than an ordering detail: the cheapest basket leads.
//
// **the unpriced placement is the half that costs money if it breaks.** ListVipShops left-joins the
// index, so a shop that has paid but not finished pricing has a null where its basket goes: it belongs
// at the back of a price ordering but still *in the list*, and a null sorting to the front would hand
// the slot sold on comparison to the one card that cannot make one.
func TestTheVipCarouselLeadsWithTheCheapestBasket(t *testing.T) {
	ctx, conn, q := beginTx(t)

	full := len(catalog.Template(string(catalog.CategoryUniversal)))

	// created most expensive first, so a query returning insertion order would fail here
	dear := makeShopTx(t, ctx, conn, q, "dear", catalog.CategoryUniversal, false)
	mid := makeShopTx(t, ctx, conn, q, "mid", catalog.CategoryUniversal, false)
	cheap := makeShopTx(t, ctx, conn, q, "cheap", catalog.CategoryUniversal, false)
	// bought a placement and has priced nothing: no row in the index at all, so basket_price is null
	unpriced := makeShopTx(t, ctx, conn, q, "unpriced", catalog.CategoryUniversal, false)

	priceProducts(t, ctx, conn, dear, full, 120_000)
	priceProducts(t, ctx, conn, mid, full, 100_000)
	priceProducts(t, ctx, conn, cheap, full, 80_000)

	// the longest run is deliberately the most expensive shop's, and the unpriced one outruns two of
	// the three priced ones: under the old `vip_until DESC` rule this list came back backwards.
	setVIP(t, ctx, q, dear, time.Now().Add(90*24*time.Hour))
	setVIP(t, ctx, q, unpriced, time.Now().Add(60*24*time.Hour))
	setVIP(t, ctx, q, cheap, time.Now().Add(14*24*time.Hour))
	setVIP(t, ctx, q, mid, time.Now().Add(7*24*time.Hour))

	shops, err := q.ListVipShops(ctx, 5)
	if err != nil {
		t.Fatalf("list vip shops: %v", err)
	}

	want := []int64{cheap, mid, dear, unpriced}
	if got := vipIDs(shops); !slices.Equal(got, want) {
		t.Fatalf("want [cheap mid dear unpriced] = %v, got %v - the cheapest basket takes the centre "+
			"and the placement with no basket sorts last", want, got)
	}
}

// the two rules that keep that ordering *total*: equal baskets fall back to the longer placement,
// and a placement whose date has passed is gone whatever it costs.
func TestTheVipCarouselTieBreaksOnTheLongerPlacement(t *testing.T) {
	ctx, conn, q := beginTx(t)

	full := len(catalog.Template(string(catalog.CategoryUniversal)))

	// created in the reverse of the order they should come back in, so a query that simply returned
	// insertion order would fail here
	short := makeShopTx(t, ctx, conn, q, "short", catalog.CategoryUniversal, false)
	long := makeShopTx(t, ctx, conn, q, "long", catalog.CategoryUniversal, false)
	lapsed := makeShopTx(t, ctx, conn, q, "lapsed", catalog.CategoryUniversal, false)
	priceProducts(t, ctx, conn, short, full, 100_000)
	priceProducts(t, ctx, conn, long, full, 100_000)
	priceProducts(t, ctx, conn, lapsed, full, 100_000)

	setVIP(t, ctx, q, short, time.Now().Add(7*24*time.Hour))
	setVIP(t, ctx, q, long, time.Now().Add(90*24*time.Hour))
	// yesterday: the placement is over, and it leaves the carousel on its own with nobody doing
	// anything - which is the whole reason vip_until is a date and not a boolean
	setVIP(t, ctx, q, lapsed, time.Now().Add(-24*time.Hour))

	shops, err := q.ListVipShops(ctx, 5)
	if err != nil {
		t.Fatalf("list vip shops: %v", err)
	}
	if got := vipIDs(shops); len(got) != 2 || got[0] != long || got[1] != short {
		t.Fatalf("want [long short] = %v, got %v - a lapsed placement must drop out, and with nothing "+
			"between two identical baskets the longer placement leads", []int64{long, short}, got)
	}
}

func TestBestOffersAreScopedToOneShopCategory(t *testing.T) {
	ctx, conn, q := beginTx(t)

	// two wallpaper shops: 10 x 50 000 = 500 000 and 10 x 100 000 = 1 000 000, averaging 750 000,
	// so their indices are 67 and 133
	cheapWallpaper := makeShopTx(t, ctx, conn, q, "cheapwall", catalog.CategoryWallpaper, false)
	dearWallpaper := makeShopTx(t, ctx, conn, q, "dearwall", catalog.CategoryWallpaper, false)
	priceProducts(t, ctx, conn, cheapWallpaper, len(catalog.Template(string(catalog.CategoryWallpaper))), 50_000)
	priceProducts(t, ctx, conn, dearWallpaper, len(catalog.Template(string(catalog.CategoryWallpaper))), 100_000)

	// the only universal shop, so it is its own market: 5 000 000 and an index of exactly 100
	universal := makeShopTx(t, ctx, conn, q, "universal", catalog.CategoryUniversal, false)
	priceProducts(t, ctx, conn, universal, len(catalog.Template(string(catalog.CategoryUniversal))), 100_000)

	wallpaper := bestOffersIn(t, ctx, q, catalog.CategoryWallpaper, 10)
	if len(wallpaper) != 2 {
		t.Fatalf("want the two wallpaper shops in the обои tab, got %d", len(wallpaper))
	}
	if wallpaper[0].ID != cheapWallpaper || wallpaper[1].ID != dearWallpaper {
		t.Fatalf("want cheapest first, got %v (indices %v)", offerIDs(wallpaper), offerIndices(wallpaper))
	}
	if wallpaper[0].PriceIndex != 67 || wallpaper[1].PriceIndex != 133 {
		t.Fatalf("want indices [67 133], got %v", offerIndices(wallpaper))
	}
	// the universal shop's 5 000 000 basket is by far the biggest number here, and it must not
	// appear in this tab at all
	for _, o := range wallpaper {
		if o.ID == universal {
			t.Fatal("a универсальный shop leaked into the обои tab")
		}
	}

	if universalTab := bestOffersIn(t, ctx, q, catalog.CategoryUniversal, 10); len(universalTab) != 1 ||
		universalTab[0].ID != universal {
		t.Fatalf("want only the universal shop in its own tab, got %v", offerIDs(universalTab))
	}

	// and a category nobody stocks produces no tab at all rather than an empty one
	if wood := bestOffersIn(t, ctx, q, catalog.CategoryWood, 10); len(wood) != 0 {
		t.Fatalf("nobody sells wood, want 0 rows, got %d", len(wood))
	}
}

func TestBestOffersExcludeShopsWithNoIndex(t *testing.T) {
	ctx, conn, q := beginTx(t)

	priced := makeShopTx(t, ctx, conn, q, "priced", catalog.CategoryUniversal, false)
	empty := makeShopTx(t, ctx, conn, q, "empty", catalog.CategoryUniversal, false)

	priceProducts(t, ctx, conn, priced, len(catalog.Template(string(catalog.CategoryUniversal))), 100_000)
	// `empty` gets nothing - it must not appear at all, rather than appearing first with a 0

	offers := bestOffersIn(t, ctx, q, catalog.CategoryUniversal, 10)
	if len(offers) != 1 || offers[0].ID != priced {
		t.Fatalf("want only the priced shop, got %v", offerIDs(offers))
	}
	for _, o := range offers {
		if o.ID == empty {
			t.Fatal("a shop with no priced products must not be ranked as a best offer")
		}
	}
}

// **the ordering is the entire meaning of this section**, so it gets its own test.
//
// what is pinned is that ordering by `price_index` and by `basket_price` are the *same* ordering inside
// one category: the index is basket ÷ that category's average basket, so the divisor is one positive
// constant. worth a test because the two look like independent choices, and somebody reading
// "ORDER BY price_index" with the raw sums in front of them will eventually be tempted to "fix" it.
func TestBestOffersRankByPriceWhicheverNumberYouUse(t *testing.T) {
	ctx, conn, q := beginTx(t)

	full := len(catalog.Template(string(catalog.CategoryUniversal)))

	// deliberately not in price order, and deliberately not in id order either
	makeAndPrice := func(name string, unit int64) int64 {
		id := makeShopTx(t, ctx, conn, q, name, catalog.CategoryUniversal, false)
		priceProducts(t, ctx, conn, id, full, unit)
		return id
	}
	middling := makeAndPrice("middling", 100_000)
	dear := makeAndPrice("dear", 130_000)
	cheap := makeAndPrice("cheap", 70_000)

	offers := bestOffersIn(t, ctx, q, catalog.CategoryUniversal, 15)
	if got := offerIDs(offers); len(got) != 3 || got[0] != cheap || got[1] != middling || got[2] != dear {
		t.Fatalf("want [cheap middling dear] = %v, got %v (indices %v)",
			[]int64{cheap, middling, dear}, got, offerIndices(offers))
	}

	// both numbers ascend together, which is the claim above
	for i := 1; i < len(offers); i++ {
		if offers[i].PriceIndex < offers[i-1].PriceIndex {
			t.Errorf("row %d has a lower index than the row above it: %v", i, offerIndices(offers))
		}
		if offers[i].BasketPrice < offers[i-1].BasketPrice {
			t.Errorf("row %d is cheaper than the row above it - ordering by the index has diverged "+
				"from ordering by the basket, which inside one category is impossible unless the "+
				"query changed markets mid-list", i)
		}
	}

	// and the limit is a limit, not a promise of fifteen rows
	if trimmed := bestOffersIn(t, ctx, q, catalog.CategoryUniversal, 2); len(trimmed) != 2 ||
		trimmed[0].ID != cheap || trimmed[1].ID != middling {
		t.Fatalf("a limit of 2 must keep the two cheapest, got %v", offerIDs(trimmed))
	}
}

// the "Популярные категории" drill-down: every priced product in one category, across every shop,
// cheapest first.
func TestProductsByCategoryListsEveryShopsPricedRows(t *testing.T) {
	ctx, conn, q := beginTx(t)

	dear := makeShopTx(t, ctx, conn, q, "dear", catalog.CategoryUniversal, false)
	cheap := makeShopTx(t, ctx, conn, q, "cheap", catalog.CategoryUniversal, false)

	if _, err := conn.Exec(ctx,
		`UPDATE products SET price = 90000 WHERE shop_id = $1 AND category = 'mixes'`, dear); err != nil {
		t.Fatalf("price dear mixes: %v", err)
	}
	if _, err := conn.Exec(ctx,
		`UPDATE products SET price = 40000 WHERE shop_id = $1 AND category = 'mixes'`, cheap); err != nil {
		t.Fatalf("price cheap mixes: %v", err)
	}
	// blocks stays unpriced everywhere, and must not leak into the mixes list either way

	rows, err := q.ListProductsByCategory(ctx, db.ListProductsByCategoryParams{
		Category:      "mixes",
		OffersPerLine: 4,
		ResultLimit:   100,
	})
	if err != nil {
		t.Fatalf("products by category: %v", err)
	}
	if len(rows) == 0 {
		t.Fatal("both shops price mixes, so the list cannot be empty")
	}

	// cheapest first, and every row names the shop selling it - a price with no seller attached is
	// not actionable
	if rows[0].Price.Int64 != 40_000 || rows[0].ShopName != "cheap" {
		t.Fatalf("want the cheapest shop's row first, got %q at %d", rows[0].ShopName, rows[0].Price.Int64)
	}
	if rows[len(rows)-1].Price.Int64 != 90_000 {
		t.Fatalf("want the dearest row last, got %d", rows[len(rows)-1].Price.Int64)
	}
	for _, row := range rows {
		if row.Category != "mixes" {
			t.Fatalf("a %q row leaked into the mixes list", row.Category)
		}
		if !row.Price.Valid {
			t.Fatal("an unpriced product reached a customer-facing list")
		}
		if row.ShopName == "" {
			t.Fatal("every row must name its shop")
		}
	}

	// a category nobody prices comes back empty rather than erroring
	none, err := q.ListProductsByCategory(ctx, db.ListProductsByCategoryParams{
		Category:      "tools",
		OffersPerLine: 4,
		ResultLimit:   100,
	})
	if err != nil {
		t.Fatalf("products by an unstocked category: %v", err)
	}
	if len(none) != 0 {
		t.Fatalf("nobody priced a tool, want 0 products, got %d", len(none))
	}
}

// **a popular category must not be one product repeated.** Every shop of a market prices the same
// curated rows, so ordering «Смеси» by price alone lists every shop's glue before its second
// product. The listing shows a few offers of one line and then moves on to the next line.
func TestACategoryShowsAFewOffersOfEachProductRatherThanOneProduct(t *testing.T) {
	ctx, conn, q := beginTx(t)

	const category = "mixes"
	const perLine = 4

	// six shops, so every line has more offers than the listing may show - and in no particular
	// order, since what must come back is the cheapest few, not the first few
	for _, shop := range []struct {
		name  string
		price int64
	}{
		{"middling", 60_000},
		{"dearest", 90_000},
		{"cheapest", 40_000},
		{"dear", 80_000},
		{"cheap", 50_000},
		{"fifth", 70_000},
	} {
		id := makeShopTx(t, ctx, conn, q, shop.name, catalog.CategoryUniversal, false)
		if _, err := conn.Exec(ctx,
			`UPDATE products SET price = $2 WHERE shop_id = $1 AND category = $3`,
			id, shop.price, category); err != nil {
			t.Fatalf("price %s: %v", shop.name, err)
		}
	}

	// counted off the template rather than written down: /products.md is the founder's to edit
	lines := 0
	for _, item := range catalog.Template(string(catalog.CategoryUniversal)) {
		if string(item.Category) == category {
			lines++
		}
	}
	if lines < 2 {
		t.Fatalf("the универсальный template has %d %q rows - this test needs two lines to tell "+
			"them apart", lines, category)
	}

	// room for every line, or a truncated list would hide the thing being asserted
	rows, err := q.ListProductsByCategory(ctx, db.ListProductsByCategoryParams{
		Category:      category,
		OffersPerLine: perLine,
		ResultLimit:   int32(perLine * lines),
	})
	if err != nil {
		t.Fatalf("products by category: %v", err)
	}

	sequence := make([]string, 0, len(rows))
	offers := map[string]int{}
	for _, row := range rows {
		sequence = append(sequence, row.TemplateKey.String)
		offers[row.TemplateKey.String]++
		// the two dearest shops are the fifth and sixth offer of every line, so a price above the
		// fourth is a line that leaked more offers than it may show
		if row.Price.Int64 > 70_000 {
			t.Fatalf("%q came back at %d: only the %d cheapest offers of a line belong in the list",
				row.Name, row.Price.Int64, perLine)
		}
	}

	if len(offers) != lines {
		t.Fatalf("want all %d priced lines in the category, got %d", lines, len(offers))
	}
	for key, count := range offers {
		if count > perLine {
			t.Fatalf("%q came back %d times - the listing shows at most %d shops per product",
				key, count, perLine)
		}
	}
	// and the offers of one line arrive together: a line left and returned to is the old wall of
	// one product, merely spread out
	if blocks := len(slices.Compact(sequence)); blocks != lines {
		t.Fatalf("the %d lines came back as %d blocks - a product's offers must be contiguous",
			lines, blocks)
	}
	// the cheapest offer in the category still opens the list
	if rows[0].Price.Int64 != 40_000 || rows[0].ShopName != "cheapest" {
		t.Fatalf("want the cheapest shop's row first, got %q at %d",
			rows[0].ShopName, rows[0].Price.Int64)
	}
}

// a product the owner added themselves shows up in the category drill-down but never moves the basket
// index, which has to stay a comparison of the same shared basket.
//
// the sharper reason: the index requires every basket row to be priced, so if an owner's own products
// counted towards it, one custom row left unpriced would silently delete the shop's badge with nothing
// connecting the two.
func TestCustomProductsAppearInACategoryButNotInTheIndex(t *testing.T) {
	ctx, conn, q := beginTx(t)

	shop := makeShopTx(t, ctx, conn, q, "custom", catalog.CategoryWallpaper, false)
	priceProducts(t, ctx, conn, shop, len(catalog.Template(string(catalog.CategoryWallpaper))), 100_000)

	before, err := q.ListShops(ctx)
	if err != nil {
		t.Fatalf("list shops: %v", err)
	}
	baseline := findShop(t, before, shop).BasketPrice

	// now one very expensive product of the owner's own, in a category the template never touches
	if _, err := q.CreateCustomProduct(ctx, db.CreateCustomProductParams{
		ShopID:       shop,
		Name:         "Перфоратор",
		Price:        pgtype.Int8{Int64: 5_000_000, Valid: true},
		Category:     "tools",
		Unit:         "шт",
		Availability: "in_stock",
	}); err != nil {
		t.Fatalf("create custom product: %v", err)
	}

	// and one the owner has not priced at all, which is the row that would knock the shop out of the
	// index entirely if custom products counted toward the "every product priced" rule
	if _, err := q.CreateCustomProduct(ctx, db.CreateCustomProductParams{
		ShopID:       shop,
		Name:         "Стремянка",
		Category:     "tools",
		Unit:         "шт",
		Availability: "in_stock",
	}); err != nil {
		t.Fatalf("create unpriced custom product: %v", err)
	}

	after, err := q.ListShops(ctx)
	if err != nil {
		t.Fatalf("list shops after custom product: %v", err)
	}
	row := findShop(t, after, shop)
	if !row.PriceIndex.Valid {
		t.Fatal("an unpriced product of the owner's own has cost the shop its index - only template " +
			"rows are the shared basket")
	}
	if row.BasketPrice.Int64 != baseline.Int64 {
		t.Fatalf("a custom product moved the basket from %d to %d - the shared basket stopped being "+
			"shared", baseline.Int64, row.BasketPrice.Int64)
	}

	// but it does show up under `tools`
	tools, err := q.ListProductsByCategory(ctx, db.ListProductsByCategoryParams{
		Category:      "tools",
		OffersPerLine: 4,
		ResultLimit:   100,
	})
	if err != nil {
		t.Fatalf("products by tools: %v", err)
	}
	if len(tools) != 1 || tools[0].Name != "Перфоратор" {
		t.Fatalf("the owner's own tool must appear under tools - got %d rows", len(tools))
	}
	if tools[0].ShopName != "custom" {
		t.Fatalf("want the shop name on the row, got %q", tools[0].ShopName)
	}
}

// -- small helpers -----------------------------------------------------------------------------

func findShop(t *testing.T, shops []db.ListShopsRow, id int64) db.ListShopsRow {
	t.Helper()
	for _, s := range shops {
		if s.ID == id {
			return s
		}
	}
	t.Fatalf("shop %d not in the list", id)
	return db.ListShopsRow{}
}

func bestOffersIn(t *testing.T, ctx context.Context, q *db.Queries, category catalog.Category, limit int32) []db.ListBestOffersInCategoryRow {
	t.Helper()
	rows, err := q.ListBestOffersInCategory(ctx, db.ListBestOffersInCategoryParams{
		Category: string(category),
		Limit:    limit,
	})
	if err != nil {
		t.Fatalf("best offers in %s: %v", category, err)
	}
	return rows
}

func vipIDs(shops []db.ListVipShopsRow) []int64 {
	ids := make([]int64, 0, len(shops))
	for _, s := range shops {
		ids = append(ids, s.ID)
	}
	return ids
}

func offerIDs(shops []db.ListBestOffersInCategoryRow) []int64 {
	ids := make([]int64, 0, len(shops))
	for _, s := range shops {
		ids = append(ids, s.ID)
	}
	return ids
}

func offerIndices(shops []db.ListBestOffersInCategoryRow) []int64 {
	out := make([]int64, 0, len(shops))
	for _, s := range shops {
		out = append(out, s.PriceIndex)
	}
	return out
}

// the templates live in `product_templates`, held in memory by internal/catalog and loaded at startup
// by main.go. tests do not run main.go, so every harness that seeds a shop has to load them first, or
// every shop is created empty and it fails as a wrong *count* three assertions later.
// the same mapping as endpoints.loadCatalogue - keep the two in step, or a column added to
// product_templates arrives in production and not in these tests
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
			InBasket: row.InBasket,
			Specs:    row.Specs, Section: row.Section,
		})
	}
	catalog.Load(loaded)
}
