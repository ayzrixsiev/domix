package imagestore

import (
	"bytes"
	"encoding/binary"
)

// one number out of a JPEG's EXIF block: the orientation tag.
//
// **why this is here rather than a dependency.** a phone stores the sensor's own raster plus a tag
// saying which of eight ways up it goes. Go's jpeg decoder hands back the raw raster and re-encoding
// drops the tag, so a portrait photo - most of them - would be stored on its side with nothing in
// any log to explain it. the full spec is large; this is one 16-bit integer at a known place, parsed
// with a bound at every step, and anything unexpected answers 1 ("upright").
func orientationOf(src []byte) int {
	block, ok := exifBlock(src)
	if !ok {
		return 1
	}
	return orientationInTIFF(block)
}

// the payload of the first APP1 segment announcing itself as EXIF, introducer stripped: the TIFF block
func exifBlock(src []byte) ([]byte, bool) {
	// SOI. anything else is not a JPEG, which includes every PNG that reaches here.
	if len(src) < 4 || src[0] != 0xFF || src[1] != 0xD8 {
		return nil, false
	}

	introducer := []byte("Exif\x00\x00")

	for pos := 2; pos+4 <= len(src); {
		if src[pos] != 0xFF {
			return nil, false // out of step with the segment structure; nothing further can be trusted
		}

		marker := src[pos+1]
		pos += 2

		switch {
		case marker == 0xFF:
			// fill byte: a segment may be padded with any number of 0xFF before its marker
			pos--
			continue
		case marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7):
			continue // standalone markers, no length and no payload
		case marker == 0xDA || marker == 0xD9:
			return nil, false // start of the compressed scan, or end of image: no metadata past here
		}

		if pos+2 > len(src) {
			return nil, false
		}
		// the length counts itself, so the payload is two bytes shorter. always big-endian, whatever
		// the TIFF block inside later declares.
		length := int(binary.BigEndian.Uint16(src[pos : pos+2]))
		if length < 2 || pos+length > len(src) {
			return nil, false
		}
		payload := src[pos+2 : pos+length]
		pos += length

		if marker == 0xE1 && bytes.HasPrefix(payload, introducer) {
			return payload[len(introducer):], true
		}
	}
	return nil, false
}

// orientationInTIFF reads tag 0x0112 out of a TIFF block's first IFD.
func orientationInTIFF(tiff []byte) int {
	const (
		upright        = 1
		orientationTag = 0x0112
		typeShort      = 3
		entrySize      = 12
		headerSize     = 8
		maxOrientation = 8
	)

	if len(tiff) < headerSize {
		return upright
	}

	// the block declares its own byte order, which may differ from the JPEG's - every multi-byte
	// read below has to go through it
	var order binary.ByteOrder
	switch {
	case tiff[0] == 'I' && tiff[1] == 'I':
		order = binary.LittleEndian
	case tiff[0] == 'M' && tiff[1] == 'M':
		order = binary.BigEndian
	default:
		return upright
	}
	if order.Uint16(tiff[2:4]) != 42 { // the version, and always 42
		return upright
	}

	ifd := int(order.Uint32(tiff[4:8]))
	if ifd < headerSize || ifd+2 > len(tiff) {
		return upright
	}

	entries := int(order.Uint16(tiff[ifd : ifd+2]))
	for i := 0; i < entries; i++ {
		at := ifd + 2 + i*entrySize
		if at+entrySize > len(tiff) {
			return upright
		}
		if order.Uint16(tiff[at:at+2]) != orientationTag {
			continue
		}
		if order.Uint16(tiff[at+2:at+4]) != typeShort {
			return upright // the tag exists but is not the type it is defined as
		}
		// a SHORT fits in the entry's value field rather than at an offset elsewhere in the block
		value := int(order.Uint16(tiff[at+8 : at+10]))
		if value < 1 || value > maxOrientation {
			return upright
		}
		return value
	}
	return upright
}
