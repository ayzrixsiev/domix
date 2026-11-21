package endpoints

// a shop owner never sees another shop's prices or index. every read here is public, so a check
// that is wrong fails open and nothing on screen says so.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
)

// 0 is a guest: no Authorization header at all
func getAs(t *testing.T, ctx context.Context, handler http.HandlerFunc, target, shopID string, asUserID int64, into any) {
	t.Helper()

	req := httptest.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if shopID != "" {
		req.SetPathValue("id", shopID)
	}
	if asUserID != 0 {
		token, err := auth.GenerateJWT(asUserID, "998900000000", 0, testJWTSecret)
		if err != nil {
			t.Fatalf("sign a token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}

	rec := httptest.NewRecorder()
	handler(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET %s as %d: want 200, got %d: %s", target, asUserID, rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), into); err != nil {
		t.Fatalf("decoding %s: %v\nbody: %s", target, err, rec.Body.String())
	}
}

func TestASellerOpeningAnotherShopSeesNeitherItsPricesNorItsIndex(t *testing.T) {
	_, ctx, tx, q := homeUnderTest(t)
	shops := &Shops{Queries: q, JWTSecret: testJWTSecret}
	products := &Products{Queries: q, JWTSecret: testJWTSecret}

	shopID := makeSeededShop(t, ctx, tx, q, "Чужой", catalog.CategoryWood, false)
	priceAll(t, ctx, tx, shopID, 10_000)
	ownerID, err := q.GetShopOwner(ctx, shopID)
	if err != nil {
		t.Fatalf("owner: %v", err)
	}
	if _, err := tx.Exec(ctx, "UPDATE products SET price = NULL WHERE shop_id = $1 AND template_key IS NULL", shopID); err != nil {
		t.Fatalf("unprice: %v", err)
	}
	totalPriced := 0
	if err := tx.QueryRow(ctx, "SELECT count(*) FROM products WHERE shop_id = $1 AND price IS NOT NULL", shopID).Scan(&totalPriced); err != nil {
		t.Fatalf("count: %v", err)
	}

	rival := makeUser(t, ctx, q, "Соперник", "shop_owner")
	customer := makeUser(t, ctx, q, "Покупатель", "customer")
	admin := makeUser(t, ctx, q, "Админ", "admin")
	id := strconv.FormatInt(shopID, 10)

	var seen ShopResponse
	getAs(t, ctx, shops.Get, "/api/shops/"+id, id, rival, &seen)
	if seen.BasketPrice != nil || seen.PriceTier != nil || seen.PriceDifferencePercent != nil {
		t.Fatalf("a rival seller was shown the index: %+v", seen)
	}

	var rows []ProductResponse
	getAs(t, ctx, products.ListByShop, "/api/shops/"+id+"/products", id, rival, &rows)
	if len(rows) != totalPriced {
		t.Fatalf("a rival seller should get the %d priced rows, got %d", totalPriced, len(rows))
	}
	for _, row := range rows {
		if row.Price != nil || !row.PriceHidden {
			t.Fatalf("a rival seller was shown a price: %+v", row)
		}
	}

	for _, who := range []struct {
		name string
		id   int64
	}{{"guest", 0}, {"customer", customer}, {"admin", admin}, {"the shop's own owner", ownerID}} {
		var shop ShopResponse
		getAs(t, ctx, shops.Get, "/api/shops/"+id, id, who.id, &shop)
		if shop.BasketPrice == nil || shop.PriceTier == nil {
			t.Fatalf("%s must see the index, got %+v", who.name, shop)
		}

		var rows []ProductResponse
		getAs(t, ctx, products.ListByShop, "/api/shops/"+id+"/products", id, who.id, &rows)
		priced := 0
		for _, row := range rows {
			if row.PriceHidden {
				t.Fatalf("%s was told a price is hidden: %+v", who.name, row)
			}
			if row.Price != nil {
				priced++
			}
		}
		if priced != totalPriced {
			t.Fatalf("%s should see %d prices, saw %d", who.name, totalPriced, priced)
		}
	}
}

// **the silent failure is the cache**: one key for both audiences would hand whichever copy was built
// first to everybody for a minute. so both are asked through one real cache, in both orders.
func TestTheCachedReadsKeepASellersCopyApartFromABuyers(t *testing.T) {
	home, ctx, tx, q := homeUnderTest(t)
	home.JWTSecret = testJWTSecret

	shopID := makeSeededShop(t, ctx, tx, q, "Витрина", catalog.CategoryWood, true)
	priceAll(t, ctx, tx, shopID, 10_000)
	seller := makeUser(t, ctx, q, "Продавец", "shop_owner")
	customer := makeUser(t, ctx, q, "Клиент", "customer")

	for _, order := range [][]int64{{customer, seller}, {seller, customer}} {
		cache := NewPublicCache(time.Minute)
		home.Cache = cache
		shops := &Shops{Queries: q, JWTSecret: testJWTSecret, Cache: cache}

		for _, as := range order {
			isSeller := as == seller

			var content HomeResponse
			getAs(t, ctx, home.Get, "/api/home", "", as, &content)
			if content.IndexHidden != isSeller {
				t.Fatalf("index_hidden = %v for seller=%v", content.IndexHidden, isSeller)
			}
			if isSeller && len(content.BestOffers) != 0 {
				t.Fatalf("a seller was sent the ranking: %+v", content.BestOffers)
			}
			if !isSeller && len(content.BestOffers) == 0 {
				t.Fatal("a buyer lost the ranking")
			}
			vip := findShop(content.VipShops, shopID)
			if vip == nil {
				t.Fatalf("the placement is missing for seller=%v", isSeller)
			}
			if (vip.PriceTier != nil) == isSeller {
				t.Fatalf("vip tier = %v for seller=%v", vip.PriceTier, isSeller)
			}

			var pins []ShopResponse
			getAs(t, ctx, shops.List, "/api/shops", "", as, &pins)
			pin := findShop(pins, shopID)
			if pin == nil {
				t.Fatalf("the pin is missing for seller=%v", isSeller)
			}
			if (pin.PriceTier != nil) == isSeller {
				t.Fatalf("pin tier = %v for seller=%v", pin.PriceTier, isSeller)
			}
		}
	}
}

func findShop(shops []ShopResponse, id int64) *ShopResponse {
	for i := range shops {
		if shops[i].ID == id {
			return &shops[i]
		}
	}
	return nil
}
