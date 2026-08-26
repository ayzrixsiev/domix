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

	// registers the png decoder with image.Decode. blank imports, because nothing here calls into
	// either package by name - the format is discovered from the bytes.
	_ "image/png"

	xdraw "golang.org/x/image/draw"
)

const (
	// OutputMaxSide is the longest side a stored photo may have. The curated catalogue photos are
	// resized to exactly this before being committed (see the `magick` line in CLAUDE.md §7), and an
	// owner's photo sits in the same grid beside them - a tile that downloads four times as much
	// data as its neighbour for the same 118px band is the difference between a grid that scrolls
	// and one that stalls on a phone tethered to mobile data.
	//
	// This is the copy the *edit screen* loads, and any future full-size view. It is not what a grid
	// loads - see [ThumbMaxSide].
	OutputMaxSide = 1000

	// ThumbMaxSide is the longest side of the copy a catalogue grid loads, which is very nearly all
	// the image traffic this api will ever serve: one shop card is up to a hundred tiles and one
	// edit screen is one photo.
	//
	// 400 rather than the ~180dp a tile is actually painted at, because the same file has to survive
	// a 3x screen without going soft, and because a thumbnail is also what a future full-width list
	// row would use. It turns a 100-tile universal catalogue from roughly 15 MB into roughly 2.5 MB.
	ThumbMaxSide = 400

	// 85 is where JPEG stops paying for itself: the file roughly doubles between 85 and 95 and the
	// difference is not visible on a photo of a bag of cement at 180dp. Same value as the catalogue.
	jpegQuality = 85

	// under this on either side it is an icon, a screenshot fragment or a mistake - not a photo of a
	// product, and it would be upscaled into mush by the grid
	minSourceSide = 64

	// **These two bound the decode, and that is their whole job.** A JPEG is compressed, so a file
	// well inside MaxUploadBytes can describe an image with hundreds of millions of pixels, and
	// decoding it allocates four bytes per pixel whatever the file weighed - the classic
	// decompression bomb. image.DecodeConfig reads only the header, so both are answered before a
	// single pixel is allocated.
	maxSourceSide   = 12000
	maxSourcePixels = 60_000_000
)

// What Normalize refuses, as sentinel errors, so the handler can turn each into its own error code
// for the app to localize - "this is not a photo" and "this photo is enormous" need different words.
var (
	ErrUnsupportedFormat = errors.New("imagestore: only jpeg and png images are accepted")
	ErrTooSmall          = errors.New("imagestore: the image is too small")
	ErrTooLarge          = errors.New("imagestore: the image has too many pixels")
	ErrBroken            = errors.New("imagestore: the image could not be decoded")
)

// Normalize turns whatever arrived into the two files this api stores: JPEGs, no alpha channel and
// no metadata, one bounded by [OutputMaxSide] and one by [ThumbMaxSide].
//
// Four things happen here and each is load-bearing:
//
//   - **It decodes.** Content-Type and file extension are both written by the client, so the only
//     honest answer to "is this a photo" is to parse it. Everything after this line is operating on
//     pixels rather than on a claim.
//   - **It re-encodes**, which is what strips the metadata. A phone photo carries EXIF, and EXIF
//     routinely carries the GPS coordinates the picture was taken at. Serving that untouched off a
//     public url would publish the location of a shop owner's home for any photo not taken in the
//     shop, and nothing in the ui would ever hint at it.
//   - **It applies the EXIF orientation first** (see exif.go). A phone stores the sensor's pixels
//     and a tag saying which way up they go; drop the tag without acting on it and every photo taken
//     in portrait arrives on its side.
//   - **It flattens transparency onto white.** JPEG has no alpha, and Go's encoder composites
//     against black, so a PNG with a transparent background would come out as a product floating on
//     a black rectangle in a grid of white tiles.
//
// **The thumbnail is scaled from the master, not from the source**, which is worth being deliberate
// about. It is fractionally lossier - two resamples instead of one, invisible at 400px on a
// photograph - and it buys two things: the expensive work (decode, EXIF, the big downscale) happens
// once, and the two files are guaranteed to frame the product identically. Two independent scales of
// the same source would round their dimensions separately, so a tile and the photo it opens into
// could differ by a pixel of crop.
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

	// **Scaled first, rotated second, and the order is free.** The target is a square bound - fit
	// inside 1000x1000 - so it is the same box whichever way up the photo ends up, and rotating a
	// one-megapixel result costs a hundredth of what rotating a twelve-megapixel source does.
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

// fit draws the source onto an opaque white canvas no larger than `maxSide` on its longest side,
// preserving the aspect ratio. Always returns a fresh *image.RGBA, so everything downstream has one
// concrete type to work with.
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
		// no resampling wanted. running the scaler at 1:1 would still filter every pixel through
		// the kernel and soften a photo that needed nothing done to it.
		draw.Draw(dst, dst.Bounds(), src, bounds.Min, draw.Over)
		return dst
	}

	// CatmullRom rather than ApproxBiLinear: this is a large downscale of a photograph, done once,
	// on a request nobody is watching a frame counter for. Bilinear drops detail on a 4x reduction
	// in a way that shows up as mush on the small print of a paint tin.
	xdraw.CatmullRom.Scale(dst, dst.Bounds(), src, bounds, xdraw.Over, nil)
	return dst
}

// orient applies one of the eight EXIF orientations, mapping each source pixel to where it belongs
// once the photo is the right way up. Orientations 5-8 transpose the image, so the destination's
// width and height are swapped.
//
// A pixel loop rather than a library: the eight cases *are* the specification, and written out this
// way each one is a line that can be checked against it. The image is already down to at most a
// megapixel by the time this runs.
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
