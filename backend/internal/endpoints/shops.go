package endpoints

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
	"domix/backend/internal/dbctx"
)

type Shops struct {
	Pool      *pgxpool.Pool
	Queries   *db.Queries
	JWTSecret string
}

func writeShopError(w http.ResponseWriter, status int, code, message string) {
	writeAPIError(w, status, code, message)
}

// dispatches /api/shops
// listing shops for usual users and creating shop for logged in shop owners
func (s *Shops) Route(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.List(w, r)
	case http.MethodPost:
		auth.RequireAuth(s.JWTSecret, s.Queries, s.Create)(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// dispatches /api/shops/{id}
// get the shop from product, modify the shop, delete the shop
func (s *Shops) RouteByID(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.Get(w, r)
	case http.MethodPut:
		auth.RequireAuth(s.JWTSecret, s.Queries, s.Update)(w, r)
	case http.MethodDelete:
		auth.RequireAuth(s.JWTSecret, s.Queries, s.Delete)(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// the shared gate in front of Update and Delete: pull {id} out of the path, then ask
// authorizeShopAccess (authz.go) whether this caller may modify or delete this shop
func (s *Shops) authorizeShopAccess(w http.ResponseWriter, r *http.Request) (shopID int64, ok bool) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeShopError(w, http.StatusUnauthorized, "unauthorized", "unauthorized")
		return 0, false
	}

	shopID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeShopError(w, http.StatusBadRequest, "invalid_shop_id", "invalid shop id")
		return 0, false
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	if accessErr := authorizeShopAccess(ctx, s.Queries, userID, shopID); accessErr != nil {
		accessErr.write(w)
		return 0, false
	}

	return shopID, true
}


func validateShopFieldLengths(name, contactPhone, address string) *accessError {
	const (
		maxShopNameLen  = 150
		maxShopPhoneLen = 50
		maxAddressLen   = 500
	)

	if utf8.RuneCountInString(name) > maxShopNameLen ||
		utf8.RuneCountInString(contactPhone) > maxShopPhoneLen ||
		utf8.RuneCountInString(address) > maxAddressLen {
		return &accessError{http.StatusBadRequest, "field_too_long", "a field is longer than allowed"}
	}

	return nil
}


// public, unauthenticated: get the shop from any listed product by id
func (s *Shops) Get(w http.ResponseWriter, r *http.Request) {
	shopID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeShopError(w, http.StatusBadRequest, "invalid_shop_id", "invalid shop id")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	shop, err := s.Queries.GetShop(ctx, shopID)
	if err != nil {
		// if a shop was deleted while user was inside the shop card, we send 404 instead of 500
		if errors.Is(err, pgx.ErrNoRows) {
			writeShopError(w, http.StatusNotFound, "shop_not_found", "shop not found")
			return
		}
		if callerGone(r) {
			return
		}
		log.Printf("CRITICAL: failed to load shop %d: %v", shopID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to load shop")
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(shopFromList(db.ListShopsRow(shop)))
}

// public, unauthenticated: used by the map screen to plot every shop as a pin
func (s *Shops) List(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	shops, err := s.Queries.ListShops(ctx)
	if err != nil {
		if callerGone(r) {
			return
		}
		log.Printf("CRITICAL: failed to list shops: %v", err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to load shops")
		return
	}

	response := make([]ShopResponse, 0, len(shops))
	for _, shop := range shops {
		response = append(response, shopFromList(shop))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// authenticated: called by "manage my shops" screen, every shop owner owns
func (s *Shops) ListMine(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeShopError(w, http.StatusUnauthorized, "unauthorized", "unauthorized")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	shops, err := s.Queries.ListShopsByOwner(ctx, userID)
	if err != nil {
		log.Printf("CRITICAL: failed to list shops for owner %d: %v", userID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to load shops")
		return
	}

	response := make([]ShopResponse, 0, len(shops))
	for _, shop := range shops {
		response = append(response, shopFromOwned(shop))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// authenticated: reads the json body flutter sends from the "add store" screen (name, contact
// number, picked map location) and creates the shop
func (s *Shops) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeShopError(w, http.StatusUnauthorized, "unauthorized", "unauthorized")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// authorization
	role, err := s.Queries.GetUserRole(ctx, userID)
	if err != nil {
		log.Printf("CRITICAL: failed to look up role for user %d: %v", userID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to verify permissions")
		return
	}
	if role != "shop_owner" && role != "admin" {
		writeShopError(w, http.StatusForbidden, "forbidden_role", "only shop owners can create a shop")
		return
	}

	var req struct {
		Name         string  `json:"name"`
		ContactPhone string  `json:"contact_phone"`
		Address      string  `json:"address"`
		Category     string  `json:"category"`
		Latitude     float64 `json:"latitude"`
		Longitude    float64 `json:"longitude"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	name := strings.TrimSpace(req.Name)
	contactPhone := strings.TrimSpace(req.ContactPhone)
	address := strings.TrimSpace(req.Address)
	category := strings.TrimSpace(req.Category)

	if name == "" || contactPhone == "" || address == "" {
		writeShopError(w, http.StatusBadRequest, "missing_fields", "name, contact_phone and address are required")
		return
	}

	// shop name length validation
	if accessErr := validateShopFieldLengths(name, contactPhone, address); accessErr != nil {
		accessErr.write(w)
		return
	}

	// checking whether shop category is valid
	if !catalog.IsValidCategory(category) {
		writeShopError(w, http.StatusBadRequest, "invalid_category", "unknown shop category")
		return
	}

	if accessErr := validateCoordinates(req.Latitude, req.Longitude); accessErr != nil {
		accessErr.write(w)
		return
	}

	// one transaction for two writes: the shop row, and the category template copied into its
	// product catalogue. without it a failure halfway through would leave a shop that exists but
	// has a half-filled catalogue - and the owner has no way to ask for the rest of it, since
	// seeding only ever happens here, at creation
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		log.Printf("CRITICAL: failed to begin shop creation transaction for user %d: %v", userID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to create shop")
		return
	}
	defer tx.Rollback(ctx)

	qtx := s.Queries.WithTx(tx)

	shop, err := qtx.CreateShop(ctx, db.CreateShopParams{
		UserID:        userID,
		Name:          name,
		ContactPhone:  contactPhone,
		Address:       address,
		Category:      category,
		StMakepoint:   req.Longitude,
		StMakepoint_2: req.Latitude,
	})
	if err != nil {
		log.Printf("CRITICAL: failed to create shop for user %d: %v", userID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to create shop")
		return
	}

	// inserting template products row by row
	template := catalog.Template(category)
	for _, item := range template {
		if err := qtx.SeedTemplateProduct(ctx, db.SeedTemplateProductParams{
			ShopID: 	 shop.ID,
			Name:   	 item.Name,
			Category:    string(item.Category),
			Unit:        item.Unit,
			TemplateKey: pgtype.Text{String: item.Key, Valid: true},
			ImagePath: 	 pgtype.Text{String: item.ImagePath, Valid: item.ImagePath != ""},
		}); err != nil {
			log.Printf("CRITICAL: failed to seed template product %q into shop %d: %v", item.Key, shop.ID, err)
			writeShopError(w, http.StatusInternalServerError, "server_error", "failed to create shop")
			return
		}
	}

	if err := tx.Commit(ctx); err != nil {
		log.Printf("CRITICAL: failed to commit shop creation for user %d: %v", userID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to create shop")
		return
	}

	log.Printf("Shop %d created for user %d (category %s, %d template products)", shop.ID, userID, category, len(template))

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(shopFromCreate(shop, int64(len(template)))) // sending amount of seeded products for flutter to show them
}

// PUT /api/shops/{id} - the "edit shop" form. the form always submits all four editable fields
// and whatever row is missing is not affecting the shop
func (s *Shops) Update(w http.ResponseWriter, r *http.Request) {
	shopID, ok := s.authorizeShopAccess(w, r)
	if !ok {
		return
	}

	var req struct {
		Name         string  `json:"name"`
		ContactPhone string  `json:"contact_phone"`
		Address      string  `json:"address"`
		Latitude     float64 `json:"latitude"`
		Longitude    float64 `json:"longitude"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	name := strings.TrimSpace(req.Name)
	contactPhone := strings.TrimSpace(req.ContactPhone)
	address := strings.TrimSpace(req.Address)

	if name == "" || contactPhone == "" || address == "" {
		writeShopError(w, http.StatusBadRequest, "missing_fields", "name, contact_phone and address are required")
		return
	}

	if accessErr := validateShopFieldLengths(name, contactPhone, address); accessErr != nil {
		accessErr.write(w)
		return
	}

	if accessErr := validateCoordinates(req.Latitude, req.Longitude); accessErr != nil {
		accessErr.write(w)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	shop, err := s.Queries.UpdateShop(ctx, db.UpdateShopParams{
		ID:           shopID,
		Name:         name,
		ContactPhone: contactPhone,
		Address:      address,
		StMakepoint:   req.Longitude,
		StMakepoint_2: req.Latitude,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeShopError(w, http.StatusNotFound, "shop_not_found", "shop not found")
			return
		}
		log.Printf("CRITICAL: failed to update shop %d: %v", shopID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to update shop")
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(shopFromUpdate(shop))
}

// DELETE /api/shops/{id}. the shop's products go with it through products.shop_id ON DELETE CASCADE
func (s *Shops) Delete(w http.ResponseWriter, r *http.Request) {
	shopID, ok := s.authorizeShopAccess(w, r)
	if !ok {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := s.Queries.DeleteShop(ctx, shopID)
	if err != nil {
		log.Printf("CRITICAL: failed to delete shop %d: %v", shopID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to delete shop")
		return
	}
	if rows == 0 {
		writeShopError(w, http.StatusNotFound, "shop_not_found", "shop not found")
		return
	}

	log.Printf("Shop %d deleted", shopID)
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}
