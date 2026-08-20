package imagestore

import (
	"bytes"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"image/png"
	"os"
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

	got := decode(t, out).Bounds()
	if got.Dx() != OutputMaxSide || got.Dy() != OutputMaxSide/4 {
		t.Errorf("got %dx%d, expected %dx%d", got.Dx(), got.Dy(), OutputMaxSide, OutputMaxSide/4)
	}
	if len(out) >= len(source) {
		t.Errorf("the stored copy (%d bytes) is not smaller than the upload (%d bytes)", len(out), len(source))
	}
}

func TestASmallPhotoIsNotUpscaled(t *testing.T) {
	source := encodeJPEG(t, testImage(300, 200, color.RGBA{R: 40, G: 80, B: 220, A: 255}))

	out, err := Normalize(source)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}

	if got := decode(t, out).Bounds(); got.Dx() != 300 || got.Dy() != 200 {
		t.Errorf("got %dx%d, expected the original 300x200 - upscaling invents detail", got.Dx(), got.Dy())
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

	result := decode(t, out)
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

	result := decode(t, out)
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

	if _, found := exifBlock(out); found {
		t.Error("the stored jpeg still carries an EXIF block")
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

func TestAStoredFileLandsUnderTheUploadsDirectory(t *testing.T) {
	root := t.TempDir()
	store, err := New(root)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	rel, err := store.Save([]byte("pretend this is a jpeg"))
	if err != nil {
		t.Fatalf("Save: %v", err)
	}

	if !IsUpload(rel) {
		t.Errorf("Save returned %q, which IsUpload does not recognise - Remove would refuse it", rel)
	}
	if _, err := os.Stat(filepath.Join(root, filepath.FromSlash(rel))); err != nil {
		t.Errorf("the file Save named is not on disk: %v", err)
	}

	// a second save must not collide with the first, or replacing a photo would overwrite somebody
	// else's
	other, err := store.Save([]byte("a different photo"))
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	if other == rel {
		t.Errorf("two saves produced the same path %q", rel)
	}

	if err := store.Remove(rel); err != nil {
		t.Errorf("Remove: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, filepath.FromSlash(rel))); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the file is still there after Remove: %v", err)
	}
	// removing what is already gone is a success - the caller is asking for a state, not an event
	if err := store.Remove(rel); err != nil {
		t.Errorf("removing an already-deleted file: %v", err)
	}
}

// **the guard that matters.** products.image_path holds curated catalogue photos too, and those are
// shared by every shop of a category - one owner clearing their photo must not unlink the file the
// other forty draw.
func TestRemoveRefusesAnythingOutsideUploads(t *testing.T) {
	root := t.TempDir()
	store, err := New(root)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	catalogue := filepath.Join(root, "universal")
	if err := os.MkdirAll(catalogue, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	photo := filepath.Join(catalogue, "001.jpg")
	if err := os.WriteFile(photo, []byte("a catalogue photo"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}

	for _, path := range []string{"universal/001.jpg", "uploads/../universal/001.jpg", "", "uploads"} {
		if err := store.Remove(path); !errors.Is(err, ErrOutsideUploads) {
			t.Errorf("Remove(%q) returned %v, expected ErrOutsideUploads", path, err)
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
