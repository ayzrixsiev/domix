package imagestore

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"image/png"
	"os"
	"path"
	"path/filepath"
	"testing"
)

// This package is pure - no database, no network - so these run everywhere, unlike the endpoint
// suites. What they pin is the four things Normalize promises, each of which fails silently in its
// own way: a photo that is too heavy to scroll past, a photo lying on its side, a product floating
// on black, and a shop owner's home coordinates riding along inside a public url.

// a photo-shaped source: a coloured quadrant on white, so a rotation is detectable afterwards
func testImage(width, height int, quadrant color.RGBA) image.Image {
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	draw.Draw(img, img.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)
	draw.Draw(img, image.Rect(0, 0, width/2, height/2), image.NewUniform(quadrant), image.Point{}, draw.Src)
	return img
}

func encodeJPEG(t *testing.T, img image.Image) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 92}); err != nil {
		t.Fatalf("encoding the test jpeg: %v", err)
	}
	return buf.Bytes()
}

func decode(t *testing.T, data []byte) image.Image {
	t.Helper()
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		t.Fatalf("decoding the result: %v", err)
	}
	return img
}

// roughly-equal, because everything here has been through a lossy encoder at least once
func assertColour(t *testing.T, img image.Image, x, y int, want color.RGBA, what string) {
	t.Helper()
	r, g, b, _ := img.At(x, y).RGBA()
	const tolerance = 0x2000
	near := func(got uint32, expected uint8) bool {
		want := uint32(expected) * 0x101
		return got+tolerance > want && got < want+tolerance
	}
	if !near(r, want.R) || !near(g, want.G) || !near(b, want.B) {
		t.Errorf("%s: pixel at (%d,%d) is rgb(%d,%d,%d), expected about rgb(%d,%d,%d)",
			what, x, y, r>>8, g>>8, b>>8, want.R, want.G, want.B)
	}
}

func TestAPhotoIsScaledIntoTheServedBound(t *testing.T) {
	// 4:1, well past the bound on the long side and under it on the short one - so this also pins
	// that the aspect ratio survives, which a naive "resize to 1000x1000" would not
	source := encodeJPEG(t, testImage(2400, 600, color.RGBA{R: 220, G: 40, B: 40, A: 255}))

	out, err := Normalize(source)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}

	got := decode(t, out.Master).Bounds()
	if got.Dx() != OutputMaxSide || got.Dy() != OutputMaxSide/4 {
		t.Errorf("got %dx%d, expected %dx%d", got.Dx(), got.Dy(), OutputMaxSide, OutputMaxSide/4)
	}
	if len(out.Master) >= len(source) {
		t.Errorf("the stored copy (%d bytes) is not smaller than the upload (%d bytes)", len(out.Master), len(source))
	}
}

func TestASmallPhotoIsNotUpscaled(t *testing.T) {
	source := encodeJPEG(t, testImage(300, 200, color.RGBA{R: 40, G: 80, B: 220, A: 255}))

	out, err := Normalize(source)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}

	if got := decode(t, out.Master).Bounds(); got.Dx() != 300 || got.Dy() != 200 {
		t.Errorf("got %dx%d, expected the original 300x200 - upscaling invents detail", got.Dx(), got.Dy())
	}
	// and the thumbnail is not blown up to 400 either - the whole point is fewer bytes
	if got := decode(t, out.Thumb).Bounds(); got.Dx() != 300 || got.Dy() != 200 {
		t.Errorf("the thumbnail is %dx%d, expected the original 300x200", got.Dx(), got.Dy())
	}
}

// **the file the grid actually loads.** Nearly all of this api's image traffic is thumbnails: one
// shop card is up to a hundred tiles and one edit screen is one photo, so a master served into a
// grid is the difference between a catalogue that scrolls and one that stalls on mobile data.
//
// The two are checked together because they are stored together and the failure being guarded
// against is a pair that disagrees - a thumbnail cropped differently from the photo it opens into,
// or a "thumbnail" that is the master under another name.
func TestAThumbnailIsStoredBesideTheMaster(t *testing.T) {
	source := encodeJPEG(t, testImage(2000, 1000, color.RGBA{R: 30, G: 150, B: 90, A: 255}))

	out, err := Normalize(source)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}

	master, thumb := decode(t, out.Master).Bounds(), decode(t, out.Thumb).Bounds()
	if master.Dx() != OutputMaxSide || master.Dy() != OutputMaxSide/2 {
		t.Errorf("the master is %dx%d, expected %dx%d", master.Dx(), master.Dy(), OutputMaxSide, OutputMaxSide/2)
	}
	if thumb.Dx() != ThumbMaxSide || thumb.Dy() != ThumbMaxSide/2 {
		t.Errorf("the thumbnail is %dx%d, expected %dx%d", thumb.Dx(), thumb.Dy(), ThumbMaxSide, ThumbMaxSide/2)
	}
	// same shape, so a tile and the photo it opens into frame the product identically
	if master.Dx()*thumb.Dy() != master.Dy()*thumb.Dx() {
		t.Errorf("the two copies have different aspect ratios: %v and %v", master, thumb)
	}
	if len(out.Thumb) >= len(out.Master) {
		t.Errorf("the thumbnail (%d bytes) is not smaller than the master (%d bytes) - it exists to be",
			len(out.Thumb), len(out.Master))
	}
}

// jpeg has no alpha channel and go's encoder composites what it is given against black, so a png
// shot on a transparent background - which is what a product cut out in an editor looks like - would
// arrive as a product on a black square in a grid of white tiles.
func TestTransparencyIsFlattenedOntoWhite(t *testing.T) {
	source := image.NewRGBA(image.Rect(0, 0, 400, 400))
	draw.Draw(source, image.Rect(0, 0, 200, 400), image.NewUniform(color.RGBA{R: 10, G: 160, B: 90, A: 255}), image.Point{}, draw.Src)
	// the right half is left fully transparent

	var encoded bytes.Buffer
	if err := png.Encode(&encoded, source); err != nil {
		t.Fatalf("encoding the test png: %v", err)
	}

	out, err := Normalize(encoded.Bytes())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}

	result := decode(t, out.Master)
	assertColour(t, result, 300, 200, color.RGBA{R: 255, G: 255, B: 255}, "the transparent half")
	assertColour(t, result, 100, 200, color.RGBA{R: 10, G: 160, B: 90}, "the opaque half")
}

// **The one that would ship broken.** A phone stores the sensor's raster plus a tag, so a portrait
// photo is a landscape raster until something honours the tag - and re-encoding drops the tag.
func TestAPhotoIsTurnedTheRightWayUpBeforeItIsStored(t *testing.T) {
	red := color.RGBA{R: 220, G: 40, B: 40, A: 255}
	// 6 is "rotate 90° clockwise for display", which is what a phone held upright writes
	source := withEXIFOrientation(t, encodeJPEG(t, testImage(800, 400, red)), 6)

	out, err := Normalize(source)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}

	result := decode(t, out.Master)
	if got := result.Bounds(); got.Dx() != 400 || got.Dy() != 800 {
		t.Fatalf("got %dx%d, expected the sides swapped to 400x800", got.Dx(), got.Dy())
	}
	// the red quadrant started top-left; a 90° clockwise turn puts it top-right
	assertColour(t, result, 300, 100, red, "the quadrant after rotation")
	assertColour(t, result, 100, 100, color.RGBA{R: 255, G: 255, B: 255}, "where the quadrant was")
}

// re-encoding is what strips EXIF, and EXIF is where a phone writes the GPS coordinates a photo was
// taken at. this asserts the stripping rather than trusting it, because the failure is invisible:
// the tile looks identical either way and the coordinates only surface if somebody goes looking.
func TestMetadataDoesNotSurviveIntoTheStoredCopy(t *testing.T) {
	source := withEXIFOrientation(t, encodeJPEG(t, testImage(600, 600, color.RGBA{B: 200, A: 255})), 3)

	out, err := Normalize(source)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}

	if _, found := exifBlock(out.Master); found {
		t.Error("the stored jpeg still carries an EXIF block")
	}
	if _, found := exifBlock(out.Thumb); found {
		t.Error("the stored thumbnail still carries an EXIF block")
	}
}

func TestWhatIsNotAUsablePhotoIsRefused(t *testing.T) {
	tests := []struct {
		name string
		data []byte
		want error
	}{
		{"a text file with a .jpg name", []byte("this is not an image at all"), ErrUnsupportedFormat},
		{"an empty body", nil, ErrUnsupportedFormat},
		{"an icon rather than a photo", encodeJPEG(t, testImage(48, 48, color.RGBA{A: 255})), ErrTooSmall},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := Normalize(tc.data); !errors.Is(err, tc.want) {
				t.Errorf("got %v, expected %v", err, tc.want)
			}
		})
	}
}

// a header claiming far more pixels than the file could hold: the decompression bomb this is bounded
// against. DecodeConfig answers from the header, so nothing is allocated to find out.
func TestAnEnormousImageIsRefusedFromItsHeaderAlone(t *testing.T) {
	var buf bytes.Buffer
	if err := png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 64, 64))); err != nil {
		t.Fatalf("encoding: %v", err)
	}
	data := buf.Bytes()
	// the IHDR width and height sit at a fixed offset in every png: 8 bytes of signature, 8 of
	// chunk header, then two big-endian uint32s
	binary.BigEndian.PutUint32(data[16:20], 30000)
	binary.BigEndian.PutUint32(data[20:24], 30000)
	// every png chunk carries a crc over its type and data, and DecodeConfig checks it - so an
	// edited header has to be re-stamped or it is refused as corrupt rather than as too large
	binary.BigEndian.PutUint32(data[29:33], crc32.ChecksumIEEE(data[12:29]))

	if _, err := Normalize(data); !errors.Is(err, ErrTooLarge) {
		t.Errorf("got %v, expected %v", err, ErrTooLarge)
	}
}

// one photo is two files on disk, and both halves of every operation have to account for both. the
// master's path is the only one stored anywhere, so a thumbnail that is not written, or not deleted,
// is invisible to the database and shows up as a blank tile or as a file nobody can reach.
func TestAStoredPhotoIsTwoFilesUnderTheUploadsDirectory(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	store, err := NewDisk(root)
	if err != nil {
		t.Fatalf("NewDisk: %v", err)
	}

	rel, err := store.Save(ctx, Photo{Master: []byte("pretend this is a jpeg"), Thumb: []byte("and this a small one")})
	if err != nil {
		t.Fatalf("Save: %v", err)
	}

	if !IsUpload(rel) {
		t.Errorf("Save returned %q, which IsUpload does not recognise - Remove would refuse it", rel)
	}
	onDisk := func(path string) error {
		_, err := os.Stat(filepath.Join(root, filepath.FromSlash(path)))
		return err
	}
	if err := onDisk(rel); err != nil {
		t.Errorf("the file Save named is not on disk: %v", err)
	}
	if err := onDisk(ThumbPath(rel)); err != nil {
		t.Errorf("the thumbnail beside it is not on disk: %v", err)
	}

	// a second save must not collide with the first, or replacing a photo would overwrite somebody
	// else's
	other, err := store.Save(ctx, Photo{Master: []byte("a different photo"), Thumb: []byte("small")})
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	if other == rel {
		t.Errorf("two saves produced the same path %q", rel)
	}

	if err := store.Remove(ctx, rel); err != nil {
		t.Errorf("Remove: %v", err)
	}
	if err := onDisk(rel); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the file is still there after Remove: %v", err)
	}
	if err := onDisk(ThumbPath(rel)); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the thumbnail is still there after Remove: %v", err)
	}
	// removing what is already gone is a success - the caller is asking for a state, not an event
	if err := store.Remove(ctx, rel); err != nil {
		t.Errorf("removing an already-deleted photo: %v", err)
	}
}

// what the admin panel's sweep sees. It compares these paths against products.image_path, so a
// listing that spelled them any other way - absolute, backslashed, prefixed with the root - would
// match nothing and report the whole market as orphaned.
func TestListingNamesFilesTheWayTheDatabaseDoes(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	store, err := NewDisk(root)
	if err != nil {
		t.Fatalf("NewDisk: %v", err)
	}

	rel, err := store.Save(ctx, Photo{Master: []byte("a photo"), Thumb: []byte("small")})
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	// a curated catalogue shot in the same root, which must not be listed: the sweep deletes what it
	// lists, and one of these files is shared by every shop of a category
	if err := os.MkdirAll(filepath.Join(root, "universal"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "universal", "001.jpg"), []byte("shared"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}

	listed, err := store.List(ctx, UploadDir)
	if err != nil {
		t.Fatalf("List: %v", err)
	}

	found := map[string]int64{}
	for _, object := range listed {
		found[object.Path] = object.Size
		if !IsUpload(object.Path) {
			t.Errorf("List returned %q, which is not under uploads/", object.Path)
		}
	}
	if len(found) != 2 {
		t.Fatalf("got %d files, expected the master and its thumbnail: %v", len(found), found)
	}
	if size, ok := found[rel]; !ok || size != int64(len("a photo")) {
		t.Errorf("the master is listed as %d bytes, expected %d", size, len("a photo"))
	}
	if _, ok := found[ThumbPath(rel)]; !ok {
		t.Errorf("the thumbnail %q was not listed", ThumbPath(rel))
	}
}

// the sweep deletes one file at a time - a thumbnail whose master is already gone is exactly the
// kind of thing it is for, and Remove would go looking for a partner that does not exist.
func TestRemoveFileTakesOneHalfOfAPair(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	store, err := NewDisk(root)
	if err != nil {
		t.Fatalf("NewDisk: %v", err)
	}

	rel, err := store.Save(ctx, Photo{Master: []byte("a photo"), Thumb: []byte("small")})
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	if err := store.RemoveFile(ctx, ThumbPath(rel)); err != nil {
		t.Fatalf("RemoveFile: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, filepath.FromSlash(rel))); err != nil {
		t.Errorf("the master went with the thumbnail: %v", err)
	}
}

// **the guard that matters.** products.image_path holds curated catalogue photos too, and those are
// shared by every shop of a category - one owner clearing their photo must not unlink the file the
// other forty draw.
func TestRemoveRefusesAnythingOutsideUploads(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	store, err := NewDisk(root)
	if err != nil {
		t.Fatalf("NewDisk: %v", err)
	}

	catalogue := filepath.Join(root, "universal")
	if err := os.MkdirAll(catalogue, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	photo := filepath.Join(catalogue, "001.jpg")
	if err := os.WriteFile(photo, []byte("a catalogue photo"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}

	for _, path := range []string{"shops/universal/001.jpg", "shops/uploads/../universal/001.jpg", "", "shops/uploads"} {
		if err := store.Remove(ctx, path); !errors.Is(err, ErrOutsideUploads) {
			t.Errorf("Remove(%q) returned %v, expected ErrOutsideUploads", path, err)
		}
		// the sweep's deletion path takes the same refusal, and it is the one pointed at files
		// rather than at a products row - so it is the one that could reach the catalogue
		if err := store.RemoveFile(ctx, path); !errors.Is(err, ErrOutsideUploads) {
			t.Errorf("RemoveFile(%q) returned %v, expected ErrOutsideUploads", path, err)
		}
	}
	if _, err := os.Stat(photo); err != nil {
		t.Errorf("the catalogue photo was deleted: %v", err)
	}
}

// builds the APP1 segment a camera writes and splices it in directly after the SOI marker, which is
// where one sits in a real photo. little-endian ("II"), since that is what most phones write.
func withEXIFOrientation(t *testing.T, jpegBytes []byte, orientation uint16) []byte {
	t.Helper()

	tiff := new(bytes.Buffer)
	tiff.WriteString("II")                                  // byte order
	binary.Write(tiff, binary.LittleEndian, uint16(42))     // the version, always 42
	binary.Write(tiff, binary.LittleEndian, uint32(8))      // IFD0 begins straight after this header
	binary.Write(tiff, binary.LittleEndian, uint16(1))      // one entry
	binary.Write(tiff, binary.LittleEndian, uint16(0x0112)) // tag: orientation
	binary.Write(tiff, binary.LittleEndian, uint16(3))      // type: SHORT
	binary.Write(tiff, binary.LittleEndian, uint32(1))      // count
	binary.Write(tiff, binary.LittleEndian, orientation)    // the value, in the first half of the field
	binary.Write(tiff, binary.LittleEndian, uint16(0))      // ... and its padding
	binary.Write(tiff, binary.LittleEndian, uint32(0))      // no next IFD

	payload := append([]byte("Exif\x00\x00"), tiff.Bytes()...)

	segment := new(bytes.Buffer)
	segment.Write([]byte{0xFF, 0xE1})
	binary.Write(segment, binary.BigEndian, uint16(len(payload)+2)) // the length counts itself
	segment.Write(payload)

	out := make([]byte, 0, len(jpegBytes)+segment.Len())
	out = append(out, jpegBytes[:2]...) // SOI
	out = append(out, segment.Bytes()...)
	return append(out, jpegBytes[2:]...)
}

// **the two deletion doors must not overlap.** an owner's photo and a curated one are deleted by
// different sweeps for different reasons; if either method accepted the other kind, a bug in one
// sweep would reach files that belong to the other - and a curated file is drawn by every shop of a
// category at once.
func TestTheTwoDeletionDoorsDoNotOverlap(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	store, err := NewDisk(root)
	if err != nil {
		t.Fatalf("NewDisk: %v", err)
	}

	upload, err := store.Save(ctx, Photo{Master: []byte("an owner's photo"), Thumb: []byte("small")})
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	shot := filepath.Join(root, "shops", "universal", "001.jpg")
	if err := os.MkdirAll(filepath.Dir(shot), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(shot, []byte("a catalogue photo"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}

	// the catalogue door refuses an upload, a traversal, the root itself and a deeper path
	for _, path := range []string{upload, "shops/universal/../uploads/x.jpg", "shops", "shops/universal", "shops/universal/a/b.jpg", ""} {
		if err := store.RemoveCatalogueFile(ctx, path); !errors.Is(err, ErrOutsideCatalogue) {
			t.Errorf("RemoveCatalogueFile(%q) returned %v, expected ErrOutsideCatalogue", path, err)
		}
	}
	if _, err := os.Stat(filepath.Join(root, filepath.FromSlash(upload))); err != nil {
		t.Fatalf("the catalogue door deleted an owner's photo: %v", err)
	}

	// the upload door still refuses the catalogue
	if err := store.RemoveFile(ctx, "shops/universal/001.jpg"); !errors.Is(err, ErrOutsideUploads) {
		t.Errorf("RemoveFile on a catalogue photo returned %v, expected ErrOutsideUploads", err)
	}

	// and each door does open for its own kind
	if err := store.RemoveCatalogueFile(ctx, "shops/universal/001.jpg"); err != nil {
		t.Fatalf("RemoveCatalogueFile on a catalogue photo: %v", err)
	}
	if _, err := os.Stat(shot); !os.IsNotExist(err) {
		t.Errorf("the catalogue photo is still there: %v", err)
	}
}

// **the second write door, and the property that makes it a door rather than an argument.** A
// curated photo written anywhere `IsCatalogue` does not recognise is a file the catalogue sweep
// cannot delete and the panel's picker cannot list - and a category that escaped its own folder
// would be a write into the uploads namespace, where one row owns every file.
func TestACataloguePhotoIsWrittenIntoItsOwnCategoryAndNowhereElse(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	store, err := NewDisk(root)
	if err != nil {
		t.Fatalf("NewDisk: %v", err)
	}

	rel, err := store.SaveCatalogue(ctx, "universal", Photo{Master: []byte("a curated photo"), Thumb: []byte("small")})
	if err != nil {
		t.Fatalf("SaveCatalogue: %v", err)
	}

	if !IsCatalogue(rel) {
		t.Errorf("SaveCatalogue returned %q, which IsCatalogue does not recognise - the sweep could never collect it", rel)
	}
	if IsUpload(rel) {
		t.Errorf("SaveCatalogue returned %q, which the uploads door would accept", rel)
	}
	if dir := path.Dir(rel); dir != "shops/universal" {
		t.Errorf("SaveCatalogue wrote into %q, want shops/universal", dir)
	}
	for _, p := range []string{rel, ThumbPath(rel)} {
		if _, err := os.Stat(filepath.Join(root, filepath.FromSlash(p))); err != nil {
			t.Errorf("%q is not on disk: %v", p, err)
		}
	}

	// **a replacement is a new name, because these urls are served immutable for a year** - and a
	// curated file is drawn by every shop of the category, so a reused name would freeze the old
	// picture onto every phone that had already loaded it
	other, err := store.SaveCatalogue(ctx, "universal", Photo{Master: []byte("the reshoot"), Thumb: []byte("small")})
	if err != nil {
		t.Fatalf("SaveCatalogue: %v", err)
	}
	if other == rel {
		t.Errorf("two catalogue saves produced the same path %q", rel)
	}

	// a category that is not one segment of its own cannot be written at all: these would land in
	// the uploads namespace, at the images root, or outside it. a leading slash is not among them -
	// path.Join cleans it away, so "/universal" is the same write as "universal".
	for _, category := range []string{"", "..", "universal/../uploads", "a/b"} {
		if _, err := store.SaveCatalogue(ctx, category, Photo{Master: []byte("x"), Thumb: []byte("y")}); !errors.Is(err, ErrOutsideCatalogue) {
			t.Errorf("SaveCatalogue(%q) returned %v, expected ErrOutsideCatalogue", category, err)
		}
	}

	// and what it wrote opens only the catalogue door
	if err := store.RemoveFile(ctx, rel); !errors.Is(err, ErrOutsideUploads) {
		t.Errorf("the uploads door accepted a catalogue photo: %v", err)
	}
	if err := store.RemoveCatalogueFile(ctx, rel); err != nil {
		t.Fatalf("RemoveCatalogueFile on what SaveCatalogue wrote: %v", err)
	}
}
