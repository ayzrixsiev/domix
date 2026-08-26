package endpoints

// The orphan sweep, which is the only code in this service that deletes a file nobody asked it to
// delete. Three rules stand between it and somebody's live photo (see the section header in
// admin.go), and each of them fails silently: the sweep would report a tidy number and the damage
// would surface days later as blank tiles in a shop nobody was looking at.

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
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

// **Rules 2 and 3 together, and rule 3 is the one that would have been a market-wide outage.**
//
// Only the master's path is in the database - the thumbnail's is derived - so a sweep that matched
// paths literally would find every `_thumb` file unreferenced and delete the thumbnail of every
// product in every shop on its first run. Every grid in the app would go blank at once, and the
// database would be perfectly consistent throughout.
//
// Rule 2 is the second half of this test: a file written a moment ago is left alone whether or not
// anything points at it, because the window between "the file exists" and "the row exists" is one
// upload request long.
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

// **The catalogue is not reachable from here, and that is a property rather than a check.** A
// curated shot is one file every shop of a category draws, and no products row will ever name it as
// an upload - so a sweep that walked the whole photo root would find all 200 of them unreferenced by
// its own test and delete the entire catalogue. What stops it is that List only walks uploads/ and
// RemoveFile refuses anything else.
func TestASweepCannotReachTheCuratedCatalogue(t *testing.T) {
	admin, root, ctx, tx, q := sweepUnderTest(t)

	shop := makeSeededShop(t, ctx, tx, q, "Katalog", catalog.CategoryUniversal, false)
	owner := shopOwnerID(t, ctx, tx, shop)
	if _, err := q.AdminUpdateUser(ctx, db.AdminUpdateUserParams{ID: owner, Role: "admin"}); err != nil {
		t.Fatalf("promote the owner: %v", err)
	}

	// stand a catalogue shot and its thumbnail up in this test's own root, backdated well past the
	// floor so age is not what is protecting them
	shot := filepath.Join(root, "universal", "001.jpg")
	if err := os.MkdirAll(filepath.Dir(shot), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	long := time.Now().Add(-72 * time.Hour)
	for _, path := range []string{shot, filepath.Join(root, "universal", "001_thumb.jpg")} {
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
