package catalog

import "strings"

// **add a line here when the letter rules below spell a word wrong** - they handle everything else:
// "plitka" -> "плитка", "samorez" -> "саморез", "molotok" -> "молоток"
var latinAliases = map[string]string{
	"sement":       "цемент", // uzbek spelling; the rules would give "семент"
	"elektr":       "электр",
	"vyklyuchatel": "выключател",
	"viklyuchatel": "выключател",
	"shpaklevka":   "шпатлевка",
}

// tried in order, so "sh" is read before "s"
var latinDigraphs = [][2]string{
	{"shch", "щ"}, {"sch", "щ"}, {"sh", "ш"}, {"ch", "ч"}, {"zh", "ж"}, {"kh", "х"},
	{"ts", "ц"}, {"ya", "я"}, {"yu", "ю"}, {"yo", "е"}, {"ye", "е"}, {"o'", "у"}, {"g'", "г"},
}

var latinLetters = map[rune]rune{
	'a': 'а', 'b': 'б', 'c': 'ц', 'd': 'д', 'e': 'е', 'f': 'ф', 'g': 'г', 'h': 'х', 'i': 'и',
	'j': 'ж', 'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н', 'o': 'о', 'p': 'п', 'q': 'к', 'r': 'р',
	's': 'с', 't': 'т', 'u': 'у', 'v': 'в', 'w': 'в', 'x': 'х', 'y': 'й', 'z': 'з',
}

// spells a latin word the way the catalogue writes it, or "" when it has no latin letters. the word
// must already be lowercased, and "ё" is written as "е", as the search index has it.
func Cyrillic(word string) string {
	if !strings.ContainsFunc(word, isLatin) {
		return ""
	}
	if alias, ok := latinAliases[word]; ok {
		return alias
	}

	out := word
	for _, pair := range latinDigraphs {
		out = strings.ReplaceAll(out, pair[0], pair[1])
	}

	var b strings.Builder
	for _, r := range out {
		if cyrillic, ok := latinLetters[r]; ok {
			b.WriteRune(cyrillic)
		} else {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func isLatin(r rune) bool {
	_, ok := latinLetters[r]
	return ok
}
