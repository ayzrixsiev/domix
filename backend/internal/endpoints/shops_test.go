package endpoints

// GET /api/shops/{id} - the one entry point into a shop card that has only an id to go on, which is
// every product tile outside the shop's own page.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"domix/backend/internal/catalog"
)

// **the LEFT JOIN, pinned.** a customer taps a product in a shop whose owner has priced half the
// catalogue; if this endpoint inner-joined the basket index the way the best-offers ranking does,
// that tap would 404 and the shop would look deleted. it opens with no badge instead, which is the
// same nullable-price state the map has always rendered.
func TestAShopOpensFromItsIdBeforeItsBasketIsPriced(t *testing.T) {
	_, ctx, tx, q := homeUnderTest(t)
	shops := &Shops{Queries: q}

	shopID := makeSeededShop(t, ctx, tx, q, "Половина цен", catalog.CategoryWood, false)

	var unpriced ShopResponse
	if rec := getShop(t, ctx, shops, shopID, &unpriced); rec.Code != http.StatusOK {
		t.Fatalf("want 200 for a shop with no basket, got %d: %s", rec.Code, rec.Body.String())
	}
	if unpriced.ID != shopID || unpriced.Name != "Половина цен" {
		t.Fatalf("wrong shop came back: %+v", unpriced)
	}
	if unpriced.BasketPrice != nil || unpriced.PriceTier != nil {
		t.Fatalf("an unpriced shop must carry no comparison, got basket=%v tier=%v",
			unpriced.BasketPrice, unpriced.PriceTier)
	}

	// and once the basket is complete the same url carries the comparison, so the card does not
	// need a second shape
	priceAll(t, ctx, tx, shopID, 10_000)

	var priced ShopResponse
	getShop(t, ctx, shops, shopID, &priced)
	if priced.BasketPrice == nil || priced.PriceTier == nil {
		t.Fatalf("a fully priced shop must carry a basket and a tier, got %+v", priced)
	}
}

// a shop deleted while its products were still on somebody's screen. 404, because nothing is wrong
// here - a 500 would put "что-то пошло не так" in front of a customer whose only mistake was being
// a few seconds late.
func TestAShopThatIsGoneAnswersNotFound(t *testing.T) {
	_, ctx, _, q := homeUnderTest(t)
	shops := &Shops{Queries: q}

	rec := getShop(t, ctx, shops, 999_999_999, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404 for an id that does not exist, got %d: %s", rec.Code, rec.Body.String())
	}
}

// PathValue is set by go's mux from the registered pattern, which httptest does not go through -
// so the test has to put {id} there itself or the handler reads an empty string.
func getShop(t *testing.T, ctx context.Context, shops *Shops, id int64, into any) *httptest.ResponseRecorder {
	t.Helper()

	req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/api/shops/"+strconv.FormatInt(id, 10), nil)
	req.SetPathValue("id", strconv.FormatInt(id, 10))

	rec := httptest.NewRecorder()
	shops.Get(rec, req)

	if into != nil && rec.Code == http.StatusOK {
		if err := json.Unmarshal(rec.Body.Bytes(), into); err != nil {
			t.Fatalf("decoding the shop: %v\nbody: %s", err, rec.Body.String())
		}
	}
	return rec
}
