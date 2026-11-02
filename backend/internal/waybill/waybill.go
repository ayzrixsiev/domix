// package waybill draws the накладная staff download from the admin panel: the printed paper form, with
// the customer's list already filled in. it knows nothing about http or the database.
//
// Цена and Сумма stay empty on purpose: a customer only says what they want and how much, and the
// form is what somebody prices by hand.
package waybill

import (
	"bytes"
	_ "embed"
	"fmt"
	"strings"
	"time"

	"codeberg.org/go-pdf/fpdf"
	"golang.org/x/image/font/sfnt"
)

// Liberation Serif, because it has the metrics of the Times the paper form is set in and covers Russian,
// Uzbek Cyrillic and Uzbek Latin. SIL OFL, see fonts/LICENSE.
//
//go:embed fonts/LiberationSerif-Regular.ttf
var regularFont []byte

//go:embed fonts/LiberationSerif-Bold.ttf
var boldFont []byte

var regularGlyphs = mustParseFont(regularFont)

func mustParseFont(raw []byte) *sfnt.Font {
	font, err := sfnt.Parse(raw)
	if err != nil {
		panic("waybill: the embedded font does not parse: " + err.Error())
	}
	return font
}

// Item is one line of the list.
type Item struct {
	Name     string `json:"name"`
	Quantity string `json:"quantity"`
}

// Document is one filled form. Exactly one of Items and Photo is set, as in the waybills table.
type Document struct {
	Number int64
	Date   time.Time
	To     string
	From   string
	Items  []Item

	// a JPEG of a paper list, printed where the table would be
	Photo []byte
}

// millimetres on a4, read off the paper form
const (
	family = "serif"

	left, right = 14.0, 195.0

	// the table's inner verticals, between №, name, quantity, price and sum. the blank has no outer ones.
	numberEnd, nameEnd, quantityEnd, priceEnd = 27.0, 104.0, 130.0, 156.0

	firstTableTop, nextTableTop = 59.0, 30.0
	headerHeight                = 21.0
	tableBottom                 = 261.0

	minRowHeight   = 10.0
	cellPadding    = 1.6
	textLineHeight = 4.6
	textSize       = 11.0

	thinLine, midLine, thickLine = 0.2, 0.35, 0.6
)

var russianMonths = [...]string{"января", "февраля", "марта", "апреля", "мая", "июня", "июля",
	"августа", "сентября", "октября", "ноября", "декабря"}

// **a fixed offset rather than a tz lookup**: the date is printed on a legal-looking form in Uzbekistan
// whatever zone the server runs in, and the country has no daylight saving to get wrong.
var tashkent = time.FixedZone("UZT", 5*60*60)

// Render returns the finished PDF.
func Render(doc Document) ([]byte, error) {
	pdf := newSheet()
	pdf.SetTitle(fmt.Sprintf("Накладная № %d", doc.Number), true)

	if doc.Photo != nil {
		pdf.AddPage()
		drawHeading(pdf, doc)
		if err := drawPhoto(pdf, doc.Photo); err != nil {
			return nil, err
		}
		drawSignatures(pdf)
	} else {
		pages := paginate(pdf, doc.Items)
		for index, page := range pages {
			pdf.AddPage()
			top := firstTableTop
			if index == 0 {
				drawHeading(pdf, doc)
			} else {
				top = nextTableTop
				drawContinuation(pdf, doc.Number, index+1, len(pages))
			}
			drawTable(pdf, top, page)
			if index == len(pages)-1 {
				drawSignatures(pdf)
			}
		}
	}

	var out bytes.Buffer
	if err := pdf.Output(&out); err != nil {
		return nil, fmt.Errorf("waybill: rendering №%d: %w", doc.Number, err)
	}
	return out.Bytes(), nil
}

func newSheet() *fpdf.Fpdf {
	pdf := fpdf.New("P", "mm", "A4", "")
	pdf.SetAutoPageBreak(false, 0)
	pdf.SetCellMargin(0)
	pdf.AddUTF8FontFromBytes(family, "", regularFont)
	pdf.AddUTF8FontFromBytes(family, "B", boldFont)
	return pdf
}

func drawHeading(pdf *fpdf.Fpdf, doc Document) {
	date := doc.Date.In(tashkent)

	pdf.SetFont(family, "", 12)
	pdf.Text(112, 21, "\"")
	drawOnRule(pdf, fmt.Sprintf("%02d", date.Day()), 115, 128, 21)
	pdf.Text(129, 21, "\"")
	drawOnRule(pdf, russianMonths[date.Month()-1], 133, 176, 21)
	pdf.Text(178, 21, fmt.Sprintf("%d г.", date.Year()))

	// centred as one line with its number, and the rule keeps the blank's minimum width on a short one
	const numberMinWidth = 20.0
	label, number := "НАКЛАДНАЯ № ", fmt.Sprint(doc.Number)
	pdf.SetFont(family, "B", 15)
	labelWidth := pdf.GetStringWidth(label)
	numberWidth := max(pdf.GetStringWidth(number)+4, numberMinWidth)
	start := (210 - labelWidth - numberWidth) / 2
	pdf.Text(start, 33, label)
	drawOnRule(pdf, number, start+labelWidth, start+labelWidth+numberWidth, 33)

	drawAddressLine(pdf, "Кому", doc.To, 44)
	drawAddressLine(pdf, "От кого", doc.From, 54)
}

func drawAddressLine(pdf *fpdf.Fpdf, label, value string, baseline float64) {
	pdf.SetFont(family, "", 12)
	pdf.Text(left, baseline, label)
	start := left + pdf.GetStringWidth(label) + 2

	pdf.SetLineWidth(thinLine)
	pdf.Line(start, baseline+1, right, baseline+1)

	// a hundred-letter name has to fit its line: the type shrinks rather than running off the sheet
	value = printable(value)
	size := 12.0
	pdf.SetFont(family, "", size)
	for size > 7 && pdf.GetStringWidth(value) > right-start-2 {
		size -= 0.5
		pdf.SetFont(family, "", size)
	}
	pdf.Text(start+1, baseline, value)
}

// text centred on a blank's underline, in whatever font is current
func drawOnRule(pdf *fpdf.Fpdf, text string, from, to, baseline float64) {
	pdf.SetLineWidth(thinLine)
	pdf.Line(from, baseline+1, to, baseline+1)
	drawCentred(pdf, text, from, to, baseline)
}

func drawCentred(pdf *fpdf.Fpdf, text string, from, to, baseline float64) {
	pdf.Text(from+(to-from-pdf.GetStringWidth(text))/2, baseline, text)
}

// a sheet of a long list has no heading to say whose it is once the pages are apart
func drawContinuation(pdf *fpdf.Fpdf, number int64, sheet, sheets int) {
	pdf.SetFont(family, "", 11)
	pdf.Text(left, 24, fmt.Sprintf("Накладная № %d", number))
	caption := fmt.Sprintf("лист %d из %d", sheet, sheets)
	pdf.Text(right-pdf.GetStringWidth(caption), 24, caption)
}

// one printed line of the table, already wrapped to its columns
type row struct {
	number         int
	name, quantity []string
	height         float64
}

// paginate wraps every line and deals them onto sheets. the last sheet is never empty of room to write
// more by hand, because drawTable rules the rest of it like the printed form.
func paginate(pdf *fpdf.Fpdf, items []Item) [][]row {
	pdf.SetFont(family, "", textSize)

	pages := [][]row{}
	current := []row{}
	used := 0.0
	room := tableBottom - firstTableTop - headerHeight

	for index, item := range items {
		line := row{
			number:   index + 1,
			name:     pdf.SplitText(printable(item.Name), nameEnd-numberEnd-2*cellPadding),
			quantity: pdf.SplitText(printable(item.Quantity), quantityEnd-nameEnd-2*cellPadding),
		}
		lines := max(len(line.name), len(line.quantity))
		line.height = max(float64(lines)*textLineHeight+2*cellPadding, minRowHeight)

		if used+line.height > room {
			pages = append(pages, current)
			current, used = []row{}, 0
			room = tableBottom - nextTableTop - headerHeight
		}
		current = append(current, line)
		used += line.height
	}
	return append(pages, current)
}

func drawTable(pdf *fpdf.Fpdf, top float64, rows []row) {
	bodyTop := top + headerHeight

	pdf.SetLineWidth(thickLine)
	pdf.Line(left, top, right, top)
	pdf.Line(left, bodyTop, right, bodyTop)

	pdf.SetLineWidth(midLine)
	for _, x := range []float64{numberEnd, nameEnd, quantityEnd, priceEnd} {
		pdf.Line(x, top, x, tableBottom)
	}

	middle := top + headerHeight/2 + 1.5
	pdf.SetFont(family, "", 11)
	drawCentred(pdf, "№№", left, numberEnd, middle-2)
	pdf.SetFont(family, "", 9)
	drawCentred(pdf, "п. п.", left, numberEnd, middle+2)
	pdf.SetFont(family, "", 11)
	drawCentred(pdf, "НАИМЕНОВАНИЕ", numberEnd, nameEnd, middle)
	drawCentred(pdf, "Кол-во", nameEnd, quantityEnd, middle)
	drawCentred(pdf, "Цена", quantityEnd, priceEnd, middle)
	drawCentred(pdf, "Сумма", priceEnd, right, middle)

	pdf.SetFont(family, "", textSize)
	y := bodyTop
	for _, line := range rows {
		first := y + cellPadding + textLineHeight - 1
		drawCentred(pdf, fmt.Sprint(line.number), left, numberEnd, first)
		for index, text := range line.name {
			pdf.Text(numberEnd+cellPadding, first+float64(index)*textLineHeight, text)
		}
		for index, text := range line.quantity {
			drawCentred(pdf, text, nameEnd, quantityEnd, first+float64(index)*textLineHeight)
		}
		y += line.height
		pdf.SetLineWidth(thinLine)
		pdf.Line(left, y, right, y)
	}

	// the rest of the sheet stays a ruled form, so staff can add a line by hand as they do on paper
	pdf.SetLineWidth(thinLine)
	for y += minRowHeight; y <= tableBottom-minRowHeight/2; y += minRowHeight {
		pdf.Line(left, y, right, y)
	}
}

func drawPhoto(pdf *fpdf.Fpdf, photo []byte) error {
	const padding = 2.0
	top, bottom := firstTableTop, tableBottom

	pdf.SetLineWidth(thickLine)
	pdf.Line(left, top, right, top)
	pdf.Line(left, bottom, right, bottom)

	options := fpdf.ImageOptions{ImageType: "JPEG"}
	info := pdf.RegisterImageOptionsReader("list", options, bytes.NewReader(photo))
	if err := pdf.Error(); err != nil {
		return fmt.Errorf("waybill: reading the photo: %w", err)
	}

	areaWidth, areaHeight := right-left-2*padding, bottom-top-2*padding
	scale := min(areaWidth/info.Width(), areaHeight/info.Height())
	width, height := info.Width()*scale, info.Height()*scale
	pdf.ImageOptions("list", left+padding+(areaWidth-width)/2, top+padding+(areaHeight-height)/2, width, height,
		false, options, 0, "")
	return nil
}

func drawSignatures(pdf *fpdf.Fpdf) {
	const baseline, caption = 270.0, 273.5

	pdf.SetFont(family, "B", 11)
	pdf.Text(19, baseline, "Сдал:")
	pdf.Text(107, baseline, "Принял:")

	pdf.SetLineWidth(thinLine)
	for _, span := range [][2]float64{{33, 53}, {56, 104}, {126, 145}, {149, 195}} {
		pdf.Line(span[0], baseline, span[1], baseline)
	}

	pdf.SetFont(family, "", 8)
	drawCentred(pdf, "подпись", 33, 53, caption)
	drawCentred(pdf, "расшифровка подписи", 56, 104, caption)
	drawCentred(pdf, "подпись", 126, 145, caption)
	drawCentred(pdf, "расшифровка подписи", 149, 195, caption)
}

// printable drops what the font cannot draw. **an emoji in a product name is not hypothetical**, and the
// PDF writer prints a rune missing from the font as a wrong glyph or nothing, depending on the viewer.
func printable(text string) string {
	var buffer sfnt.Buffer
	return strings.Map(func(r rune) rune {
		index, err := regularGlyphs.GlyphIndex(&buffer, r)
		if err != nil || index == 0 {
			return -1
		}
		return r
	}, text)
}
