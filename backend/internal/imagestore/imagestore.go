// package imagestore owns everything about where a product photo lives: the bytes that get stored,
// the paths they are stored under, and the addresses those paths are served from.
//
// **The curated catalogue photos and owner uploads are different things sharing one namespace.**
// The shots under photos/<shop category>/ were taken by the founder, are checked into the project,
// and are shared by every shop seeded from the same template - product_templates points at them by
// path. What a [Storage] writes belongs to exactly one products row. Both end up in the same
// products.image_path column, so a stored path can be either, and [UploadDir] is what tells them
// apart: every deletion path here refuses anything outside it, which is the line that stops
// "replace my photo" from unlinking a file forty other shops still draw.
//
// Nothing here touches the database. The handler owns the ordering - write the files, then point
// the row at them, then unlink whatever the row pointed at before - because that ordering is what
// decides whether a failure leaves an orphaned file (harmless, a few hundred kilobytes, and
// sweepable from the admin panel) or a row pointing at a file that does not exist (a broken tile in
// every grid the product appears in).
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

// UploadDir is the subdirectory of the served images namespace that uploads live in, and therefore
// the prefix every owner-uploaded products.image_path starts with. Forward slashes throughout: this
// value goes into a database column, into a url and into an S3 object key, not only onto a disk.
const UploadDir = "uploads"

// MaxUploadBytes is the most that will be read off the network for one photo. It is a ceiling on a
// request, not on the stored file - [Normalize] re-encodes to roughly 100-200 KB whatever arrives -
// and it exists so a decode is never attempted on something arbitrarily large.
//
// 6 MiB is above a 12-megapixel phone photo at full quality and well below anything that could be
// called a bulk upload. The app resizes before sending (image_picker's maxWidth), so a request
// anywhere near this is either a different client or a mistake.
const MaxUploadBytes = 6 << 20

// ErrOutsideUploads is what a deletion answers for a path that is not one of ours - a curated
// catalogue photo, or anything with a .. in it. It is a programming error rather than a user one, so
// it is returned loudly instead of being skipped quietly.
var ErrOutsideUploads = errors.New("imagestore: refusing to delete a path outside the uploads directory")

// Photo is one accepted upload in the two sizes that get stored. [Normalize] produces it and
// [Storage.Save] consumes it, and it is a pair rather than two arguments for the reason
// endpoints.productImage returns its fields together: **the two files are one fact**, and a
// signature that let a caller store a master without its thumbnail would eventually be called that
// way - leaving a row whose grid tile is blank on every phone in the market.
type Photo struct {
	// the 1000px copy, the one the edit screen and any full-size view load
	Master []byte
	// the 400px copy, the one a catalogue grid loads. ~99% of all image traffic is this file.
	Thumb []byte
}

// Object is one stored file as the orphan sweep sees it: what it is called, what it weighs, and
// when it was written. Modified is the field rule 2 of the sweep rests on - a file younger than an
// hour is never deleted, because it may belong to a row that is still being written.
type Object struct {
	// relative, forward-slashed, exactly as it would appear in products.image_path
	Path     string
	Size     int64
	Modified time.Time
}

// Storage is where product photos are kept. Two implementations, both used every day, which is what
// makes the abstraction worth having rather than architecture for its own sake: [Disk] is what runs
// on the founder's laptop and in every test - no network, no credentials, no account - and [R2] is
// what runs in production. main.go picks between them by whether the R2 keys are in the environment.
//
// Every method takes a context because one implementation talks over the network; [Disk] ignores it.
//
// The last two methods exist only for the admin panel's orphan sweep (uploads whose products row
// went away with a deleted shop). They are on the same interface rather than a second one because
// both implementations satisfy both halves, and a second interface would mean a type assertion in
// main.go that could fail at runtime for no gain.
type Storage interface {
	// Save writes one photo - both files - and returns the *master's* relative path, which is what
	// goes into products.image_path. The thumbnail's path is not returned because it is not stored
	// anywhere: it is [ThumbPath] of this one.
	Save(ctx context.Context, photo Photo) (string, error)

	// Remove unlinks one photo: the master named by rel and its thumbnail. A file that is already
	// gone is a success - the caller is asking for a state, which is the same reason DeleteUser is
	// :exec. Refuses anything outside [UploadDir] with [ErrOutsideUploads].
	Remove(ctx context.Context, rel string) error

	// List returns every file under [UploadDir]. Only the sweep calls it.
	List(ctx context.Context) ([]Object, error)

	// RemoveFile unlinks exactly one file, master or thumbnail, without assuming anything about the
	// other. The sweep needs this and [Remove] will not do: a stray thumbnail whose master is
	// already gone is one of the things being swept, and Remove would go looking for a partner that
	// does not exist. Refuses anything outside [UploadDir].
	RemoveFile(ctx context.Context, rel string) error

	// Describe names where photos are going, for one line in the startup log. The single most
	// useful thing to see when photos are not appearing is which of the two is in use.
	Describe() string
}

// thumbSuffix goes before the extension, so "uploads/3f/3f9c.jpg" pairs with
// "uploads/3f/3f9c_thumb.jpg". Kept next to [ThumbPath] and declared nowhere else - **the app is
// deliberately never told this rule.** ProductResponse sends both urls ready-made, because a Flutter
// build that appended "_thumb" itself would freeze the convention inside every apk already on a
// phone, and changing it would then mean a release in Play rather than a deploy.
const thumbSuffix = "_thumb"

// ThumbPath is the thumbnail beside a stored master. One declaration, used by both implementations
// when they write and delete, by the url builder when it answers a request, and by the sweep when it
// decides that a referenced master claims its thumbnail too.
//
// It applies to curated catalogue paths as well ("universal/001.jpg" -> "universal/001_thumb.jpg"),
// which is not incidental: the catalogue is what most tiles in most grids actually show, so without
// thumbnails beside those files the saving barely happens.
func ThumbPath(rel string) string {
	ext := path.Ext(rel)
	return strings.TrimSuffix(rel, ext) + thumbSuffix + ext
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

// DefaultURLPrefix is where the api serves photos from when nothing says otherwise: off its own
// disk, through staticFiles in cmd/api/main.go. This is the laptop and the test suite.
const DefaultURLPrefix = "/static/products/"

// URLs turns a stored relative path into the addresses the app fetches it from.
//
// **The database stores a relative path and never a full url**, and IMAGE_BASE_URL is why that rule
// gets stronger rather than weaker in production: the host differs between the ngrok tunnel, a
// laptop and img.domix-api.uz, so a column holding "https://img.domix-api.uz/uploads/3f/3f9c.jpg"
// would have to be rewritten row by row the day the host changes - and a dump taken from production
// would point every local tile at production.
//
// The zero value is the default: relative urls off this api's own /static/products/. That is
// deliberate, because it means every test and every struct literal that does not mention photos
// behaves exactly as it did before this existed.
type URLs struct {
	// "" means DefaultURLPrefix. Otherwise an absolute origin with no trailing slash.
	base string
}

// NewURLs reads the configured image host. An empty base - IMAGE_BASE_URL unset, which is the
// laptop and the test suite - serves from this api's own /static/products/.
func NewURLs(base string) URLs {
	return URLs{base: strings.TrimSuffix(strings.TrimSpace(base), "/")}
}

// Configured reports whether an image host was set, for the startup log and for main.go's refusal to
// run R2 without one.
func (u URLs) Configured() bool { return u.base != "" }

// Master is the address of the full-size copy: the edit screen's photo field, and anything showing
// one product on its own.
func (u URLs) Master(rel string) string {
	if u.base == "" {
		return DefaultURLPrefix + rel
	}
	return u.base + "/" + rel
}

// Thumb is the address of the 400px copy: every catalogue grid.
func (u URLs) Thumb(rel string) string { return u.Master(ThumbPath(rel)) }

// 16 bytes, spelled in hex.
//
// **The name is random rather than derived from the product id, and that is a caching decision.**
// Every photo is served with `Cache-Control: immutable, max-age=1y`, so a phone that has seen one url
// will not ask for it again this year. Reusing "product-42.jpg" for a replacement would leave every
// device that already loaded the old one showing it until the cache expired - reported as "my new
// photo did not save" by someone whose photo saved perfectly. A new name is a new url, and the old
// files are unlinked separately once the row no longer points at them.
//
// Long enough that guessing a url is not a way to enumerate the market's photos, which matters
// because nothing serving them has any authorization in front of it.
func randomName() (string, error) {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return "", errors.New("imagestore: no randomness available: " + err.Error())
	}
	return hex.EncodeToString(raw), nil
}

// the relative paths one saved photo occupies: the master and its thumbnail, under a two-character
// shard.
//
// The shard keeps one flat directory from collecting every photo in the market. It costs nothing and
// is very hard to introduce later, once paths are in the database - and it is in the object key on
// R2 as well as in the directory name on disk, so the two backends produce byte-identical paths.
// That is what lets a database dump move between them.
func newPaths() (master, thumb string, err error) {
	name, err := randomName()
	if err != nil {
		return "", "", err
	}
	master = path.Join(UploadDir, name[:2], name+".jpg")
	return master, ThumbPath(master), nil
}
