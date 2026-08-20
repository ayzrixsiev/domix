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

// the ShopResponse DTO and the mappers that build it from each sqlc row type live in shop_dto.go -
// there are seven of those row types now, and the mapping was the longest thing in this file.

// every shop endpoint will carry erros, we format them cleanly here.
//
// an alias for writeAPIError (authz.go) rather than a second implementation: the two had drifted to
// the same three lines, and two spellings of "how this api reports an error" is how a shop endpoint
// ends up with a response shape the product endpoints don't use.
func writeShopError(w http.ResponseWriter, status int, code, message string) {
	writeAPIError(w, status, code, message)
}

// dispatches /api/shops by method, since GET and POST share the same url but need very different handling
// (list is public, create requires a logged-in shop owner)
func (s *Shops) Route(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.List(w, r)
	case http.MethodPost:
		// only shop owners with a valid credentials may create a shop; RequireAuth checks the jwt before we touch the db
		auth.RequireAuth(s.JWTSecret, s.Queries, s.Create)(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed) // error 405
	}
}

// dispatches /api/shops/{id} by method both methods here mutate one specific existing shop, so both need the authorization
func (s *Shops) RouteByID(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPut:
		auth.RequireAuth(s.JWTSecret, s.Queries, s.Update)(w, r)
	case http.MethodDelete:
		auth.RequireAuth(s.JWTSecret, s.Queries, s.Delete)(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// the shared gate in front of Update and Delete: pull {id} out of the path, then ask
// authorizeShopAccess (authz.go) whether this caller may modify that shop.
// on failure it has already written the response, so callers just return.
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

// public, unauthenticated: used by the map screen to plot every shop as a pin
func (s *Shops) List(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	shops, err := s.Queries.ListShops(ctx)
	if err != nil {
		log.Printf("CRITICAL: failed to list shops: %v", err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to load shops")
		return
	}

	// make(..., 0, len) and not `var response []ShopResponse`: a nil slice encodes as `null`, not
	// `[]`, and the app's `jsonDecode(...) as List` would throw on it. the difference only shows up
	// when there are no shops at all, which is exactly the state a fresh install is in.
	response := make([]ShopResponse, 0, len(shops))
	for _, shop := range shops {
		response = append(response, shopFromList(shop))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// authenticated: backs the "manage my shops" screen - every shop the caller themselves owns, as
// opposed to List above which is every shop, for anyone, for the map. no role check needed here:
// unlike Create and the product mutations this has no side effects, and it's already scoped to the
// caller's own user_id, so there's nothing a customer account could see here that a shop_owner
// couldn't (it would just always come back empty for them).
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
// number, picked map location) and creates the shop.
func (s *Shops) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeShopError(w, http.StatusUnauthorized, "unauthorized", "unauthorized")
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

	// mirrors the varchar widths in db/migrations/000001 and 000003. postgres rejects an over-long
	// value too, but as a constraint violation the handler can only report as a 500 - the owner
	// would see "не удалось" with no hint that the name is simply too long.
	if accessErr := validateShopFieldLengths(name, contactPhone, address); accessErr != nil {
		accessErr.write(w)
		return
	}

	// checked before the insert rather than left to the column's CHECK constraint: postgres would
	// reject it too, but as a 500 with a constraint violation in the log instead of a 400 naming
	// the field. it also has to be a category we hold a template for, since the next step copies
	// that template in.
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
	// seeding only ever happens here, at creation.
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		log.Printf("CRITICAL: failed to begin shop creation transaction for user %d: %v", userID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to create shop")
		return
	}
	defer tx.Rollback(ctx) // no-op once Commit below succeeds

	// the same Queries methods, but routed through the transaction instead of straight at the pool
	// - that is the whole job of db.Queries.WithTx (see db/db.go)
	qtx := s.Queries.WithTx(tx)

	shop, err := qtx.CreateShop(ctx, db.CreateShopParams{
		UserID:       userID,
		Name:         name,
		ContactPhone: contactPhone,
		Address:      address,
		Category:     category,
		// st_makepoint wants (longitude, latitude) in that order - see the comment in shops.sql
		StMakepoint:   req.Longitude,
		StMakepoint_2: req.Latitude,
	})
	if err != nil {
		log.Printf("CRITICAL: failed to create shop for user %d: %v", userID, err)
		writeShopError(w, http.StatusInternalServerError, "server_error", "failed to create shop")
		return
	}

	// a plain loop of single-row inserts rather than one bulk COPY: it is at most 100 statements (the
	// универсальный template), runs once in a shop's lifetime, and reuses the query sqlc already
	// generated. worth revisiting only if templates ever grow into the thousands.
	template := catalog.Template(category)
	for _, item := range template {
		if err := qtx.SeedTemplateProduct(ctx, db.SeedTemplateProductParams{
			ShopID: shop.ID,
			Name:   item.Name,
			// ProductCategory is a named string type, so the conversion is explicit. it is typed in
			// the template list precisely so a typo there fails to compile instead of quietly
			// filing a product under a category the app has no label for.
			Category:    string(item.Category),
			Unit:        item.Unit,
			TemplateKey: pgtype.Text{String: item.Key, Valid: true},
			// null rather than "" for a template with no photo set, so the column means the same
			// thing as products.price does: absent, not empty
			ImagePath: pgtype.Text{String: item.ImagePath, Valid: item.ImagePath != ""},
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
	// the template size is passed in because the app appends this shop straight into its in-memory
	// list instead of re-fetching - without it the brand-new shop would show "нет товаров" despite
	// having just been seeded with fifty
	json.NewEncoder(w).Encode(shopFromCreate(shop, int64(len(template))))
}

// PUT /api/shops/{id} - the "edit shop" form. the form always submits all four editable fields, so
// this is a full replacement, not a per-field patch; whatever is missing from the body would be
// written as empty and is therefore rejected by the same required-field check Create uses.
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

	// the same check Create does. it matters more here, if anything: the edit form is where an owner
	// drags the map pin, and a location that failed to resolve would silently move the shop to
	// (0, 0) - off the map, with the row still reporting success.
	if accessErr := validateCoordinates(req.Latitude, req.Longitude); accessErr != nil {
		accessErr.write(w)
		return
	}

	// a fresh timeout, not the one authorizeShopAccess used: that one's cancel() already fired when
	// the helper returned, so reusing its context here would hit an already-cancelled deadline
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	shop, err := s.Queries.UpdateShop(ctx, db.UpdateShopParams{
		ID:           shopID,
		Name:         name,
		ContactPhone: contactPhone,
		Address:      address,
		// st_makepoint wants (longitude, latitude) in that order - see the comment in shops.sql
		StMakepoint:   req.Longitude,
		StMakepoint_2: req.Latitude,
	})
	if err != nil {
		// the row existed a moment ago (authorizeShopAccess read its owner), so no-rows here means it
		// was deleted in between - a real race, not a client mistake
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

// the varchar widths from db/migrations/000001 (name) and 000003 (contact_phone). address is TEXT
// and so has no database limit at all, which is its own problem - an unbounded column is a place to
// store a megabyte - so it gets an application limit instead, generous enough for any real address
// a geocoder would return.
//
// rune counts, not len(): these are cyrillic strings where one character is two bytes, and postgres
// counts varchar limits in characters. this mirrors the same check product_crud.go does on a
// product's name and unit.
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

// DELETE /api/shops/{id}. the shop's products go with it through products.shop_id ON DELETE CASCADE,
// so this is one statement and not a transaction.
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
		// same race as Update above: it was there when we checked its owner and is gone now. the
		// caller's goal ("this shop should not exist") is satisfied either way, but saying so is
		// more honest than reporting a deletion we didn't perform.
		writeShopError(w, http.StatusNotFound, "shop_not_found", "shop not found")
		return
	}

	log.Printf("Shop %d deleted", shopID)
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}
