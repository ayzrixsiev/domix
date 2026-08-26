package endpoints

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
	"domix/backend/internal/imagestore"
)

// The photo endpoints, through the real RequireAuth with a real signed token - the same shape the
// rest of this package's tests use, and for the same reason: ownership and the rule being tested are
// separate answers, and exercising one without the other leaves half the path unchecked.
//
// The bytes are real jpegs built in memory rather than a fixture on disk, because the handler
// decodes what it is given: a fixture would be testing that a file the author picked is still there.

// a Products whose uploads land in a directory that disappears with the test
func imageProductsUnderTest(t *testing.T) (*Products, string, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	products, ctx, tx, q := productsUnderTest(t)

	root := t.TempDir()
	store, err := imagestore.NewDisk(root)
	if err != nil {
		t.Fatalf("imagestore.NewDisk: %v", err)
	}
	products.Images = store
	// Uploads stays nil: the per-account bucket is ratelimit's to test, and a limiter here would
	// make the number of requests one of these may make part of its setup
	return products, root, ctx, tx, q
}

func testPhoto(t *testing.T, width, height int) []byte {
	t.Helper()

	img := image.NewRGBA(image.Rect(0, 0, width, height))
	draw.Draw(img, img.Bounds(), image.NewUniform(color.RGBA{R: 200, G: 120, B: 40, A: 255}), image.Point{}, draw.Src)

	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90}); err != nil {
		t.Fatalf("encode: %v", err)
	}
	return buf.Bytes()
}

// POSTs one photo to /api/products/{id}/image as the given user
func callUpload(
	t *testing.T, ctx context.Context, p *Products,
	productID, asUserID int64, filename string, photo []byte,
) *httptest.ResponseRecorder {
	t.Helper()

	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	part, err := form.CreateFormFile("image", filename)
	if err != nil {
		t.Fatalf("multipart: %v", err)
	}
	if _, err := part.Write(photo); err != nil {
		t.Fatalf("multipart write: %v", err)
	}
	if err := form.Close(); err != nil {
		t.Fatalf("multipart close: %v", err)
	}

	token, err := auth.GenerateJWT(asUserID, "+998900000000", testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	path := fmt.Sprintf("/api/products/%d/image", productID)
	req := httptest.NewRequestWithContext(ctx, http.MethodPost, path, &body)
	req.SetPathValue("id", strconv.FormatInt(productID, 10))
	req.Header.Set("Content-Type", form.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, p.Queries, p.UploadImage)(rec, req)
	return rec
}

func callRemoveImage(
	t *testing.T, ctx context.Context, p *Products, productID, asUserID int64,
) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "+998900000000", testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	path := fmt.Sprintf("/api/products/%d/image", productID)
	req := httptest.NewRequestWithContext(ctx, http.MethodDelete, path, nil)
	req.SetPathValue("id", strconv.FormatInt(productID, 10))
	req.Header.Set("Authorization", "Bearer "+token)

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, p.Queries, p.RemoveImage)(rec, req)
	return rec
}

// the served url back to the path on disk, which is the pair this whole feature rests on
func storedFile(t *testing.T, root string, imageURL *string) string {
	t.Helper()

	if imageURL == nil {
		t.Fatal("the product came back with no image url")
	}
	rel := strings.TrimPrefix(*imageURL, imagestore.DefaultURLPrefix)
	if rel == *imageURL {
		t.Fatalf("%q does not start with %q", *imageURL, imagestore.DefaultURLPrefix)
	}
	return filepath.Join(root, filepath.FromSlash(rel))
}

// both files a response names, so a test can assert on the pair. **A master with no thumbnail is the
// failure that does not look like one**: the edit screen works, the row is right, and every tile in
// every grid is blank.
func storedPair(t *testing.T, root string, saved ProductResponse) (master, thumb string) {
	t.Helper()

	if saved.ImageThumbURL == nil {
		t.Fatal("the product came back with an image_url and no image_thumb_url")
	}
	return storedFile(t, root, saved.ImageURL), storedFile(t, root, saved.ImageThumbURL)
}

func TestAnOwnerPutsAPhotoOnTheirOwnProduct(t *testing.T) {
	products, root, ctx, tx, q := imageProductsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Foto", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)

	created := decodeProduct(t, callProductInShop(t, ctx, products, shop, owner, `{
		"name": "Тачка садовая", "category": "tools", "unit": "шт",
		"price": 450000, "availability": "in_stock"
	}`))
	if created.ImageURL != nil {
		t.Fatalf("a new product starts with no photo, got %q", *created.ImageURL)
	}

	rec := callUpload(t, ctx, products, created.ID, owner, "photo.jpg", testPhoto(t, 1600, 1200))
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	saved := decodeProduct(t, rec)
	// **two files, and the response names both.** the database holds only the master's path; the
	// thumbnail's is derived from it, so nothing else in the system would notice it missing until a
	// hundred tiles came up blank on somebody's phone.
	master, thumb := storedPair(t, root, saved)
	if _, err := os.Stat(master); err != nil {
		t.Fatalf("the photo the response names is not on disk: %v", err)
	}
	if _, err := os.Stat(thumb); err != nil {
		t.Fatalf("the thumbnail the response names is not on disk: %v", err)
	}
	// the flag the edit screen draws its delete button off: this photo is the shop's own
	if !saved.OwnImage {
		t.Error("own_image is false on a photo the owner just uploaded")
	}

	// and it is on the row, not only in the response - the customer-facing list is what has to show
	// it
	for _, listed := range listProducts(t, ctx, products, shop) {
		if listed.ID == created.ID {
			if listed.ImageURL == nil || *listed.ImageURL != *saved.ImageURL {
				t.Fatalf("the catalogue lists %v, expected %q", listed.ImageURL, *saved.ImageURL)
			}
			return
		}
	}
	t.Fatal("the product is missing from its own shop's catalogue")
}

// **the founder's rule, positive half: an owner photographs what the catalogue has not.**
//
// The two categories that qualify today qualify for different reasons, so both are here. An обои
// slot names a *kind* of wallpaper - "премиум (Россия)" - and there is no such object to photograph,
// so the shop's own roll is the only picture that could ever be on that tile. Древесные материалы
// names real products and simply has not been shot yet.
//
// The rule is read off the template rather than off this list of categories (see templateFlags), so
// what this test really pins is that both of those end up on the permissive side of it.
func TestAnOwnerPhotographsWhatTheCatalogueHasNot(t *testing.T) {
	for _, tc := range []struct {
		name     string
		category catalog.Category
		key      string
	}{
		{"обои slot", catalog.CategoryWallpaper, "wallpaper.premium_ru"},
		{"unphotographed wood row", catalog.CategoryWood, "wood.board_25x150"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			products, root, ctx, tx, q := imageProductsUnderTest(t)

			shop := makeSeededShop(t, ctx, tx, q, "Foto"+tc.key, tc.category, false)
			owner := shopOwnerID(t, ctx, tx, shop)
			row := seededProductID(t, ctx, tx, shop, tc.key)

			rec := callUpload(t, ctx, products, row, owner, "roll.jpg", testPhoto(t, 900, 900))
			if rec.Code != http.StatusOK {
				t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
			}

			saved := decodeProduct(t, rec)
			if !saved.IsTemplate {
				t.Fatal("uploading a photo must not turn a template row into an ordinary product")
			}
			if !saved.PhotoEditable {
				t.Error("photo_editable is false on a row the endpoint just accepted a photo for")
			}
			if _, err := os.Stat(storedFile(t, root, saved.ImageURL)); err != nil {
				t.Fatalf("the file the response names is not on disk: %v", err)
			}
		})
	}
}

// **the founder's rule, refusing half.** a универсальный row points at a photograph we took, shared
// by every универсальный shop in the market - and the basket index says that row is *the same
// product* as its counterpart across the road. An owner replacing the picture makes two tiles of one
// product show two different objects, and it is the customer comparing the two shops who is misled.
//
// The 403 has to arrive before the bytes do, which is why the check sits above the rate limiter and
// above readUploadedImage: refusing a six-megabyte upload after receiving it spends exactly what the
// refusal exists to save.
func TestTheCataloguesOwnPhotographCannotBeReplaced(t *testing.T) {
	products, _, ctx, tx, q := imageProductsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Zamok", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	row := seededProductID(t, ctx, tx, shop, photographedUniversalKey(t))

	rec := callUpload(t, ctx, products, row, owner, "mine.jpg", testPhoto(t, 800, 800))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d: %s", rec.Code, rec.Body.String())
	}

	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode %s: %v", rec.Body.String(), err)
	}
	// the machine-readable code the app turns into a sentence, and the flag it draws the control off
	if body["code"] != "template_photo" {
		t.Fatalf("want template_photo, got %q", body["code"])
	}
	for _, listed := range listProducts(t, ctx, products, shop) {
		if listed.ID == row {
			if listed.PhotoEditable {
				t.Fatal("photo_editable is true on a row whose photo the endpoint refuses to replace")
			}
			return
		}
	}
	t.Fatal("the product is missing from its own shop's catalogue")
}

// the first универсальный row the catalogue actually has a photograph of - which is all of them
// today, and is looked up rather than written down so that a template edit cannot silently turn this
// test into one about a row with no photo.
func photographedUniversalKey(t *testing.T) string {
	t.Helper()

	for _, item := range catalog.Template(string(catalog.CategoryUniversal)) {
		if item.ImagePath != "" {
			return item.Key
		}
	}
	t.Skip("no photographed row in the universal template - there is no rule to test")
	return ""
}

// replacing is the common case - photograph it again in better light - and every replacement leaves
// a file behind unless the row's previous one is unlinked
func TestReplacingAPhotoUnlinksTheOneItReplaced(t *testing.T) {
	products, root, ctx, tx, q := imageProductsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Zamena", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	created := decodeProduct(t, callProductInShop(t, ctx, products, shop, owner, `{
		"name": "Ведро", "category": "tools", "unit": "шт", "price": 25000, "availability": "in_stock"
	}`))

	first := decodeProduct(t, callUpload(t, ctx, products, created.ID, owner, "a.jpg", testPhoto(t, 800, 600)))
	firstMaster, firstThumb := storedPair(t, root, first)

	second := decodeProduct(t, callUpload(t, ctx, products, created.ID, owner, "b.jpg", testPhoto(t, 700, 700)))
	if *second.ImageURL == *first.ImageURL {
		// a reused name would be served from every cache that already holds the old bytes, for a
		// year - the photo would look unchanged on every phone that had seen the product
		t.Fatal("the replacement reused the same url")
	}
	if _, err := os.Stat(firstMaster); !os.IsNotExist(err) {
		t.Errorf("the replaced photo is still on disk: %v", err)
	}
	// **the thumbnail has to go with it.** nothing in the database ever named this file, so if the
	// replacement path forgets it, every replaced photo leaves one behind forever and the only thing
	// that would ever notice is the admin panel's sweep.
	if _, err := os.Stat(firstThumb); !os.IsNotExist(err) {
		t.Errorf("the replaced thumbnail is still on disk: %v", err)
	}
	newMaster, newThumb := storedPair(t, root, second)
	if _, err := os.Stat(newMaster); err != nil {
		t.Errorf("the replacement is not on disk: %v", err)
	}
	if _, err := os.Stat(newThumb); err != nil {
		t.Errorf("the replacement's thumbnail is not on disk: %v", err)
	}
}

// **the guard that protects the catalogue.** a seeded universal row points at a photo shared by
// every universal shop; removing the owner's own upload must put that path back and must not touch
// the file it names.
//
// **The upload is written straight onto the row rather than posted**, because the endpoint refuses
// exactly this combination now (see TestTheCataloguesOwnPhotographCannotBeReplaced) - and removal is
// deliberately *not* gated by the same rule, for the case this test is standing in for: rows that
// were photographed by their owner before the rule existed, and rows whose catalogue is shot after
// the fact. Those are the ones with something to restore to, and with the delete path closed as well
// their owners would be stuck with a picture the catalogue is supposed to override.
func TestRemovingAPhotoRestoresTheCatalogueShot(t *testing.T) {
	products, root, ctx, tx, q := imageProductsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Vozvrat", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)

	key := photographedUniversalKey(t)
	catalogueImage := catalog.TemplateImage(key)
	product := seededProductID(t, ctx, tx, shop, key)

	// stand the shared file up inside this test's own root, so a deletion would be visible
	shared := filepath.Join(root, filepath.FromSlash(catalogueImage))
	if err := os.MkdirAll(filepath.Dir(shared), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(shared, []byte("the catalogue photo"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}

	normalized, err := imagestore.Normalize(testPhoto(t, 640, 480))
	if err != nil {
		t.Fatalf("normalize an upload: %v", err)
	}
	stored, err := products.Images.Save(ctx, normalized)
	if err != nil {
		t.Fatalf("save an upload: %v", err)
	}
	uploaded, err := q.SetProductImage(ctx, db.SetProductImageParams{
		ID:        product,
		ImagePath: pgtype.Text{String: stored, Valid: true},
	})
	if err != nil {
		t.Fatalf("point the row at it: %v", err)
	}
	uploadedURL, _, _ := productImage(products.URLs, uploaded.ImagePath)
	uploadedPath := storedFile(t, root, uploadedURL)

	rec := callRemoveImage(t, ctx, products, product, owner)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	restored := decodeProduct(t, rec)
	if restored.ImageURL == nil || *restored.ImageURL != imagestore.DefaultURLPrefix+catalogueImage {
		t.Fatalf("got %v, expected the catalogue photo %q back", restored.ImageURL, catalogueImage)
	}
	// and it is no longer the shop's own, which is what hides "удалить фото" - pressing it again
	// would set the same catalogue path and change nothing
	if restored.OwnImage {
		t.Error("own_image is true on the shared catalogue photo")
	}
	if _, err := os.Stat(shared); err != nil {
		t.Fatalf("the shared catalogue photo was deleted: %v", err)
	}
	if _, err := os.Stat(uploadedPath); !os.IsNotExist(err) {
		t.Errorf("the owner's own upload is still on disk: %v", err)
	}
}

// a product of the owner's own has no catalogue photo to fall back to, so removing leaves none
func TestRemovingAPhotoFromAnOwnProductLeavesItWithNone(t *testing.T) {
	products, _, ctx, tx, q := imageProductsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Pusto", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	created := decodeProduct(t, callProductInShop(t, ctx, products, shop, owner, `{
		"name": "Стремянка", "category": "tools", "unit": "шт", "price": 700000, "availability": "in_stock"
	}`))

	callUpload(t, ctx, products, created.ID, owner, "x.jpg", testPhoto(t, 500, 500))

	removed := decodeProduct(t, callRemoveImage(t, ctx, products, created.ID, owner))
	if removed.ImageURL != nil {
		t.Fatalf("got %q, expected no photo", *removed.ImageURL)
	}
}

func TestOnlyTheShopsOwnerMayChangeAProductsPhoto(t *testing.T) {
	products, _, ctx, tx, q := imageProductsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Chuzhoy", catalog.CategoryUniversal, false)
	stranger := makeSeededShop(t, ctx, tx, q, "Sosed", catalog.CategoryUniversal, false)
	strangerID := shopOwnerID(t, ctx, tx, stranger)
	product := seededProductID(t, ctx, tx, shop, catalog.Template(string(catalog.CategoryUniversal))[0].Key)

	rec := callUpload(t, ctx, products, product, strangerID, "theirs.jpg", testPhoto(t, 400, 400))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d: %s", rec.Code, rec.Body.String())
	}
	if rec := callRemoveImage(t, ctx, products, product, strangerID); rec.Code != http.StatusForbidden {
		t.Fatalf("want 403 on delete, got %d: %s", rec.Code, rec.Body.String())
	}
}

// the extension and the Content-Type are both written by the client, so the only real check is the
// decode - and its failure has to reach the owner as a sentence about the file, not as a 500.
//
// on a product of the owner's own, because a seeded универсальный row is refused a step earlier now
// and would answer template_photo whatever bytes were attached to it.
func TestSomethingThatIsNotAPhotoIsRefused(t *testing.T) {
	products, _, ctx, tx, q := imageProductsUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Nefoto", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	product := decodeProduct(t, callProductInShop(t, ctx, products, shop, owner, `{
		"name": "Уровень", "category": "tools", "unit": "шт", "price": 90000, "availability": "in_stock"
	}`)).ID

	rec := callUpload(t, ctx, products, product, owner, "malware.jpg", []byte("MZ\x90\x00 definitely not a jpeg"))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode %s: %v", rec.Body.String(), err)
	}
	// the machine-readable code, because the backend's messages are english and the app renders ru/uz
	if body["code"] != "invalid_image" {
		t.Fatalf("want invalid_image, got %q", body["code"])
	}
}
