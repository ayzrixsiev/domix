package endpoints

// обои are the one shop category whose template names slots instead of products, and the whole
// difference between the two lives in a single `switch` inside Products.Update. these pin both
// halves of it, because each half fails silently in its own way:
//
//   - if a slot stopped being recognised, an обои owner would find the name locked to "Обои премиум
//     (Россия)" with a 200 coming back and nothing anywhere saying why their edit vanished;
//   - if the recognition leaked to the other three templates, one shop could rename "Кнауф Ротбанд,
//     25 кг" to anything at all, and the basket index would go on comparing the renamed row against
//     everyone else's Ротбанд as though they were still the same product.
//
// they go through the real auth.RequireAuth with a real signed token rather than calling the
// handlers directly: the ownership check and the slot check are separate answers to separate
// questions, and testing one without the other leaves half the path unexercised. going through the
// real middleware also means these exercise its user-still-exists lookup for free.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
)

// any string works - these tests sign and verify with the same one, which is the whole contract
const testJWTSecret = "test-secret-not-a-real-one"

func productsUnderTest(t *testing.T) (*Products, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	_, ctx, tx, q := homeUnderTest(t)
	if _, err := tx.Exec(ctx, "DELETE FROM shops"); err != nil {
		t.Fatalf("clearing shops: %v", err)
	}
	return &Products{Queries: q, JWTSecret: testJWTSecret}, ctx, tx, q
}

// the id of one seeded row, looked up by the template key that identifies it. the key is the stable
// handle - ids are whatever postgres hands out - so this is also how the app's own flow finds it.
func seededProductID(t *testing.T, ctx context.Context, tx pgx.Tx, shopID int64, templateKey string) int64 {
	t.Helper()

	var id int64
	err := tx.QueryRow(ctx,
		`SELECT id FROM products WHERE shop_id = $1 AND template_key = $2`, shopID, templateKey).Scan(&id)
	if err != nil {
		t.Fatalf("find seeded product %q in shop %d: %v", templateKey, shopID, err)
	}
	return id
}

// the shop's owner, so the request below can be signed as somebody the authorization check accepts
func shopOwnerID(t *testing.T, ctx context.Context, tx pgx.Tx, shopID int64) int64 {
	t.Helper()

	var userID int64
	if err := tx.QueryRow(ctx, `SELECT user_id FROM shops WHERE id = $1`, shopID).Scan(&userID); err != nil {
		t.Fatalf("find the owner of shop %d: %v", shopID, err)
	}
	return userID
}

// sends one request to /api/products/{id} as the given user, through the wrapper main.go registers
func callProduct(
	t *testing.T, ctx context.Context, p *Products,
	method string, productID, asUserID int64, body string,
) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "+998900000000", testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	path := "/api/products/" + strconv.FormatInt(productID, 10)
	req := httptest.NewRequestWithContext(ctx, method, path, strings.NewReader(body))
	req.SetPathValue("id", strconv.FormatInt(productID, 10))
	req.Header.Set("Authorization", "Bearer "+token)

	handler := p.Update
	if method == http.MethodDelete {
		handler = p.Delete
	}

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, p.Queries, handler)(rec, req)
	return rec
}

// POSTs a new product into a shop, as the given user
func callProductInShop(
	t *testing.T, ctx context.Context, p *Products, shopID, asUserID int64, body string,
) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "+998900000000", testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	path := fmt.Sprintf("/api/shops/%d/products", shopID)
	req := httptest.NewRequestWithContext(ctx, http.MethodPost, path, strings.NewReader(body))
	req.SetPathValue("id", strconv.FormatInt(shopID, 10))
	req.Header.Set("Authorization", "Bearer "+token)

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, p.Queries, p.Create)(rec, req)
	return rec
}

// the public catalogue of one shop
func listProducts(t *testing.T, ctx context.Context, p *Products, shopID int64) []ProductResponse {
	t.Helper()

	req := httptest.NewRequestWithContext(ctx, http.MethodGet,
		fmt.Sprintf("/api/shops/%d/products", shopID), nil)
	req.SetPathValue("id", strconv.FormatInt(shopID, 10))
	rec := httptest.NewRecorder()
	p.ListByShop(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var listed []ProductResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &listed); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return listed
}

func decodeProduct(t *testing.T, rec *httptest.ResponseRecorder) ProductResponse {
	t.Helper()

	var product ProductResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &product); err != nil {
		t.Fatalf("decode %s: %v", rec.Body.String(), err)
	}
	return product
}

// the point of the slot: the owner writes in the collection they actually stock, and the row keeps
// the key it is compared on.
func TestWallpaperSlotTakesTheOwnersName(t *testing.T) {
	products, ctx, tx, q := productsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Oboi", catalog.CategoryWallpaper, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	slot := seededProductID(t, ctx, tx, shop, "wallpaper.premium_ru")

	// what the app sends: the owner's own name, their price, and the locked category and unit
	// submitted back unchanged
	rec := callProduct(t, ctx, products, http.MethodPut, slot, owner, `{
		"name": "Erismann Vlies 1,06 м",
		"category": "finishing",
		"unit": "рулон",
		"price": 320000,
		"availability": "in_stock"
	}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	saved := decodeProduct(t, rec)
	if saved.Name != "Erismann Vlies 1,06 м" {
		t.Fatalf("a slot's name is the owner's to write, got %q", saved.Name)
	}
	if saved.Price == nil || *saved.Price != 320_000 {
		t.Fatalf("want the price saved alongside the name, got %v", saved.Price)
	}

	// both flags, because the app reads them for different controls: the name is a text field
	// (name_editable) while the category, the unit and the delete button stay locked (is_template)
	if !saved.IsTemplate || !saved.NameEditable {
		t.Fatalf("a slot is a template row with an editable name, got is_template=%v name_editable=%v",
			saved.IsTemplate, saved.NameEditable)
	}

	// the unit is what keeps ten different rolls a comparable basket, so it must have ignored an
	// attempt to move it even though the name went through on the same request
	rec = callProduct(t, ctx, products, http.MethodPut, slot, owner, `{
		"name": "Erismann Vlies 1,06 м",
		"category": "tools",
		"unit": "м²",
		"price": 320000,
		"availability": "in_stock"
	}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if moved := decodeProduct(t, rec); moved.Unit != "рулон" || moved.Category != "finishing" {
		t.Fatalf("a slot's unit and category are locked, got %q / %q", moved.Unit, moved.Category)
	}
}

// the rule the other three templates still live under, and the reason the slot path had to be a
// third branch rather than a loosening of the existing one.
func TestOrdinaryTemplateProductKeepsItsName(t *testing.T) {
	products, ctx, tx, q := productsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Univ", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	row := seededProductID(t, ctx, tx, shop, "universal.rotband_25")

	rec := callProduct(t, ctx, products, http.MethodPut, row, owner, `{
		"name": "Ротбанд по акции!!!",
		"category": "tools",
		"unit": "шт",
		"price": 95000,
		"availability": "in_stock"
	}`)
	// a 200, not a 400: the app submits the locked fields back unchanged, so refusing them would
	// punish an honest client. what must not happen is the write landing.
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	saved := decodeProduct(t, rec)
	if saved.Name != "Штукатурка гипсовая" || saved.Specs != "25 кг · Rotband · Knauf" {
		t.Fatalf("a template row's name must survive an edit, got %q", saved.Name)
	}
	if saved.Unit != "мешок" || saved.Category != "mixes" {
		t.Fatalf("a template row's unit and category must survive too, got %q / %q", saved.Unit, saved.Category)
	}
	if saved.NameEditable {
		t.Fatal("a универсальный template row is not a slot - name_editable must be false")
	}
	// the price is the one thing that was supposed to change
	if saved.Price == nil || *saved.Price != 95_000 {
		t.Fatalf("want the price through, got %v", saved.Price)
	}
}

// a slot may be renamed but not removed. an обои shop is ranked on exactly ten of them, so deleting
// the премиум rows is the same "look cheap by not stocking the expensive half" trick that template
// rows are protected from - it just wears a different name here.
func TestSlotCannotBeDeleted(t *testing.T) {
	products, ctx, tx, q := productsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Oboi2", catalog.CategoryWallpaper, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	slot := seededProductID(t, ctx, tx, shop, "wallpaper.premium_ru")

	rec := callProduct(t, ctx, products, http.MethodDelete, slot, owner, "")
	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d: %s", rec.Code, rec.Body.String())
	}

	var body map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["code"] != "template_product" {
		t.Fatalf("want the machine-readable code the app localizes, got %q", body["code"])
	}
}

// the name is validated on the slot path exactly as it is on a custom product, because it lands in
// the same column. a blank one would otherwise leave the row with an empty tile in every grid.
func TestSlotRefusesABlankName(t *testing.T) {
	products, ctx, tx, q := productsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Oboi3", catalog.CategoryWallpaper, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	slot := seededProductID(t, ctx, tx, shop, "wallpaper.econom_cn_1")

	rec := callProduct(t, ctx, products, http.MethodPut, slot, owner, `{
		"name": "   ",
		"category": "finishing",
		"unit": "рулон",
		"price": 90000,
		"availability": "in_stock"
	}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

// the photo has to survive the whole way: catalog.Item.Image -> products.image_path at seeding ->
// image_url on the wire. each hop is somewhere it can be dropped without anything failing, and the
// symptom would be a grid of placeholder tiles that looks like a design choice.
func TestSeededProductsCarryTheirPhoto(t *testing.T) {
	products, ctx, tx, q := productsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Photos", catalog.CategoryUniversal, false)
	listed := listProducts(t, ctx, products, shop)

	for _, product := range listed {
		if product.ImageURL == nil {
			t.Fatalf("%q came back with no photo", product.Name)
		}
		if !strings.HasPrefix(*product.ImageURL, "/images/shops/universal/") {
			t.Fatalf("want a root-relative url the app can prepend a host to, got %q", *product.ImageURL)
		}
	}

	// a product the owner adds themselves has no photo, and that must be null rather than a url
	// pointing at a file that isn't there
	owner := shopOwnerID(t, ctx, tx, shop)
	rec := callProductInShop(t, ctx, products, shop, owner, `{
		"name": "Свой товар", "category": "tools", "unit": "шт",
		"price": 50000, "availability": "in_stock"
	}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", rec.Code, rec.Body.String())
	}
	if created := decodeProduct(t, rec); created.ImageURL != nil {
		t.Fatalf("a product with no photo must send null, got %q", *created.ImageURL)
	}
}

// every обои shop is seeded with the ten slots the founder specified, and the app relies on them
// arriving in that order - премиум first, эконом last - because that is the order the owner's grid
// renders and the sequence they price them in.
func TestWallpaperShopIsSeededWithTenSlots(t *testing.T) {
	products, ctx, tx, q := productsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Oboi4", catalog.CategoryWallpaper, false)

	listed := listProducts(t, ctx, products, shop)
	if len(listed) != len(catalog.Template(string(catalog.CategoryWallpaper))) {
		t.Fatalf("want %d slots, got %d", len(catalog.Template(string(catalog.CategoryWallpaper))), len(listed))
	}

	for i, product := range listed {
		if !product.IsTemplate || !product.NameEditable {
			t.Fatalf("slot %d should arrive as an editable-name template row, got is_template=%v name_editable=%v",
				i, product.IsTemplate, product.NameEditable)
		}
		// unpriced, which is the state the "укажите цену" prompt is built on
		if product.Price != nil {
			t.Fatalf("slot %d should arrive unpriced, got %d", i, *product.Price)
		}
	}
}

// deleting a user cuts their app off immediately, rather than four months later when their token
// expires.
//
// this is the whole reason RequireAuth reads the database instead of trusting the signature alone. a
// JWT is a claim frozen at the moment it was signed: nothing in it changes when the row it names is
// deleted, and there is no revocation list, so without the lookup a deleted owner keeps editing
// products from a phone that never noticed. the founder found this by deleting a user and watching
// the app carry on.
//
// the distinct `account_deleted` code matters as much as the 401: the app clears its stored token on
// seeing it, which is the difference between "you are signed out" and a screen that retries forever.
func TestADeletedUserIsRefusedImmediately(t *testing.T) {
	p, ctx, tx, q := productsUnderTest(t)

	shopID := makeSeededShop(t, ctx, tx, q, "Гвоздь", catalog.CategoryUniversal, false)
	ownerID := shopOwnerID(t, ctx, tx, shopID)
	productID := seededProductID(t, ctx, tx, shopID, "universal.nails")

	body := `{"name":"Гвозди","price":15000,"category":"fasteners","unit":"кг","availability":"in_stock"}`

	// the same request, signed the same way, before and after - so the only thing that changed
	// between the two assertions is whether the user row exists
	if rec := callProduct(t, ctx, p, http.MethodPut, productID, ownerID, body); rec.Code != http.StatusOK {
		t.Fatalf("the owner should be able to price their own product, got %d: %s", rec.Code, rec.Body.String())
	}

	// cascades the shop and its products away too, which is exactly what deleting a user does in
	// production - and the point is that the *token* stops working, not merely that the data is gone
	if _, err := tx.Exec(ctx, `DELETE FROM users WHERE id = $1`, ownerID); err != nil {
		t.Fatalf("delete the user: %v", err)
	}

	rec := callProduct(t, ctx, p, http.MethodPut, productID, ownerID, body)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("a deleted user must be refused with 401, got %d: %s", rec.Code, rec.Body.String())
	}

	var payload map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode the error body: %v", err)
	}
	if payload["code"] != "account_deleted" {
		t.Fatalf("want the code the app logs out on, got %q", payload["code"])
	}
}

// a token signed with the wrong key is still refused, and *not* as account_deleted - the app must
// not learn to treat a forged token and a removed account as the same event
func TestAForgedTokenIsRefused(t *testing.T) {
	p, ctx, tx, q := productsUnderTest(t)

	shopID := makeSeededShop(t, ctx, tx, q, "Форж", catalog.CategoryUniversal, false)
	productID := seededProductID(t, ctx, tx, shopID, "universal.nails")

	token, err := auth.GenerateJWT(shopOwnerID(t, ctx, tx, shopID), "+998900000000", "a-different-secret")
	if err != nil {
		t.Fatalf("sign: %v", err)
	}

	path := "/api/products/" + strconv.FormatInt(productID, 10)
	req := httptest.NewRequestWithContext(ctx, http.MethodPut, path, strings.NewReader("{}"))
	req.SetPathValue("id", strconv.FormatInt(productID, 10))
	req.Header.Set("Authorization", "Bearer "+token)

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, p.Queries, p.Update)(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401 for a token signed with the wrong key, got %d", rec.Code)
	}
	var payload map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &payload)
	if payload["code"] == "account_deleted" {
		t.Fatal("a forged token must not be reported as a deleted account")
	}
}
