package waybill

import (
	"bytes"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

func sampleDocument() Document {
	return Document{
		Number: 1042,
		Date:   time.Date(2026, time.November, 2, 9, 30, 0, 0, time.UTC),
		To:     "Domix, магазины «Сантехника»",
		From:   "Азиз Рихсиев, +998 90 123 45 67",
	}
}

func pageCount(t *testing.T, pdf []byte) int {
	t.Helper()
	if !bytes.HasPrefix(pdf, []byte("%PDF-")) {
		t.Fatalf("not a pdf: %q", pdf[:min(len(pdf), 16)])
	}
	return len(regexp.MustCompile(`/Type\s*/Page\b`).FindAll(pdf, -1))
}

// keeps the rendered samples for a human to open: WAYBILL_SAMPLES=/tmp/x go test ./internal/waybill
func keepSample(t *testing.T, name string, pdf []byte) {
	t.Helper()
	if dir := os.Getenv("WAYBILL_SAMPLES"); dir != "" {
		if err := os.WriteFile(filepath.Join(dir, name), pdf, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestAShortListFillsOneFormWithRoomLeft(t *testing.T) {
	doc := sampleDocument()
	doc.Items = []Item{
		{Name: "Смеситель для кухни однорычажный", Quantity: "2 шт"},
		{Name: "Труба PPR 25 мм", Quantity: "40 м"},
		{Name: "Oʻzbekcha: gʻisht, ғишт, қум, ҳовли, ўн", Quantity: "10 ta"},
	}
	pdf, err := Render(doc)
	if err != nil {
		t.Fatal(err)
	}
	keepSample(t, "short.pdf", pdf)
	if got := pageCount(t, pdf); got != 1 {
		t.Errorf("%d pages, want 1", got)
	}
}

// the longest list the api accepts, each line the longest it accepts. a row that outgrew its sheet would
// run over the signatures, and only a list this long would ever show it.
func TestTheLongestListContinuesOntoFurtherSheets(t *testing.T) {
	doc := sampleDocument()
	for range 100 {
		doc.Items = append(doc.Items, Item{
			Name:     strings.Repeat("Цементно-песчаная смесь ", 7)[:150],
			Quantity: strings.Repeat("9", 30),
		})
	}
	pdf, err := Render(doc)
	if err != nil {
		t.Fatal(err)
	}
	keepSample(t, "long.pdf", pdf)
	if got := pageCount(t, pdf); got < 2 {
		t.Errorf("%d pages for a hundred long rows, want several", got)
	}

	printed := 0
	for _, page := range paginate(newSheet(), doc.Items) {
		printed += len(page)
	}
	if printed != len(doc.Items) {
		t.Errorf("%d rows printed of %d", printed, len(doc.Items))
	}
}

func TestAPhotoListPrintsThePhotoOnTheForm(t *testing.T) {
	var photo bytes.Buffer
	img := image.NewRGBA(image.Rect(0, 0, 1500, 2000))
	draw.Draw(img, img.Bounds(), image.NewUniform(color.RGBA{240, 236, 220, 255}), image.Point{}, draw.Src)
	if err := jpeg.Encode(&photo, img, nil); err != nil {
		t.Fatal(err)
	}

	doc := sampleDocument()
	doc.Photo = photo.Bytes()
	pdf, err := Render(doc)
	if err != nil {
		t.Fatal(err)
	}
	keepSample(t, "photo.pdf", pdf)
	if got := pageCount(t, pdf); got != 1 {
		t.Errorf("%d pages, want 1", got)
	}
	if !bytes.Contains(pdf, []byte("/DCTDecode")) {
		t.Error("the photo is not embedded")
	}
}

func TestABrokenPhotoIsAnErrorRatherThanABlankForm(t *testing.T) {
	doc := sampleDocument()
	doc.Photo = []byte("not a jpeg")
	if _, err := Render(doc); err == nil {
		t.Fatal("rendered a form around a photo that cannot be read")
	}
}

// a customer can type anything into a name, and the emoji must neither crash the render nor reach the page
func TestPrintableKeepsTheAlphabetsAndDropsWhatTheFontLacks(t *testing.T) {
	for input, want := range map[string]string{
		"Цемент М400":        "Цемент М400",
		"gʻisht":             "gʻisht",
		"ғишт қум ҳовли ўн":  "ғишт қум ҳовли ўн",
		"Плитка 🧱 белая":     "Плитка  белая",
		"«Кабель» №3 — 10 м": "«Кабель» №3 — 10 м",
	} {
		if got := printable(input); got != want {
			t.Errorf("printable(%q) = %q, want %q", input, got, want)
		}
	}

	doc := sampleDocument()
	doc.Items = []Item{{Name: "🧱🧱🧱", Quantity: "🧱"}}
	if _, err := Render(doc); err != nil {
		t.Fatal(err)
	}
}
