package endpoints

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
)

// GET /api/shops (public - the map needs to see every shop) and POST /api/shops (a logged-in
// shop_owner adding their own shop). see db/queries/shops.sql for how the postgis location column
// is read and written.
type Shops struct {
	Queries   *db.Queries
	JWTSecret string
}

// what we send back to flutter for a single shop - a clean shape independent of sqlc's generated row
// types, so the two near-identical CreateShopRow / ListShopsRow structs don't leak their pgtype
// wrapper types over the wire
type ShopResponse struct {
	ID              int64   `json:"id"`
	Name            string  `json:"name"`
	ContactPhone    string  `json:"contact_phone"`
	ImageURL        string  `json:"image_url,omitempty"`
	Address         string  `json:"address"`
	Rating          float64 `json:"rating"`
	AveragePaycheck int64   `json:"average_paycheck"`
	Latitude        float64 `json:"latitude"`
	Longitude       float64 `json:"longitude"`
}

// dispatches by method, since GET and POST share the same url but need very different handling
// (list is public, create requires a logged-in shop owner)
func (s *Shops) Route(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.List(w, r)
	case http.MethodPost:
		// only shop owners with a valid session may create a shop; RequireAuth checks the jwt before we touch the db
		auth.RequireAuth(s.JWTSecret, s.Create)(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed) // error 405
	}
}

// public, unauthenticated: used by the map screen to plot every shop as a pin
func (s *Shops) List(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	shops, err := s.Queries.ListShops(ctx)
	if err != nil {
		log.Printf("CRITICAL: failed to list shops: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "failed to load shops"})
		return
	}

	response := make([]ShopResponse, 0, len(shops))
	for _, shop := range shops {
		ratingF8, _ := shop.Rating.Float64Value()
		response = append(response, ShopResponse{
			ID:              shop.ID,
			Name:            shop.Name,
			ContactPhone:    shop.ContactPhone,
			ImageURL:        shop.ImageUrl.String,
			Address:         shop.Address,
			Rating:          ratingF8.Float64,
			AveragePaycheck: int64(shop.AveragePaycheck),
			Latitude:        shop.Latitude,
			Longitude:       shop.Longitude,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// authenticated: reads the json body flutter sends from the "add store" screen (name, contact
// number, picked map location) and creates the shop.
func (s *Shops) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(map[string]string{"error": "unauthorized"})
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// being logged in only proves who you are (authentication) - this checks what you're allowed to do
	// (authorization): the "add store" button is already hidden from customers in the app, but that's
	// just ui; a customer could still call this endpoint directly with their own valid token otherwise.
	// role isn't carried on the request (see internal/auth/jwt.go) since it can change after login, so
	// this looks up the user's current role fresh instead of trusting a claim that might be stale.
	role, err := s.Queries.GetUserRole(ctx, userID)
	if err != nil {
		log.Printf("CRITICAL: failed to look up role for user %d: %v", userID, err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "failed to verify permissions"})
		return
	}
	if role != "shop_owner" && role != "admin" {
		w.WriteHeader(http.StatusForbidden)
		json.NewEncoder(w).Encode(map[string]string{"error": "only shop owners can create a shop"})
		return
	}

	var req struct {
		Name         string  `json:"name"`
		ContactPhone string  `json:"contact_phone"`
		Address      string  `json:"address"`
		Latitude     float64 `json:"latitude"`
		Longitude    float64 `json:"longitude"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "invalid json body"})
		return
	}

	name := strings.TrimSpace(req.Name)
	contactPhone := strings.TrimSpace(req.ContactPhone)
	address := strings.TrimSpace(req.Address)

	if name == "" || contactPhone == "" || address == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "name, contact_phone and address are required"})
		return
	}

	shop, err := s.Queries.CreateShop(ctx, db.CreateShopParams{
		UserID:       userID,
		Name:         name,
		ContactPhone: contactPhone,
		Address:      address,
		// st_makepoint wants (longitude, latitude) in that order - see the comment in shops.sql
		StMakepoint:   req.Longitude,
		StMakepoint_2: req.Latitude,
	})
	if err != nil {
		log.Printf("CRITICAL: failed to create shop for user %d: %v", userID, err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "failed to create shop"})
		return
	}

	ratingF8, _ := shop.Rating.Float64Value()
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(ShopResponse{
		ID:              shop.ID,
		Name:            shop.Name,
		ContactPhone:    shop.ContactPhone,
		ImageURL:        shop.ImageUrl.String,
		Address:         shop.Address,
		Rating:          ratingF8.Float64,
		AveragePaycheck: int64(shop.AveragePaycheck),
		Latitude:        shop.Latitude,
		Longitude:       shop.Longitude,
	})
}
