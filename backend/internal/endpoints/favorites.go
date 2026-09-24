package endpoints

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5/pgconn"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
)

// the heart on a product tile:
//
//	GET    /api/favorites       - everything this caller saved, newest first
//	PUT    /api/favorites/{id}  - save one product
//	DELETE /api/favorites/{id}  - unsave it
//
// **there is no id in the list path and none in the body**: the set belongs to whoever RequireAuth
// says is calling, so nothing here can name somebody else's.
//
// the app holds the whole list and paints the hearts from it, which is why there is no per-product
// "is this saved" field on ProductResponse - one would make every product list depend on the caller
// and take the browsing reads out of publicCache.
type Favorites struct {
	Queries *db.Queries
	URLs    imagestore.URLs
}

// a grid nobody scrolls to the end of, and the whole list is one request the app makes on sign-in
const favoritesLimit = 200

func (f *Favorites) Route(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		f.List(w, r)
		return
	}
	w.WriteHeader(http.StatusMethodNotAllowed)
}

func (f *Favorites) RouteByID(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPut:
		f.Add(w, r)
	case http.MethodDelete:
		f.Remove(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (f *Favorites) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := f.Queries.ListFavorites(ctx, db.ListFavoritesParams{UserID: userID, Limit: favoritesLimit})
	if err != nil {
		if callerGone(r) {
			return
		}
		log.Printf("CRITICAL: could not load the favorites of user %d: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load favorites")
		return
	}

	// zero-length rather than nil: a nil marshals to `null` and the app decodes this as a list
	products := make([]CategoryProductResponse, 0, len(rows))
	for _, row := range rows {
		// field-for-field the same row the category listing returns, so the conversion is checked by
		// the compiler and both share one mapper
		products = append(products, categoryProductFromRow(f.URLs, db.ListProductsByCategoryRow(row)))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(products)
}

func (f *Favorites) Add(w http.ResponseWriter, r *http.Request) {
	userID, productID, ok := f.target(w, r)
	if !ok {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	if err := f.Queries.AddFavorite(ctx, db.AddFavoriteParams{UserID: userID, ProductID: productID}); err != nil {
		// the foreign key is what answers "does this product exist", rather than a read before the
		// write that could not exclude a deletion in between anyway
		if isForeignKeyViolation(err) {
			writeAPIError(w, http.StatusNotFound, "product_not_found", "product not found")
			return
		}
		log.Printf("CRITICAL: user %d could not save product %d: %v", userID, productID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not save the product")
		return
	}

	writeFavorite(w, productID, true)
}

func (f *Favorites) Remove(w http.ResponseWriter, r *http.Request) {
	userID, productID, ok := f.target(w, r)
	if !ok {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	if err := f.Queries.RemoveFavorite(ctx, db.RemoveFavoriteParams{UserID: userID, ProductID: productID}); err != nil {
		log.Printf("CRITICAL: user %d could not unsave product %d: %v", userID, productID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not remove the product")
		return
	}

	// removing what was never there is a success: the caller asked for a state, and it holds
	writeFavorite(w, productID, false)
}

func (f *Favorites) target(w http.ResponseWriter, r *http.Request) (userID, productID int64, ok bool) {
	userID, ok = auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
		return 0, 0, false
	}

	productID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || productID <= 0 {
		writeAPIError(w, http.StatusBadRequest, "invalid_product_id", "invalid product id")
		return 0, 0, false
	}
	return userID, productID, true
}

// both verbs answer with the state they left behind, so the app can settle an optimistic tap on the
// server's word rather than on which request it sent
func writeFavorite(w http.ResponseWriter, productID int64, saved bool) {
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"product_id": productID, "favorite": saved})
}

// 23503 is the SQLSTATE for a foreign key violation - matched on the code, not the message, which is
// localized by the server's lc_messages
func isForeignKeyViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23503"
}
