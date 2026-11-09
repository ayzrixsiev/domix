package endpoints

// The orphan sweep, which is the only code in this service that deletes a file nobody asked it to
// delete. Three rules stand between it and somebody's live photo (see the section header in
// admin.go), and each of them fails silently: the sweep would report a tidy number and the damage
// would surface days later as blank tiles in a shop nobody was looking at.

import (
	"bytes"
	"context"
	"image"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
	"domix/backend/internal/imagestore"
)

// an Admin whose photo storage is a directory that disappears with the test
func sweepUnderTest(t *testing.T) (*Admin, string, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	admin, ctx, tx, q := adminUnderTest(t)

	root := t.TempDir()
	store, err := imagestore.NewDisk(root)
	if err != nil {
		t.Fatalf("imagestore.NewDisk: %v", err)
	}
	admin.Images = store
	return admin, root, ctx, tx, q
}

// puts a photo in storage and returns the master's relative path. `age` is how long ago it was
// written, which is the input rule 2 turns on.
func storePhoto(t *testing.T, ctx context.Context, admin *Admin, root string, age time.Duration) string {
	t.Helper()

	rel, err := admin.Images.Save(ctx, imagestore.Photo{Master: []byte("a photo"), Thumb: []byte("small")})
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	if age > 0 {
		when := time.Now().Add(-age)
		for _, path := range []string{rel, imagestore.ThumbPath(rel)} {
			full := filepath.Join(root, filepath.FromSlash(path))
			if err := os.Chtimes(full, when, when); err != nil {
				t.Fatalf("backdating %s: %v", path, err)
			}
		}
	}
	return rel
}

func exists(t *testing.T, root, rel string) bool {
	t.Helper()
	_, err := os.Stat(filepath.Join(root, filepath.FromSlash(rel)))
	return err == nil
}

// **Rules 2 and 3 together, and rule 3 would be a market-wide outage.** Only the master's path is in
// the database, so a sweep matching paths literally would find every `_thumb` unreferenced and blank
// every grid in the app on its first run, with the database perfectly consistent throughout.
//
// Rule 2 is the second half: a file written a moment ago is left alone whether or not anything points
// at it, because the window between "the file exists" and "the row exists" is one upload request.
func TestASweepKeepsThumbnailsAndAnythingWrittenRecently(t *testing.T) {
	admin, root, ctx, tx, q := sweepUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Uborka", catalog.CategoryUniversal, false)
	product := seededProductID(t, ctx, tx, shop, catalog.Template(string(catalog.CategoryUniversal))[0].Key)

	// referenced by a live row, and old enough that only rule 3 protects its thumbnail
	live := storePhoto(t, ctx, admin, root, 3*time.Hour)
	if _, err := q.SetProductImage(ctx, db.SetProductImageParams{
		ID:        product,
		ImagePath: pgtype.Text{String: live, Valid: true},
	}); err != nil {
		t.Fatalf("point the row at it: %v", err)
	}

	// nothing points at these two: one old enough to sweep, one written a minute ago
	dead := storePhoto(t, ctx, admin, root, 3*time.Hour)
	fresh := storePhoto(t, ctx, admin, root, time.Minute)

	owner := shopOwnerID(t, ctx, tx, shop)
	if _, err := q.AdminUpdateUser(ctx, db.AdminUpdateUserParams{ID: owner, Role: "admin"}); err != nil {
		t.Fatalf("promote the owner: %v", err)
	}

	// ── the scan first: it must count without changing anything
	rec := requestAdmin(t, ctx, admin, http.MethodGet, "/api/admin/storage/orphans", owner, admin.RouteOrphans)
	if rec.Code != http.StatusOK {
		t.Fatalf("scan: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var scan orphanReport
	decodeBody(t, rec, &scan)
	if scan.Files != 2 {
		t.Errorf("the scan found %d files to delete, expected the dead master and its thumbnail", scan.Files)
	}
	if scan.TooRecent != 2 {
		t.Errorf("%d files were held back as too recent, expected the two written a minute ago", scan.TooRecent)
	}
	if scan.TotalFiles != 6 {
		t.Errorf("the scan looked at %d files, expected three photos of two files each", scan.TotalFiles)
	}
	if !exists(t, root, dead) {
		t.Fatal("the scan deleted something - it must only count")
	}

	// ── then the sweep
	rec = requestAdmin(t, ctx, admin, http.MethodDelete, "/api/admin/storage/orphans", owner, admin.RouteOrphans)
	if rec.Code != http.StatusOK {
		t.Fatalf("sweep: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var swept orphanReport
	decodeBody(t, rec, &swept)
	if swept.Files != 2 || swept.Failed != 0 {
		t.Errorf("swept %d files with %d failures, expected 2 and 0", swept.Files, swept.Failed)
	}

	if !exists(t, root, live) {
		t.Error("the photo a product points at was deleted")
	}
	// the one that would have blanked every grid in the market
	if !exists(t, root, imagestore.ThumbPath(live)) {
		t.Error("the thumbnail of a live photo was deleted - a referenced master claims both files")
	}
	if !exists(t, root, fresh) || !exists(t, root, imagestore.ThumbPath(fresh)) {
		t.Error("a file written a minute ago was deleted - the one-hour floor is what covers an upload in flight")
	}
	if exists(t, root, dead) || exists(t, root, imagestore.ThumbPath(dead)) {
		t.Error("the orphaned photo is still there - nothing swept")
	}
}

// **The catalogue is not reachable from here, and that is a property rather than a check**: a sweep
// that walked the whole photo root would find every curated file unreferenced as an upload and delete
// the catalogue. The uploads sweep lists only uploads/ and RemoveFile refuses anything else.
func TestASweepCannotReachTheCuratedCatalogue(t *testing.T) {
	admin, root, ctx, tx, q := sweepUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Katalog", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	if _, err := q.AdminUpdateUser(ctx, db.AdminUpdateUserParams{ID: owner, Role: "admin"}); err != nil {
		t.Fatalf("promote the owner: %v", err)
	}

	// stand a catalogue shot and its thumbnail up in this test's own root, backdated well past the
	// floor so age is not what is protecting them
	shot := filepath.Join(root, "shops", "universal", "001.jpg")
	if err := os.MkdirAll(filepath.Dir(shot), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	long := time.Now().Add(-72 * time.Hour)
	for _, path := range []string{shot, filepath.Join(root, "shops", "universal", "001_thumb.jpg")} {
		if err := os.WriteFile(path, []byte("the catalogue photo"), 0o644); err != nil {
			t.Fatalf("write: %v", err)
		}
		if err := os.Chtimes(path, long, long); err != nil {
			t.Fatalf("backdating: %v", err)
		}
	}

	rec := requestAdmin(t, ctx, admin, http.MethodDelete, "/api/admin/storage/orphans", owner, admin.RouteOrphans)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var swept orphanReport
	decodeBody(t, rec, &swept)
	if swept.TotalFiles != 0 {
		t.Errorf("the sweep looked at %d files, expected none - the catalogue is outside uploads/", swept.TotalFiles)
	}
	if _, err := os.Stat(shot); err != nil {
		t.Fatalf("the shared catalogue photo was deleted: %v", err)
	}
}

// writes one curated file (master or thumbnail) under the test's root, backdated past the floor
func storeCatalogueFile(t *testing.T, root, rel string) {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(full, []byte("a catalogue photo"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}
	long := time.Now().Add(-72 * time.Hour)
	if err := os.Chtimes(full, long, long); err != nil {
		t.Fatalf("backdating: %v", err)
	}
}

// The catalogue sweep exists because several sizes of one product now share a photo, which leaves
// the files they used to name drawn by nobody. **What it must never take is a file some row still
// points at** - a template row, or a shop's own copy seeded before the template's photo changed - and
// it must leave owner uploads to the other door even though they live under the same root.
func TestTheCatalogueSweepTakesOnlyWhatNothingDraws(t *testing.T) {
	admin, root, ctx, tx, q := sweepUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Sizes", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	if _, err := q.AdminUpdateUser(ctx, db.AdminUpdateUserParams{ID: owner, Role: "admin"}); err != nil {
		t.Fatalf("promote the owner: %v", err)
	}

	// what the seeded shop draws, whatever the template's first row is today
	live := catalog.Template(string(catalog.CategoryUniversal))[0].ImagePath
	if live == "" {
		t.Fatal("the universal template's first row has no photo, so there is nothing referenced to protect")
	}
	unused := "shops/universal/zz-unused-by-anything.jpg"
	for _, rel := range []string{live, imagestore.ThumbPath(live), unused, imagestore.ThumbPath(unused)} {
		storeCatalogueFile(t, root, rel)
	}
	// an orphaned owner upload: the other sweep's business, never this one's
	upload := storePhoto(t, ctx, admin, root, 3*time.Hour)

	// ── the scan lists the unused pair and offers the picker every master
	rec := requestAdmin(t, ctx, admin, http.MethodGet, "/api/admin/storage/catalogue", owner, admin.RouteCatalogueFiles)
	if rec.Code != http.StatusOK {
		t.Fatalf("scan: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var scan orphanReport
	decodeBody(t, rec, &scan)
	if scan.Files != 2 {
		t.Errorf("the scan found %d files to delete, expected the unused master and its thumbnail: %v", scan.Files, scan.Paths)
	}
	if scan.TotalFiles != 4 {
		t.Errorf("the scan looked at %d files, expected the four curated ones and not the upload", scan.TotalFiles)
	}
	used := map[string]bool{}
	for _, file := range scan.Catalogue {
		used[file.Path] = file.Used
	}
	if len(used) != 2 || !used[live] || used[unused] {
		t.Errorf("the picker list is %v, expected two masters with only %q in use", scan.Catalogue, live)
	}

	// ── the sweep
	rec = requestAdmin(t, ctx, admin, http.MethodDelete, "/api/admin/storage/catalogue", owner, admin.RouteCatalogueFiles)
	if rec.Code != http.StatusOK {
		t.Fatalf("sweep: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var swept orphanReport
	decodeBody(t, rec, &swept)
	if swept.Files != 2 || swept.Failed != 0 {
		t.Errorf("swept %d files with %d failures, expected 2 and 0", swept.Files, swept.Failed)
	}

	if !exists(t, root, live) || !exists(t, root, imagestore.ThumbPath(live)) {
		t.Error("a catalogue photo a row points at was deleted - every shop of the category draws it")
	}
	if exists(t, root, unused) || exists(t, root, imagestore.ThumbPath(unused)) {
		t.Error("the unused catalogue photo is still there - nothing swept")
	}
	if !exists(t, root, upload) {
		t.Error("the catalogue sweep deleted an owner upload - that is the other door's file")
	}
}

// ─────────────────── adding a photo to the catalogue ───────────────────

// POSTs one photo to /api/admin/catalogue/{category}/photo through the real middleware chain
func callCatalogueUpload(
	t *testing.T, ctx context.Context, a *Admin, category string, asUserID int64, photo []byte,
) *httptest.ResponseRecorder {
	t.Helper()

	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	part, err := form.CreateFormFile("image", "shot.jpg")
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

	req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/api/admin/catalogue/"+category+"/photo", &body)
	req.SetPathValue("category", category)
	req.Header.Set("Content-Type", form.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, a.Queries, a.RequireAdmin(a.UploadCataloguePhoto))(rec, req)
	return rec
}

// **the cycle this endpoint replaced was a person converting a file by hand and copying it into
// images/**, so what matters is that the panel's photo is the same kind of file an owner's upload is:
// two JPEGs, re-encoded, in the category's own folder - and that the picker can see it straight
// away, because the scan that feeds the picker is the same walk the sweep uses.
func TestACataloguePhotoUploadedFromThePanelIsTwoFilesThePickerCanSee(t *testing.T) {
	admin, root, ctx, _, q := sweepUnderTest(t)
	adminID := makeUser(t, ctx, q, "Shooter", "admin")

	rec := callCatalogueUpload(t, ctx, admin, "universal", adminID, testPhoto(t, 1400, 900))
	if rec.Code != http.StatusOK {
		t.Fatalf("upload = %d (%s), want 200", rec.Code, rec.Body.String())
	}
	var saved catalogueFile
	decodeBody(t, rec, &saved)

	if !imagestore.IsCatalogue(saved.Path) {
		t.Fatalf("stored at %q, which IsCatalogue does not recognise", saved.Path)
	}
	if want := "shops/universal/"; !strings.HasPrefix(saved.Path, want) {
		t.Errorf("stored at %q, want it under %s", saved.Path, want)
	}
	if !exists(t, root, saved.Path) {
		t.Errorf("the master is not on disk")
	}
	if !exists(t, root, imagestore.ThumbPath(saved.Path)) {
		t.Errorf("the thumbnail beside it is not on disk")
	}
	if saved.Used {
		t.Errorf("a file nothing points at yet came back as used")
	}

	// re-encoded rather than stored as sent: the master is bounded and the thumbnail is the smaller
	// of the pair, which is the whole reason two files are written
	master, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(saved.Path)))
	if err != nil {
		t.Fatalf("read the master: %v", err)
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(master))
	if err != nil || format != "jpeg" {
		t.Fatalf("the stored master is not a jpeg: %v (%s)", err, format)
	}
	if cfg.Width != imagestore.OutputMaxSide {
		t.Errorf("the master is %dpx wide, want %d", cfg.Width, imagestore.OutputMaxSide)
	}
	thumb, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(imagestore.ThumbPath(saved.Path))))
	if err != nil {
		t.Fatalf("read the thumbnail: %v", err)
	}
	if len(thumb) >= len(master) {
		t.Errorf("the thumbnail is %d bytes against the master's %d", len(thumb), len(master))
	}

	// **the picker's list is the catalogue scan**, so a photo that did not show up here would be one
	// the founder could upload and then not be able to choose
	scan := requestAdmin(t, ctx, admin, http.MethodGet, "/api/admin/storage/catalogue", adminID, admin.RouteCatalogueFiles)
	if scan.Code != http.StatusOK {
		t.Fatalf("catalogue scan = %d (%s)", scan.Code, scan.Body.String())
	}
	var report orphanReport
	decodeBody(t, scan, &report)
	listed := false
	for _, file := range report.Catalogue {
		if file.Path == saved.Path {
			listed = true
			if file.Used {
				t.Errorf("the new file is listed as used, so the picker would not mark it free")
			}
		}
	}
	if !listed {
		t.Errorf("the uploaded photo is not in the picker's list of %d files", len(report.Catalogue))
	}
	// and it survives the sweep that runs on the same scan: it was written a moment ago
	if report.Files != 0 {
		t.Errorf("the sweep would take %d files, including one uploaded seconds ago", report.Files)
	}
}

// **the one category with nothing to photograph.** An обои row names a *kind* of wallpaper; the
// product is the roll standing in one shop, and the owner's right to photograph it is granted by
// the template having no photo. One picture uploaded here would take that right away from every
// обои shop at once, so the upload is refused before a byte is read.
func TestTheCatalogueRefusesAPhotoForACategoryWhoseProductsAreTheOwners(t *testing.T) {
	admin, root, ctx, _, q := sweepUnderTest(t)
	adminID := makeUser(t, ctx, q, "Shooter", "admin")

	rec := callCatalogueUpload(t, ctx, admin, string(catalog.CategoryWallpaper), adminID, testPhoto(t, 800, 800))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("upload = %d (%s), want 400", rec.Code, rec.Body.String())
	}
	var body map[string]string
	decodeBody(t, rec, &body)
	if body["code"] != "owner_named_photo" {
		t.Errorf("code = %q, want owner_named_photo", body["code"])
	}

	files, err := admin.Images.List(ctx, imagestore.CatalogueRoot)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(files) != 0 {
		t.Errorf("%d files were written under %s anyway", len(files), root)
	}
}

// a logged-in shop owner holds a perfectly valid token, and this endpoint writes into the catalogue
// every shop of a market draws from
func TestOnlyAnAdminAddsToTheCatalogue(t *testing.T) {
	admin, _, ctx, _, q := sweepUnderTest(t)
	ownerID := makeUser(t, ctx, q, "Owner", "shop_owner")

	rec := callCatalogueUpload(t, ctx, admin, "universal", ownerID, testPhoto(t, 800, 800))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("upload as a shop owner = %d, want 403", rec.Code)
	}
}
