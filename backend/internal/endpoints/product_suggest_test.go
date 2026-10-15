package endpoints

// the http half of the as-you-type panel. no database and no fixtures: SuggestProducts reads
// internal/catalog's in-memory copy, which is the whole point of the endpoint.

import (
	"context"
	"net/http"
	"net/url"
	"strings"
	"testing"

	"domix/backend/internal/catalog"
)

func suggestUnderTest() *Home {
	catalog.Load([]catalog.Row{
		{ShopCategory: "universal", Key: "u.cement", Name: "Цемент М400", Specs: "50 кг",
			Category: "mixes", Unit: "мешок"},
		{ShopCategory: "universal", Key: "u.cable", Name: "Кабель ПВС", Specs: "2 × 1,5 мм² · Медный",
			Category: "electrics", Unit: "м"},
	})
	return &Home{}
}

func suggestURL(query string) string {
	return "/api/products/suggest?q=" + url.QueryEscape(query)
}

func TestSuggestAnswersWithTheNamesMatchingTheQuery(t *testing.T) {
	home := suggestUnderTest()

	var names []string
	rec := getJSON(t, context.Background(), home.SuggestProducts, suggestURL("цем"), &names)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if len(names) != 1 || names[0] != "Цемент М400" {
		t.Fatalf("want the one matching name, got %v", names)
	}
}

// **the body has to be `[]` and never `null`**: the app decodes it with `as List<dynamic>`, and a
// null is a crash on the one path every half-typed word takes
func TestSuggestAnswersAnEmptyListForAQueryTooShortToLookUp(t *testing.T) {
	home := suggestUnderTest()

	rec := getJSON(t, context.Background(), home.SuggestProducts, suggestURL("це"), nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200 while a word is still being typed, got %d", rec.Code)
	}
	if body := strings.TrimSpace(rec.Body.String()); body != "[]" {
		t.Fatalf("want an empty json array, got %q", body)
	}
}

func TestSuggestRefusesAQueryLongerThanTheSearchAccepts(t *testing.T) {
	home := suggestUnderTest()

	rec := getJSON(t, context.Background(), home.SuggestProducts, suggestURL(strings.Repeat("ц", 61)), nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body.String())
	}
}
