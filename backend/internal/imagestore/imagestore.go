// package imagestore owns where a product photo lives: the bytes, the paths, and the addresses
// those paths are served from.
//
// **curated catalogue photos and owner uploads share one namespace.** the shots under
// photos/<category>/ are checked into the project and shared by every shop seeded from that
// template; what a [Storage] writes belongs to exactly one products row. both land in
// products.image_path, and [UploadDir] is what tells them apart - every deletion here refuses
// anything outside it, which is what stops "replace my photo" unlinking a file forty shops draw.
//
// nothing here touches the database: the handler owns the ordering, which is what decides whether a
// failure leaves a harmless orphan file or a row pointing at a file that does not exist.
package imagestore

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"path"
	"strings"
	"time"
)

// the prefix every owner-uploaded products.image_path starts with. forward slashes throughout: this
// goes into a database column, a url and an S3 object key, not only onto a disk.
//
// under `shops/` with the curated catalogue, so the images root has room for a second kind of image
// without either of them moving again.
const UploadDir = "shops/uploads"

// the most that will be read off the network for one photo - a ceiling on the request, not on the
// stored file, which [Normalize] re-encodes to 100-200 KB. above a full-quality 12MP phone photo,
// and the app resizes before sending anyway.
const MaxUploadBytes = 6 << 20

// what a deletion answers for a path that is not ours - a catalogue photo, or anything with a .. in
// it. a programming error rather than a user one, so it is loud rather than skipped quietly.
var ErrOutsideUploads = errors.New("imagestore: refusing to delete a path outside the uploads directory")

// one accepted upload in the two sizes that get stored. a pair rather than two arguments because
// **the two files are one fact**: a signature that let a caller store a master without its thumbnail
// would eventually be called that way, leaving a blank grid tile on every phone in the market.
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

// where product photos are kept. two implementations, both used every day, which is what makes the
// interface worth having: [Disk] runs on the laptop and in every test, [R2] runs in production, and
// main.go picks by whether the R2 keys are in the environment.
type Storage interface {
	// writes both files and returns the *master's* relative path, which is what goes into
	// products.image_path - the thumbnail's is not stored anywhere, it is [ThumbPath] of this one
	Save(ctx context.Context, photo Photo) (string, error)

	// unlinks a master and its thumbnail. a file already gone is a success; anything outside
	// [UploadDir] is [ErrOutsideUploads].
	Remove(ctx context.Context, rel string) error

	// every file under [UploadDir]. only the orphan sweep calls it.
	List(ctx context.Context) ([]Object, error)

	// exactly one file, assuming nothing about its partner - the sweep collects stray thumbnails
	// whose master is already gone, which [Remove] would refuse to handle
	RemoveFile(ctx context.Context, rel string) error

	// where photos are going, for one line in the startup log
	Describe() string
}

// "uploads/3f/3f9c.jpg" pairs with "uploads/3f/3f9c_thumb.jpg". **the app is never told this rule**:
// a build that appended "_thumb" itself would freeze the convention inside every apk on a phone.
const thumbSuffix = "_thumb"

// the thumbnail beside a stored master. it applies to curated catalogue paths too, which is not
// incidental: the catalogue is what most tiles in most grids show.
func ThumbPath(rel string) string {
	ext := path.Ext(rel)
	return strings.TrimSuffix(rel, ext) + thumbSuffix + ext
}

// whether a stored path is an owner upload rather than a curated catalogue photo. the `..` check is
// what makes the prefix test mean anything: "uploads/../../etc/passwd" starts with the right nine
// characters and points somewhere else entirely.
func IsUpload(rel string) bool {
	if rel == "" || strings.Contains(rel, "..") {
		return false
	}
	return strings.HasPrefix(path.Clean(rel), UploadDir+"/")
}

// where images are served from when nothing says otherwise: this api's own disk, the laptop and tests
const DefaultURLPrefix = "/images/"

// turns a stored relative path into the addresses the app fetches it from.
//
// **the database stores a relative path and never a full url**: the host differs between the tunnel,
// a laptop and img.domix-api.uz, so a stored absolute url would have to be rewritten row by row the
// day it changes - and a production dump would point every local tile at production.
//
// the zero value serves from this api's own /images/, so every test behaves as before.
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

// **random rather than derived from the product id, and that is a caching decision**: photos are
// served immutable for a year, so reusing "product-42.jpg" would leave every device that loaded the
// old one showing it - reported as "my new photo did not save". a new name is a new url.
//
// long enough that guessing one is not a way to enumerate the market's photos.
func randomName() (string, error) {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return "", errors.New("imagestore: no randomness available: " + err.Error())
	}
	return hex.EncodeToString(raw), nil
}

// the two paths one saved photo occupies, under a two-character shard so no single directory
// collects every photo in the market. identical on disk and in an R2 object key, which is what lets
// a database dump move between the two backends.
func newPaths() (master, thumb string, err error) {
	name, err := randomName()
	if err != nil {
		return "", "", err
	}
	master = path.Join(UploadDir, name[:2], name+".jpg")
	return master, ThumbPath(master), nil
}
