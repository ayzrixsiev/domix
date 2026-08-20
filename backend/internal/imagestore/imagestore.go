// package imagestore owns the one directory owner-uploaded product photos are written to, and the
// step that turns whatever a phone sent into a file this api is willing to serve.
//
// **The curated catalogue photos and these are different things sharing one directory tree.** The
// shots under photos/<shop category>/ were taken by the founder, are checked into the project, and
// are shared by every shop seeded from the same template - migration 000014's product_templates
// points at them by path. What this package writes belongs to exactly one products row. Both are
// served by the same static handler off the same root, so a stored image_path can be either, and
// [UploadDir] is what tells them apart: [Store.Remove] refuses everything outside it, which is the
// line that stops "replace my photo" from unlinking a file forty other shops still draw.
//
// Nothing here touches the database. The handler owns the ordering - write the file, then point the
// row at it, then unlink whatever the row pointed at before - because that ordering is what decides
// whether a failure leaves an orphaned file (harmless, a few hundred kilobytes) or a row pointing at
// a file that does not exist (a broken tile in every grid the product appears in).
package imagestore

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// UploadDir is the subdirectory of the served images root that uploads live in, and therefore the
// prefix every owner-uploaded products.image_path starts with. Forward slashes throughout: this
// value goes into a database column and into a url, not only onto a disk.
const UploadDir = "uploads"

const (
	// MaxUploadBytes is the most this will read off the network for one photo. It is a ceiling on a
	// request, not on the stored file - Normalize re-encodes to roughly 100-200 KB whatever arrives
	// - and it exists so a decode is never attempted on something arbitrarily large.
	//
	// 6 MiB is above a 12-megapixel phone photo at full quality and well below anything that could
	// be called a bulk upload. The app resizes before sending (image_picker's maxWidth), so a
	// request anywhere near this is either a different client or a mistake.
	MaxUploadBytes = 6 << 20

	filePerm = 0o644
	dirPerm  = 0o755
)

// ErrOutsideUploads is what Remove answers for a path that is not one of ours - a curated catalogue
// photo, or anything with a .. in it. It is a programming error rather than a user one, so it is
// returned loudly instead of being skipped quietly.
var ErrOutsideUploads = errors.New("imagestore: refusing to delete a path outside the uploads directory")

// Store writes into `root`/uploads, where root is the same directory the api serves
// /static/products/ from (PRODUCT_IMAGES_DIR).
type Store struct {
	root string
}

// New makes sure the uploads directory exists and hands back a store writing into it.
//
// Creating it at startup rather than lazily on the first upload is deliberate: a directory the
// process cannot create is a misconfigured deployment, and finding that out when the first shop
// owner presses "добавить фото" means finding out from them.
func New(root string) (*Store, error) {
	dir := filepath.Join(root, UploadDir)
	if err := os.MkdirAll(dir, dirPerm); err != nil {
		return nil, fmt.Errorf("imagestore: cannot create %q: %w", dir, err)
	}
	return &Store{root: root}, nil
}

// Dir is the absolute-or-relative path uploads are written under. For logging at startup.
func (s *Store) Dir() string { return filepath.Join(s.root, UploadDir) }

// Save writes one already-normalized JPEG and returns the path to store in products.image_path,
// e.g. "uploads/3f/3f9c...c1.jpg".
//
// **The name is random rather than derived from the product id, and that is a caching decision.**
// Every file under /static/products/ is served with `Cache-Control: immutable, max-age=1y` (see
// staticFiles in cmd/api/main.go), so a phone that has seen one url will not ask for it again this
// year. Reusing "product-42.jpg" for a replacement photo would leave every device that already
// loaded the old one showing it until the cache expired - a bug reported as "my new photo did not
// save" by someone whose photo saved perfectly. A new name is a new url, and the old file is
// unlinked separately once the row no longer points at it.
//
// The two-character shard keeps one flat directory from collecting every photo in the market. It
// costs nothing and is very hard to introduce later, once paths are in the database.
func (s *Store) Save(jpeg []byte) (string, error) {
	name, err := randomName()
	if err != nil {
		return "", err
	}

	rel := path.Join(UploadDir, name[:2], name+".jpg")
	full := filepath.Join(s.root, filepath.FromSlash(rel))

	if err := os.MkdirAll(filepath.Dir(full), dirPerm); err != nil {
		return "", fmt.Errorf("imagestore: cannot create %q: %w", filepath.Dir(full), err)
	}

	// written to a temp file in the *same* directory and renamed into place. rename is atomic
	// within one filesystem, so the static handler either does not see this path at all or sees a
	// complete file - never the half of it that had been flushed when the process was killed.
	tmp, err := os.CreateTemp(filepath.Dir(full), ".upload-*")
	if err != nil {
		return "", fmt.Errorf("imagestore: cannot create a temporary file: %w", err)
	}
	tmpName := tmp.Name()

	if _, err := tmp.Write(jpeg); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return "", fmt.Errorf("imagestore: writing %q: %w", tmpName, err)
	}
	if err := tmp.Chmod(filePerm); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return "", fmt.Errorf("imagestore: chmod %q: %w", tmpName, err)
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return "", fmt.Errorf("imagestore: closing %q: %w", tmpName, err)
	}
	if err := os.Rename(tmpName, full); err != nil {
		os.Remove(tmpName)
		return "", fmt.Errorf("imagestore: renaming into %q: %w", full, err)
	}

	return rel, nil
}

// Remove unlinks one uploaded file. A path that is already gone is a success: the caller is asking
// for a state ("this file is not on disk"), which is the same reason DeleteUser is :exec.
//
// It refuses anything outside [UploadDir]. Every caller has a products.image_path in hand, and that
// column holds catalogue photos too - so without this check, an owner clearing the photo on a
// seeded template row would delete the shared shot out from under every other shop of that category.
func (s *Store) Remove(rel string) error {
	if !IsUpload(rel) {
		return fmt.Errorf("%w: %q", ErrOutsideUploads, rel)
	}

	err := os.Remove(filepath.Join(s.root, filepath.FromSlash(path.Clean(rel))))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("imagestore: removing %q: %w", rel, err)
	}
	return nil
}

// IsUpload reports whether a stored image path is one of ours rather than a curated catalogue photo.
// The `..` check is what makes the prefix test meaningful: "uploads/../../etc/passwd" starts with
// the right nine characters and points somewhere else entirely.
func IsUpload(rel string) bool {
	if rel == "" || strings.Contains(rel, "..") {
		return false
	}
	return strings.HasPrefix(path.Clean(rel), UploadDir+"/")
}

// 16 bytes, spelled in hex. Long enough that guessing a url is not a way to enumerate the market's
// photos, which matters because the static handler has no authorization in front of it at all.
func randomName() (string, error) {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return "", fmt.Errorf("imagestore: no randomness available: %w", err)
	}
	return hex.EncodeToString(raw), nil
}
