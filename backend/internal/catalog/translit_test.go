package catalog

import "testing"

// the letter rules, and the alias list for the words they would spell wrong
func TestCyrillicSpellsLatinWords(t *testing.T) {
	cases := map[string]string{
		"kabel":      "кабел",
		"plitka":     "плитка",
		"samorez":    "саморез",
		"shpatlevka": "шпатлевка",
		"sement":     "цемент", // alias: the rules would give "семент"
		"кабель":     "",       // nothing latin in it
	}

	for word, want := range cases {
		if got := Cyrillic(word); got != want {
			t.Errorf("Cyrillic(%q) = %q, want %q", word, got, want)
		}
	}
}
