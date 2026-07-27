package endpoints

import "testing"

// the price column is the single most fragile input in the whole upload: excelize gives us whatever
// text the owner's cell formatting produced, and a parser that rejects a shape silently drops that
// product. every case below is a real spreadsheet shape, not a hypothetical.
func TestParsePrice(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want int64
		ok   bool
	}{
		{"plain integer", "45000", 45000, true},
		{"currency formatted", "1,250,000.00", 1250000, true},
		{"float from a numeric cell", "45000.5", 45001, true},
		{"ru locale thousands dots", "1.250.000", 1250000, true},
		{"comma thousands", "150,000", 150000, true},
		{"space thousands", "150 000", 150000, true},
		{"nbsp thousands", "150 000", 150000, true},
		{"narrow nbsp thousands", "150 000", 150000, true},
		{"ru decimal comma", "150,50", 151, true},
		{"mixed separators", "45 000,50", 45001, true},
		{"surrounding whitespace", "  45000  ", 45000, true},
		{"zero", "0", 0, true},

		{"empty", "", 0, false},
		{"negative", "-100", 0, false},
		{"not a number", "договорная", 0, false},
		{"trailing separator", "150.", 0, false},
		{"absurdly large", "9999999999999999999", 0, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := parsePrice(tc.raw)
			if ok != tc.ok {
				t.Fatalf("parsePrice(%q) ok = %v, want %v", tc.raw, ok, tc.ok)
			}
			if ok && got != tc.want {
				t.Errorf("parsePrice(%q) = %d, want %d", tc.raw, got, tc.want)
			}
		})
	}
}

func TestParseAvailability(t *testing.T) {
	cases := []struct {
		raw  string
		want string
		ok   bool
	}{
		{"Есть", "in_stock", true},
		{"есть", "in_stock", true},
		{"  В наличии  ", "in_stock", true},
		{"Под заказ", "on_order", true},
		{"под  заказ", "on_order", true}, // doubled inner space
		{"Нет", "unavailable", true},
		{"отсутствует", "unavailable", true},
		{"Yo‘q", "unavailable", true}, // uzbek with a typographic apostrophe
		{"mavjud", "in_stock", true},

		{"", "", false},
		{"может быть", "", false},
	}

	for _, tc := range cases {
		t.Run(tc.raw, func(t *testing.T) {
			got, ok := parseAvailability(tc.raw)
			if ok != tc.ok {
				t.Fatalf("parseAvailability(%q) ok = %v, want %v", tc.raw, ok, tc.ok)
			}
			if got != tc.want {
				t.Errorf("parseAvailability(%q) = %q, want %q", tc.raw, got, tc.want)
			}
		})
	}
}

// a value wider than its postgres column used to abort the shared transaction and discard the whole
// file; it has to read as one skipped row instead.
func TestParseProductRowRejectsOverlongValues(t *testing.T) {
	longName := make([]rune, maxNameLen+1)
	for i := range longName {
		longName[i] = 'ц' // cyrillic: two bytes per character, so len() and rune count disagree
	}

	valid := []string{"Цемент", "Цемент М400", "45000", "шт", "Есть", "ART-001"}
	if _, ok := parseProductRow(valid); !ok {
		t.Fatalf("expected the baseline row to parse")
	}

	overlong := append([]string(nil), valid...)
	overlong[1] = string(longName)
	if _, ok := parseProductRow(overlong); ok {
		t.Errorf("expected a row with an over-length name to be skipped")
	}
}

func TestParseProductRowRequiresEveryColumn(t *testing.T) {
	short := []string{"Цемент", "Цемент М400", "45000", "шт", "Есть"} // no Артикул column at all
	if _, ok := parseProductRow(short); ok {
		t.Errorf("expected a row missing a column to be skipped")
	}

	blankArticle := []string{"Цемент", "Цемент М400", "45000", "шт", "Есть", "   "}
	if _, ok := parseProductRow(blankArticle); ok {
		t.Errorf("expected a row with a blank article to be skipped")
	}
}

func TestIsBlankRow(t *testing.T) {
	if !isBlankRow([]string{}) {
		t.Errorf("an empty row should read as blank")
	}
	if !isBlankRow([]string{"", "  ", ""}) {
		t.Errorf("a whitespace-only row should read as blank")
	}
	if isBlankRow([]string{"", "Цемент", ""}) {
		t.Errorf("a row with any content should not read as blank")
	}
}
