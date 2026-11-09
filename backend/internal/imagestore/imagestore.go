// package imagestore owns where a product photo lives: the bytes, the paths, and the addresses those
// paths are served from.
//
// **curated catalogue photos and owner uploads share one namespace** - both land in products.image_path,
// and [UploadDir] is what tells them apart. every deletion here refuses anything outside its own door,
// which is what stops "replace my photo" unlinking a file forty shops draw.
//
// nothing here touches the database: the handler owns the ordering, which is what decides whether a
// failure leaves a harmless orphan or a row pointing at a file that does not exist.
package imagestore

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"path"
	"strings"
	"time"
)

// the prefix every owner-uploaded products.image_path starts with. forward slashes throughout: this goes
// into a database column, a url and an S3 object key, not only onto a disk.
const UploadDir = "shops/uploads"

// the curated catalogue: `shops/<shop category>/<file>`, one photo shared by every shop seeded from that
// template. [UploadDir] sits under the same root, which is what [IsCatalogue] has to exclude.
const CatalogueRoot = "shops"

// the most that will be read off the network for one photo - a ceiling on the request, not on the stored
// file, which [Normalize] re-encodes to 100-200 KB.
const MaxUploadBytes = 6 << 20

// what a deletion answers for a path that is not ours. a programming error, so it is loud rather than skipped.
var ErrOutsideUploads = errors.New("imagestore: refusing to delete a path outside the uploads directory")

// what a catalogue deletion answers for anything that is not shaped like a curated photo
var ErrOutsideCatalogue = errors.New("imagestore: refusing to delete a path outside the curated catalogue")

// one accepted upload in the two sizes that get stored. a pair rather than two arguments because **the two
// files are one fact**: a master stored without its thumbnail is a blank grid tile on every phone.
type Photo struct {
	// the 1000px copy, what the edit screen and any full-size view load
	Master []byte
	// the 400px copy a catalogue grid loads - ~99% of all image traffic is this file
	Thumb []byte
}

// one stored file as the orphan sweep sees it. Modified is what rule 2 of that sweep rests on: a
// file younger than an hour may belong to a row that is still being written.
type Object struct {
	// relative, forward-slashed, exactly as it appears in products.image_path
	Path     string
	Size     int64
	Modified time.Time
}

// "uploads/3f/3f9c.jpg" pairs with "uploads/3f/3f9c_thumb.jpg". **the app is never told this rule**:
// a build that appended "_thumb" itself would freeze the convention inside every apk on a phone.
const thumbSuffix = "_thumb"

// the thumbnail beside a stored master. it applies to curated paths too, which is what most grids show.
func ThumbPath(rel string) string {
	ext := path.Ext(rel)
	return strings.TrimSuffix(rel, ext) + thumbSuffix + ext
}

// whether a stored path is an owner upload rather than a curated photo. the `..` check is what makes the
// prefix test mean anything: "uploads/../../etc/passwd" starts with the right characters.
func IsUpload(rel string) bool {
	if rel == "" || strings.Contains(rel, "..") {
		return false
	}
	return strings.HasPrefix(path.Clean(rel), UploadDir+"/")
}

// whether a stored path is a curated catalogue photo: `shops/<category>/<file>`, three segments, and
// not the uploads directory. the `..` check is what makes the prefix test mean anything.
func IsCatalogue(rel string) bool {
	if rel == "" || strings.Contains(rel, "..") || IsUpload(rel) {
		return false
	}
	parts := strings.Split(path.Clean(rel), "/")
	return len(parts) == 3 && parts[0] == CatalogueRoot && parts[1] != "" && parts[2] != ""
}

// where images are served from when nothing says otherwise: this api's own disk, the laptop and tests
const DefaultURLPrefix = "/images/"

// turns a stored relative path into the addresses the app fetches it from.
//
// **the database stores a relative path and never a full url**: the host differs between the tunnel, a
// laptop and the server, and a production dump would otherwise point every local tile at production.
// the zero value serves from this api's own /images/.
type URLs struct {
	// "" means DefaultURLPrefix; otherwise an absolute origin with no trailing slash
	base string
}

// an empty base - IMAGE_BASE_URL unset - serves from this api's own /images/
func NewURLs(base string) URLs {
	return URLs{base: strings.TrimSuffix(strings.TrimSpace(base), "/")}
}

// for the startup log, and for main.go's refusal to run R2 without one
func (u URLs) Configured() bool { return u.base != "" }

// the full-size copy: the edit screen's photo field, and anything showing one product alone
func (u URLs) Master(rel string) string {
	if u.base == "" {
		return DefaultURLPrefix + rel
	}
	return u.base + "/" + rel
}

// the 400px copy: every catalogue grid
func (u URLs) Thumb(rel string) string { return u.Master(ThumbPath(rel)) }

// **random rather than derived from the product id, and that is a caching decision**: photos are served
// immutable for a year, so reusing a name leaves every device that cached it showing the old photo.
func randomName() (string, error) {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return "", errors.New("imagestore: no randomness available: " + err.Error())
	}
	return hex.EncodeToString(raw), nil
}

// the two paths one saved photo occupies, under a two-character shard so no single directory collects
// every photo in the market. identical on disk and as an R2 object key.
func newPaths() (master, thumb string, err error) {
	name, err := randomName()
	if err != nil {
		return "", "", err
	}
	master = path.Join(UploadDir, name[:2], name+".jpg")
	return master, ThumbPath(master), nil
}

// the same for a curated photo: `shops/<category>/<random>.jpg`, flat because [IsCatalogue] is exactly
// three segments. **the name is random here too, and for a stronger reason**: a replaced catalogue shot
// is drawn by every shop of the market. the [IsCatalogue] check turns a category of "../uploads" into
// an error instead of a write.
func newCataloguePaths(category string) (master, thumb string, err error) {
	name, err := randomName()
	if err != nil {
		return "", "", err
	}
	master = path.Join(CatalogueRoot, category, name+".jpg")
	if !IsCatalogue(master) {
		return "", "", fmt.Errorf("%w: %q", ErrOutsideCatalogue, master)
	}
	return master, ThumbPath(master), nil
}
