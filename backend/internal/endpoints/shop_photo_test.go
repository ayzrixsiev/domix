package endpoints

// The storefront photograph: the one picture a VIP card draws, uploaded from the admin panel. Two
// things here fail silently. A shop photo lives in the same directory as a product photo, so the orphan
// sweep deletes it an hour after upload unless the query protecting live files reads `shops` as well as
// `products`. And `needs_photo` is the only thing that tells the panel to ask for one.

import (
	"bytes"
	"context"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
	"domix/backend/internal/imagestore"
)

// POSTs one photo to /api/admin/shops/{id}/photo through the real middleware chain
func callShopPhotoUpload(
	t *testing.T, ctx context.Context, a *Admin, shopID, asUserID int64, photo []byte,
) *httptest.ResponseRecorder {
	t.Helper()

	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	part, err := form.CreateFormFile("image", "storefront.jpg")
	if err != nil {
		t.Fatalf("multipart: %v", err)
	}
	if _, err := part.Write(photo); err != nil {
		t.Fatalf("multipart write: %v", err)
	}
	if err := form.Close(); err != nil {
		t.Fatalf("multipart close: %v", err)
	}

	token, err := auth.GenerateJWT(asUserID, "+998900000000", 0, testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	id := strconv.FormatInt(shopID, 10)
	req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/api/admin/shops/"+id+"/photo", &body)
	req.SetPathValue("id", id)
	req.Header.Set("Content-Type", form.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, a.Queries, a.RequireAdmin(a.RouteShopPhoto))(rec, req)
	return rec
}

type storedPhoto struct {
	Path     string `json:"image_path"`
	URL      string `json:"image_url"`
	ThumbURL string `json:"image_thumb_url"`
}

// **the card is the whole reason the column exists**, so the test follows the photo all the way to
// the home screen: the same two files every upload writes, an upload path (which is what puts it
// behind the uploads sweep and `RemoveFile`), and two ready-made urls on the card — the app is never
// told how a thumbnail's path is spelled.
func TestAStorefrontPhotoReachesTheVipCardAsTwoReadyMadeURLs(t *testing.T) {
	admin, root, ctx, tx, q := sweepUnderTest(t)
	home := &Home{Queries: q}

	adminID := makeUser(t, ctx, q, "Shooter", "admin")
	shopID := makeSeededShop(t, ctx, tx, q, "Vippy", catalog.CategoryUniversal, true)

	rec := callShopPhotoUpload(t, ctx, admin, shopID, adminID, testPhoto(t, 1400, 900))
	if rec.Code != http.StatusOK {
		t.Fatalf("upload = %d (%s), want 200", rec.Code, rec.Body.String())
	}
	var saved storedPhoto
	decodeBody(t, rec, &saved)

	if !imagestore.IsUpload(saved.Path) {
		t.Fatalf("stored at %q - a storefront must be an upload, or neither the sweep nor RemoveFile reaches it", saved.Path)
	}
	if !exists(t, root, saved.Path) || !exists(t, root, imagestore.ThumbPath(saved.Path)) {
		t.Fatalf("the master and its thumbnail are not both on disk")
	}

	var card struct {
		VipShops []struct {
			ID            int64  `json:"id"`
			ImageURL      string `json:"image_url"`
			ImageThumbURL string `json:"image_thumb_url"`
			ProductCount  int64  `json:"product_count"`
		} `json:"vip_shops"`
	}
	if rec := getJSON(t, ctx, home.Get, "/api/home", &card); rec.Code != http.StatusOK {
		t.Fatalf("home = %d (%s)", rec.Code, rec.Body.String())
	}
	if len(card.VipShops) != 1 || card.VipShops[0].ID != shopID {
		t.Fatalf("expected the one VIP shop on the home screen, got %d cards", len(card.VipShops))
	}
	if want := "/images/" + saved.Path; card.VipShops[0].ImageURL != want {
		t.Errorf("image_url = %q, want %q", card.VipShops[0].ImageURL, want)
	}
	if want := "/images/" + imagestore.ThumbPath(saved.Path); card.VipShops[0].ImageThumbURL != want {
		t.Errorf("image_thumb_url = %q, want %q", card.VipShops[0].ImageThumbURL, want)
	}
	// «1200 товаров» on the card: a seeded shop holds its category's whole template
	if card.VipShops[0].ProductCount == 0 {
		t.Error("the card carries no product count - the row under the address would read 0")
	}

	// ── replacing it: the new file is written first and the old one unlinked after, so a photo can
	// never be a row naming a file that is gone
	second := callShopPhotoUpload(t, ctx, admin, shopID, adminID, testPhoto(t, 900, 1200))
	if second.Code != http.StatusOK {
		t.Fatalf("replace = %d (%s)", second.Code, second.Body.String())
	}
	var replaced storedPhoto
	decodeBody(t, second, &replaced)
	if replaced.Path == saved.Path {
		t.Error("the replacement reused the name - urls are cached for a year, so it must be a new one")
	}
	if exists(t, root, saved.Path) || exists(t, root, imagestore.ThumbPath(saved.Path)) {
		t.Error("the photo that was replaced is still on disk")
	}

	// ── and taking it off clears the column and the files with it
	token, err := auth.GenerateJWT(adminID, "+998900000000", 0, testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}
	id := strconv.FormatInt(shopID, 10)
	req := httptest.NewRequestWithContext(ctx, http.MethodDelete, "/api/admin/shops/"+id+"/photo", nil)
	req.SetPathValue("id", id)
	req.Header.Set("Authorization", "Bearer "+token)
	removed := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, admin.Queries, admin.RequireAdmin(admin.RouteShopPhoto))(removed, req)

	if removed.Code != http.StatusOK {
		t.Fatalf("remove = %d (%s)", removed.Code, removed.Body.String())
	}
	var cleared storedPhoto
	decodeBody(t, removed, &cleared)
	if cleared.Path != "" || cleared.ThumbURL != "" {
		t.Errorf("after removal the row still names %q", cleared.Path)
	}
	if exists(t, root, replaced.Path) {
		t.Error("the removed photo is still on disk")
	}
}

// **the sweep's blind spot, and it would be invisible.** A storefront sits in `shops/uploads/`
// beside every product photo, so the file list contains it — and the query that says which files are
// live read `products` alone until shops could carry one. An hour after a placement was photographed
// the sweep would quietly delete it, report a tidy number, and the card would go blank.
func TestTheUploadsSweepLeavesAStorefrontPhotoAlone(t *testing.T) {
	admin, root, ctx, tx, q := sweepUnderTest(t)

	shopID := makeSeededShop(t, ctx, tx, q, "Photographed", catalog.CategoryUniversal, true)
	owner := shopOwnerID(t, ctx, tx, shopID)
	if _, err := q.AdminUpdateUser(ctx, db.AdminUpdateUserParams{ID: owner, Role: "admin"}); err != nil {
		t.Fatalf("promote the owner: %v", err)
	}

	// old enough that only being referenced protects it
	live := storePhoto(t, ctx, admin, root, 3*time.Hour)
	if _, err := q.SetShopImage(ctx, db.SetShopImageParams{
		ID:        shopID,
		ImagePath: pgtype.Text{String: live, Valid: true},
	}); err != nil {
		t.Fatalf("point the shop at it: %v", err)
	}
	dead := storePhoto(t, ctx, admin, root, 3*time.Hour)

	rec := requestAdmin(t, ctx, admin, http.MethodDelete, "/api/admin/storage/orphans", owner, admin.RouteOrphans)
	if rec.Code != http.StatusOK {
		t.Fatalf("sweep: want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	if !exists(t, root, live) || !exists(t, root, imagestore.ThumbPath(live)) {
		t.Fatal("the sweep deleted a storefront a VIP card is drawing")
	}
	if exists(t, root, dead) {
		t.Error("the unreferenced photo survived - the sweep did nothing at all")
	}
}

// The founder's rule: a placement is sold before anybody has the picture to hand, so the grant goes
// through and **the answer asks for the photo**. The panel has nothing else to go on — a card with
// an empty frame is only visible from the home screen.
func TestGrantingVIPAsksForThePhotoWhenTheShopHasNone(t *testing.T) {
	admin, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "VipSeller", "admin")
	shopID := makeSeededShop(t, ctx, tx, q, "Unphotographed", catalog.CategoryWood, false)
	target := "/api/admin/shops/" + strconv.FormatInt(shopID, 10) + "/vip"

	var granted struct {
		IsVIP      bool `json:"is_vip"`
		NeedsPhoto bool `json:"needs_photo"`
	}
	rec := requestAdminBody(t, ctx, admin, http.MethodPut, target, adminID, `{"days":30}`, admin.SetVIP)
	if rec.Code != http.StatusOK {
		t.Fatalf("grant = %d (%s)", rec.Code, rec.Body.String())
	}
	decodeBody(t, rec, &granted)
	if !granted.IsVIP {
		t.Fatal("the grant was refused for a missing photo - it must go through and ask")
	}
	if !granted.NeedsPhoto {
		t.Error("a placement with no storefront did not ask for one, so nothing in the panel would")
	}

	if _, err := q.SetShopImage(ctx, db.SetShopImageParams{
		ID:        shopID,
		ImagePath: pgtype.Text{String: "shops/uploads/ab/abcdef.jpg", Valid: true},
	}); err != nil {
		t.Fatalf("give the shop a photo: %v", err)
	}

	rec = requestAdminBody(t, ctx, admin, http.MethodPut, target, adminID, `{"days":30}`, admin.SetVIP)
	decodeBody(t, rec, &granted)
	if granted.NeedsPhoto {
		t.Error("a photographed shop is still being asked for a photo")
	}

	// revoking is not a reason to ask for anything: there is no card to fill
	rec = requestAdminBody(t, ctx, admin, http.MethodPut, target, adminID, `{"days":0}`, admin.SetVIP)
	decodeBody(t, rec, &granted)
	if granted.IsVIP || granted.NeedsPhoto {
		t.Errorf("after a revoke: is_vip=%v needs_photo=%v", granted.IsVIP, granted.NeedsPhoto)
	}
}

// the panel decides whether to nag from the shop list, so the thumbnail has to be on that row -
// built here, because only the server knows whether photos come from this api or another host
func TestTheShopListCarriesTheStorefrontThumbnail(t *testing.T) {
	admin, ctx, tx, q := adminUnderTest(t)

	adminID := makeUser(t, ctx, q, "Lister", "admin")
	shopID := makeSeededShop(t, ctx, tx, q, "Listed", catalog.CategoryUniversal, true)
	if _, err := q.SetShopImage(ctx, db.SetShopImageParams{
		ID:        shopID,
		ImagePath: pgtype.Text{String: "shops/uploads/ab/abcdef.jpg", Valid: true},
	}); err != nil {
		t.Fatalf("give the shop a photo: %v", err)
	}

	rec := requestAdmin(t, ctx, admin, http.MethodGet, "/api/admin/shops", adminID, admin.ListShops)
	if rec.Code != http.StatusOK {
		t.Fatalf("shops = %d (%s)", rec.Code, rec.Body.String())
	}
	var listed struct {
		Shops []adminShopResponse `json:"shops"`
	}
	decodeBody(t, rec, &listed)

	for _, shop := range listed.Shops {
		if shop.ID != shopID {
			continue
		}
		if !strings.HasSuffix(shop.ImageThumbURL, "/shops/uploads/ab/abcdef_thumb.jpg") {
			t.Errorf("image_thumb_url = %q, want the thumbnail beside the stored master", shop.ImageThumbURL)
		}
		return
	}
	t.Fatalf("shop %d is not in the list of %d", shopID, len(listed.Shops))
}
