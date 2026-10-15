package catalog

import (
	"slices"
	"strconv"
	"testing"
)

// the catalogue these tests suggest from: names chosen here, so an assertion is about matching and
// not about whatever product_templates happens to hold today.
func loadSuggestionCatalogue(specs ...[2]string) {
	rows := make([]Row, 0, len(specs))
	for i, pair := range specs {
		rows = append(rows, Row{
			ShopCategory: "universal", Key: "k" + strconv.Itoa(i),
			Name: pair[0], Specs: pair[1], Category: "tools", Unit: "шт",
		})
	}
	Load(rows)
}

func suggested(t *testing.T, query string) []string {
	t.Helper()
	return Suggest(query, 8)
}

func TestSuggestMatchesEveryWordInAnyOrder(t *testing.T) {
	loadSuggestionCatalogue(
		[2]string{"Кабель ПВС", "2 × 1,5 мм² · Медный"},
		[2]string{"Кабель ВВГ", "3 × 2,5 мм²"},
	)

	if got := suggested(t, "пвс кабель"); !slices.Equal(got, []string{"Кабель ПВС"}) {
		t.Fatalf("want the one name holding both words, got %v", got)
	}
}

// the size lives in specs, and the search matches against it, so the panel has to offer the name
// whose size was typed - or the field disagrees with the results it leads to
func TestSuggestMatchesAWordOnlyTheSizeHolds(t *testing.T) {
	loadSuggestionCatalogue(
		[2]string{"Кабель ПВС", "2 × 1,5 мм² · Медный"},
		[2]string{"Кабель ВВГ", "3 × 2,5 мм² · Алюминиевый"},
	)

	if got := suggested(t, "медный"); !slices.Equal(got, []string{"Кабель ПВС"}) {
		t.Fatalf("want the name whose specs hold the word, got %v", got)
	}
}

// one size is one template row, and the panel is a list of *names*: two sizes of one product must
// be one row in it, and either size must still find it
func TestSuggestOffersOneRowPerNameAndKeepsEverySize(t *testing.T) {
	loadSuggestionCatalogue(
		[2]string{"Шпатлёвка суперфинишная", "20 кг"},
		[2]string{"Шпатлёвка суперфинишная", "5 кг · Элерон"},
	)

	if got := suggested(t, "шпатлевка"); !slices.Equal(got, []string{"Шпатлёвка суперфинишная"}) {
		t.Fatalf("want one row for the two sizes, got %v", got)
	}
	if got := suggested(t, "элерон"); len(got) != 1 {
		t.Fatalf("the second size's specs were dropped: %v", got)
	}
}

func TestSuggestReadsALatinQueryAsCyrillic(t *testing.T) {
	loadSuggestionCatalogue([2]string{"Цемент М400", "50 кг"})

	if got := suggested(t, "sement"); !slices.Equal(got, []string{"Цемент М400"}) {
		t.Fatalf("a latin query found nothing: %v", got)
	}
}

// the name that opens with what was typed leads, then the shortest - the general product above a
// brand's or a size's version of it
func TestSuggestLeadsWithTheNameThatOpensWithTheQuery(t *testing.T) {
	loadSuggestionCatalogue(
		[2]string{"VERO (к) Клипса 100", ""},
		[2]string{"Клипса", ""},
		[2]string{"Клипса усиленная", ""},
	)

	want := []string{"Клипса", "Клипса усиленная", "VERO (к) Клипса 100"}
	if got := suggested(t, "клипса"); !slices.Equal(got, want) {
		t.Fatalf("want %v, got %v", want, got)
	}
}

// a brand in front of the name is how half the catalogue is written, so «смеситель» has to rank
// those above a name that merely contains the word in the middle of a longer one
func TestSuggestRanksAWordStartAboveABuriedMatch(t *testing.T) {
	loadSuggestionCatalogue(
		[2]string{"Гидросмесительный узел", ""},
		[2]string{"BOOU Смеситель B8156", ""},
	)

	want := []string{"BOOU Смеситель B8156", "Гидросмесительный узел"}
	if got := suggested(t, "смесител"); !slices.Equal(got, want) {
		t.Fatalf("want %v, got %v", want, got)
	}
}

func TestSuggestStopsAtTheLimit(t *testing.T) {
	rows := make([][2]string, 0, 12)
	for i := range 12 {
		rows = append(rows, [2]string{"Кабель " + strconv.Itoa(i), ""})
	}
	loadSuggestionCatalogue(rows...)

	if got := Suggest("кабель", 8); len(got) != 8 {
		t.Fatalf("want 8 names, got %d", len(got))
	}
}

func TestSuggestAnswersNothingForAnEmptyQuery(t *testing.T) {
	loadSuggestionCatalogue([2]string{"Цемент М400", "50 кг"})

	if got := Suggest("   ", 8); len(got) != 0 {
		t.Fatalf("want no suggestions, got %v", got)
	}
}
