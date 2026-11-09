package catalog

import (
	"cmp"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"
)

// one name the search field can offer back, with the text a typed query is matched against.
type suggestion struct {
	name string

	// lower(name || ' ' || specs) with ё folded to е - the same text SearchProducts compares in
	// postgres, so a name offered here is a name the search can find.
	haystack string
}

// how a typed query is read everywhere: lowercase, ё written as е. the catalogue spells 19 names
// with ё and nobody types it, so both sides fold it - the trigram index is built on the folded
// expression too.
func QueryWords(query string) []string {
	return strings.Fields(strings.ReplaceAll(strings.ToLower(query), "ё", "е"))
}

// Suggest answers the search field's as-you-type panel with up to `limit` catalogue names, matched
// the way the product search matches: every word a substring, in any order, a latin word also tried
// in its cyrillic spelling.
//
// **it reads the curated catalogue in memory and never the database.** that is what makes a request
// per keystroke affordable - a few hundred substring scans, no connection, no cache. The price is
// that a name an owner typed into their own shop is not offered, and that a suggestion is a name the
// catalogue holds rather than a promise that some shop has priced it.
func Suggest(query string, limit int) []string {
	words := QueryWords(query)
	if len(words) == 0 || limit <= 0 {
		return nil
	}

	// a word and, when it was typed in latin, its cyrillic spelling: either form is a match
	forms := make([][]string, 0, len(words))
	for _, word := range words {
		variants := []string{word}
		if cyrillic := Cyrillic(word); cyrillic != "" && cyrillic != word {
			variants = append(variants, cyrillic)
		}
		forms = append(forms, variants)
	}

	type hit struct {
		name string
		rank int
	}

	mu.RLock()
	defer mu.RUnlock()

	hits := make([]hit, 0, limit)
	for _, item := range suggestionIndex {
		if !matchesAll(item.haystack, forms) {
			continue
		}
		hits = append(hits, hit{name: item.name, rank: rankOf(item, forms[0])})
	}

	// the shortest name of a rank first: it is the general product, and the longer ones are a brand
	// or a size of it - «Клипса» above «VERO (к) Клипса 100»
	slices.SortFunc(hits, func(a, b hit) int {
		if a.rank != b.rank {
			return cmp.Compare(a.rank, b.rank)
		}
		if n := cmp.Compare(utf8.RuneCountInString(a.name), utf8.RuneCountInString(b.name)); n != 0 {
			return n
		}
		return cmp.Compare(a.name, b.name)
	})

	if len(hits) > limit {
		hits = hits[:limit]
	}
	names := make([]string, 0, len(hits))
	for _, h := range hits {
		names = append(names, h.name)
	}
	return names
}

func matchesAll(haystack string, forms [][]string) bool {
	for _, variants := range forms {
		if !slices.ContainsFunc(variants, func(form string) bool {
			return strings.Contains(haystack, form)
		}) {
			return false
		}
	}
	return true
}

// how well the first word typed - the one the customer led with - sits in this name: the name opens
// with it, a word inside it opens with it, or it is buried in the middle of one.
func rankOf(item suggestion, variants []string) int {
	rank := 2
	for _, form := range variants {
		switch {
		case strings.HasPrefix(item.haystack, form):
			return 0
		case startsWord(item.haystack, form):
			rank = 1
		}
	}
	return rank
}

// whether `form` begins a word of `haystack`. anything that is not a letter or a digit opens a word,
// because catalogue names break on punctuation as often as on spaces: «Кабель-канал», «VERO (к)».
func startsWord(haystack, form string) bool {
	for at := 0; ; {
		i := strings.Index(haystack[at:], form)
		if i < 0 {
			return false
		}
		i += at
		before, _ := utf8.DecodeLastRuneInString(haystack[:i])
		if !unicode.IsLetter(before) && !unicode.IsDigit(before) {
			return true
		}
		at = i + 1
	}
}

// the suggestion list, rebuilt by Load from the same rows the templates come from. names repeat
// across sizes and across shop categories, so one entry per name carries every size's specs in its
// haystack: «Кабель ПВС» is offered once and still answers a search for the gauge.
func buildSuggestions(items map[Category][]Item) []suggestion {
	out := make([]suggestion, 0, 256)
	at := map[string]int{}

	for _, category := range AllShopCategories {
		for _, item := range items[category] {
			text := strings.ReplaceAll(strings.ToLower(item.Name+" "+item.Specs), "ё", "е")
			key := strings.ReplaceAll(strings.ToLower(item.Name), "ё", "е")
			if i, known := at[key]; known {
				out[i].haystack += " " + text
				continue
			}
			at[key] = len(out)
			out = append(out, suggestion{name: item.Name, haystack: text})
		}
	}
	return out
}
