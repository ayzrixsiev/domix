package imagestore

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"math"

	// registers the png decoder with image.Decode - the format is discovered from the bytes
	_ "image/png"

	xdraw "golang.org/x/image/draw"
)

const (
	// the longest side a stored photo may have, matching the curated catalogue it sits beside in a
	// grid. what the *edit screen* loads - a grid loads [ThumbMaxSide].
	OutputMaxSide = 1000

	// what a catalogue grid loads, which is nearly all the image traffic here: one shop card is up to a
	// hundred tiles. 400 rather than the ~180dp it is painted at, so it survives a 3x screen.
	ThumbMaxSide = 400

	// where JPEG stops paying for itself: the file roughly doubles between 85 and 95 and the
	// difference is invisible on a bag of cement at 180dp
	jpegQuality = 85

	// under this it is an icon or a screenshot fragment, and the grid would upscale it into mush
	minSourceSide = 64

	// **these two bound the decode, and that is their whole job**: a file well inside MaxUploadBytes can
	// describe hundreds of millions of pixels. DecodeConfig reads only the header, so both are checked first.
	maxSourceSide   = 12000
	maxSourcePixels = 60_000_000
)

// sentinels, so the handler can turn each into its own code: "this is not a photo" and "this photo
// is enormous" need different words
var (
	ErrUnsupportedFormat = errors.New("imagestore: only jpeg and png images are accepted")
	ErrTooSmall          = errors.New("imagestore: the image is too small")
	ErrTooLarge          = errors.New("imagestore: the image has too many pixels")
	ErrBroken            = errors.New("imagestore: the image could not be decoded")
)

// turns whatever arrived into the two files this api stores: JPEGs, no alpha, no metadata.
//
//   - **it decodes**, because Content-Type and extension are both written by the client.
//   - **it re-encodes**, which is what strips EXIF - routinely carrying the GPS coordinates a picture
//     was taken at, which off a public url publishes a shop owner's home address.
//   - **it applies the EXIF orientation first** (exif.go), or every portrait photo arrives sideways.
//   - **it flattens transparency onto white**, because Go's jpeg encoder composites against black.
//
// **the thumbnail is scaled from the master, not the source**: the expensive work happens once, and the
// two files frame the product identically.
func Normalize(src []byte) (Photo, error) {
	// header only - no pixels are allocated until the two bounds below have been checked
	cfg, format, err := image.DecodeConfig(bytes.NewReader(src))
	if err != nil {
		return Photo{}, fmt.Errorf("%w: %v", ErrUnsupportedFormat, err)
	}
	if format != "jpeg" && format != "png" {
		return Photo{}, fmt.Errorf("%w: got %s", ErrUnsupportedFormat, format)
	}
	if cfg.Width < minSourceSide || cfg.Height < minSourceSide {
		return Photo{}, fmt.Errorf("%w: %dx%d", ErrTooSmall, cfg.Width, cfg.Height)
	}
	if cfg.Width > maxSourceSide || cfg.Height > maxSourceSide ||
		cfg.Width*cfg.Height > maxSourcePixels {
		return Photo{}, fmt.Errorf("%w: %dx%d", ErrTooLarge, cfg.Width, cfg.Height)
	}

	img, _, err := image.Decode(bytes.NewReader(src))
	if err != nil {
		return Photo{}, fmt.Errorf("%w: %v", ErrBroken, err)
	}

	// scaled first, rotated second: the target is a square bound, so it is the same box whichever
	// way up the photo ends, and rotating one megapixel costs a hundredth of rotating twelve
	master := orient(fit(img, OutputMaxSide), orientationOf(src))

	masterJPEG, err := encode(master)
	if err != nil {
		return Photo{}, err
	}
	thumbJPEG, err := encode(fit(master, ThumbMaxSide))
	if err != nil {
		return Photo{}, err
	}
	return Photo{Master: masterJPEG, Thumb: thumbJPEG}, nil
}

func encode(img image.Image) ([]byte, error) {
	var out bytes.Buffer
	if err := jpeg.Encode(&out, img, &jpeg.Options{Quality: jpegQuality}); err != nil {
		return nil, fmt.Errorf("imagestore: encoding: %w", err)
	}
	return out.Bytes(), nil
}

// draws the source onto an opaque white canvas bounded by `maxSide`, preserving the aspect ratio.
// always a fresh *image.RGBA, so everything downstream has one concrete type.
func fit(src image.Image, maxSide int) *image.RGBA {
	bounds := src.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	if longest := max(width, height); longest > maxSide {
		scale := float64(maxSide) / float64(longest)
		width = max(1, int(math.Round(float64(width)*scale)))
		height = max(1, int(math.Round(float64(height)*scale)))
	}

	dst := image.NewRGBA(image.Rect(0, 0, width, height))
	// the white goes down first and the photo composites over it - see the alpha note on Normalize
	draw.Draw(dst, dst.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)

	if width == bounds.Dx() && height == bounds.Dy() {
		// running the scaler at 1:1 would still filter every pixel and soften a photo that needed nothing
		draw.Draw(dst, dst.Bounds(), src, bounds.Min, draw.Over)
		return dst
	}

	// CatmullRom rather than ApproxBiLinear: a large downscale done once, where bilinear would turn
	// the small print on a paint tin into mush
	xdraw.CatmullRom.Scale(dst, dst.Bounds(), src, bounds, xdraw.Over, nil)
	return dst
}

// applies one of the eight EXIF orientations. 5-8 transpose, so width and height swap. a pixel loop
// rather than a library: the eight cases *are* the specification, and the image is at most a megapixel.
func orient(img *image.RGBA, orientation int) *image.RGBA {
	if orientation <= 1 || orientation > 8 {
		return img // 1 is "already upright", and anything unrecognised is treated as such
	}

	bounds := img.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	dstWidth, dstHeight := width, height
	if orientation >= 5 {
		dstWidth, dstHeight = height, width
	}
	dst := image.NewRGBA(image.Rect(0, 0, dstWidth, dstHeight))

	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			var nx, ny int
			switch orientation {
			case 2: // mirrored horizontally
				nx, ny = width-1-x, y
			case 3: // rotated 180°
				nx, ny = width-1-x, height-1-y
			case 4: // mirrored vertically
				nx, ny = x, height-1-y
			case 5: // transposed (mirrored across the main diagonal)
				nx, ny = y, x
			case 6: // rotated 90° clockwise - by far the most common, portrait on most phones
				nx, ny = height-1-y, x
			case 7: // transverse (mirrored across the anti-diagonal)
				nx, ny = height-1-y, width-1-x
			case 8: // rotated 90° counter-clockwise
				nx, ny = y, width-1-x
			}
			dst.SetRGBA(nx, ny, img.RGBAAt(bounds.Min.X+x, bounds.Min.Y+y))
		}
	}
	return dst
}
