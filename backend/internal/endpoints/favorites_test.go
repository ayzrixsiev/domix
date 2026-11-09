package endpoints

// A favourite is a pointer from one account to one shop's product row. What matters is that it
// belongs to exactly that account, that a double tap is not an error, and that it does not outlive
// the product it points at.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/auth"
)

func itoa(id int64) string { return strconv.FormatInt(id, 10) }

func favoritesUnderTest(t *testing.T) (*Favorites, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	_, ctx, tx, q := homeUnderTest(t)
	return &Favorites{Queries: q}, ctx, tx, q
}

// through the real RequireAuth with a real token, because the handler reads its user id off the
// context the middleware fills
func requestFavorite(t *testing.T, ctx context.Context, f *Favorites, method, target string, asUserID int64, handler http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "998900000000", 0, testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	req := httptest.NewRequestWithContext(ctx, method, target, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	if id := lastPathSegment(target); id != "" {
		req.SetPathValue("id", id)
	}

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, f.Queries, handler)(rec, req)
	return rec
}

func savedProductIDs(t *testing.T, ctx context.Context, f *Favorites, asUserID int64) []int64 {
	t.Helper()

	rec := requestFavorite(t, ctx, f, http.MethodGet, "/api/favorites", asUserID, f.Route)
	if rec.Code != http.StatusOK {
		t.Fatalf("listing favorites answered %d: %s", rec.Code, rec.Body)
	}

	var products []struct {
		ID int64 `json:"id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &products); err != nil {
		t.Fatalf("decode %s: %v", rec.Body, err)
	}

	ids := make([]int64, 0, len(products))
	for _, p := range products {
		ids = append(ids, p.ID)
	}
	return ids
}

// a shop with one priced product, which is the smallest thing a heart can point at
func productToSave(t *testing.T, ctx context.Context, q *db.Queries, ownerName string) (productID int64) {
	t.Helper()

	owner := makeUser(t, ctx, q, ownerName, "shop_owner")
	shop, err := q.CreateShop(ctx, db.CreateShopParams{
		UserID: owner, Name: "Лавка", ContactPhone: "998901112233", Address: "Ташкент",
		Category: "universal", StMakepoint: 69.24, StMakepoint_2: 41.31,
	})
	if err != nil {
		t.Fatalf("creating a shop: %v", err)
	}

	product, err := q.CreateCustomProduct(ctx, db.CreateCustomProductParams{
		ShopID: shop.ID, Name: "Цемент", Category: "mixes", Unit: "мешок", Availability: "in_stock",
		Price: pgtype.Int8{Int64: 52000, Valid: true},
	})
	if err != nil {
		t.Fatalf("creating a product: %v", err)
	}
	return product.ID
}

// **the whole point of the table.** two people saving from the same grid must not see each other's
// hearts, and there is no id in the list path that could ask for somebody else's.
func TestOneAccountsFavoritesAreItsOwn(t *testing.T) {
	favorites, ctx, _, q := favoritesUnderTest(t)

	productID := productToSave(t, ctx, q, "Owner")
	mine := makeUser(t, ctx, q, "Mine", "customer")
	theirs := makeUser(t, ctx, q, "Theirs", "customer")

	target := "/api/favorites/" + itoa(productID)
	if rec := requestFavorite(t, ctx, favorites, http.MethodPut, target, mine, favorites.RouteByID); rec.Code != http.StatusOK {
		t.Fatalf("saving answered %d: %s", rec.Code, rec.Body)
	}

	if got := savedProductIDs(t, ctx, favorites, mine); len(got) != 1 || got[0] != productID {
		t.Fatalf("my favorites are %v, want [%d]", got, productID)
	}
	if got := savedProductIDs(t, ctx, favorites, theirs); len(got) != 0 {
		t.Fatalf("somebody else's account sees %v", got)
	}
}

// the app toggles optimistically, so a retry after a dropped answer arrives as a second save
func TestSavingTwiceIsNotAnErrorAndDoesNotDuplicate(t *testing.T) {
	favorites, ctx, _, q := favoritesUnderTest(t)

	productID := productToSave(t, ctx, q, "Owner")
	mine := makeUser(t, ctx, q, "Mine", "customer")
	target := "/api/favorites/" + itoa(productID)

	for range 2 {
		if rec := requestFavorite(t, ctx, favorites, http.MethodPut, target, mine, favorites.RouteByID); rec.Code != http.StatusOK {
			t.Fatalf("saving answered %d: %s", rec.Code, rec.Body)
		}
	}
	if got := savedProductIDs(t, ctx, favorites, mine); len(got) != 1 {
		t.Fatalf("two saves left %d rows", len(got))
	}

	// and removing what is already gone is a success too - the caller asked for a state
	for range 2 {
		if rec := requestFavorite(t, ctx, favorites, http.MethodDelete, target, mine, favorites.RouteByID); rec.Code != http.StatusOK {
			t.Fatalf("removing answered %d: %s", rec.Code, rec.Body)
		}
	}
	if got := savedProductIDs(t, ctx, favorites, mine); len(got) != 0 {
		t.Fatalf("after removing, favorites are %v", got)
	}
}

// **a saved card has to open onto something.** the shop stops selling the item, the row goes, and
// the favourite goes with it rather than becoming a tile that leads nowhere.
func TestAFavoriteDiesWithTheProductItPointsAt(t *testing.T) {
	favorites, ctx, tx, q := favoritesUnderTest(t)

	productID := productToSave(t, ctx, q, "Owner")
	mine := makeUser(t, ctx, q, "Mine", "customer")

	requestFavorite(t, ctx, favorites, http.MethodPut, "/api/favorites/"+itoa(productID), mine, favorites.RouteByID)
	if got := savedProductIDs(t, ctx, favorites, mine); len(got) != 1 {
		t.Fatalf("the product was not saved")
	}

	if _, err := tx.Exec(ctx, "DELETE FROM products WHERE id = $1", productID); err != nil {
		t.Fatalf("deleting the product: %v", err)
	}

	if got := savedProductIDs(t, ctx, favorites, mine); len(got) != 0 {
		t.Fatalf("the favorite outlived its product: %v", got)
	}
}

func TestSavingAProductThatDoesNotExistIsA404(t *testing.T) {
	favorites, ctx, _, q := favoritesUnderTest(t)
	mine := makeUser(t, ctx, q, "Mine", "customer")

	rec := requestFavorite(t, ctx, favorites, http.MethodPut, "/api/favorites/999999999", mine, favorites.RouteByID)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("answered %d, want 404: %s", rec.Code, rec.Body)
	}
}
