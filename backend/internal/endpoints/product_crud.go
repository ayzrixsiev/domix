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

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
	"domix/backend/internal/ratelimit"
)

// the whole products api:
//
//	GET    /api/shops/{id}/products  - public, the catalogue grid on a shop's card
//	POST   /api/shops/{id}/products  - owner adds one of their own products
//	PUT    /api/products/{id}        - owner edits one (price/stock always; the name on a обои slot)
//	DELETE /api/products/{id}        - owner removes one of their own products
//
// most rows are not created here: picking a category at shop creation seeds the catalogue from
// internal/catalog, and these endpoints are how the owner then fills in prices.
type Products struct {
	Queries   *db.Queries
	JWTSecret string

	// where uploaded photos are written: local disk or a Cloudflare R2 bucket, picked in main.go
	Images imagestore.Storage

	// how a stored path becomes a fetchable address. zero value = this api's own /images/
	URLs imagestore.URLs

	// the per-account ceiling the per-IP limiter cannot express. nil in tests.
	Uploads *ratelimit.Limiter
}

// how many products an owner may add on top of the category template - the cap that stops a shop
// drifting into a catalogue nobody else's lines up with. counts only `template_key IS NULL` rows,
// since seeded ones are identical in every shop. sent to the app in the product_limit_reached error.
const maxCustomProducts = 30

// the varchar widths in db/migrations. a value wider than its column makes postgres reject the
// statement, which reaches the owner as an unexplained "failed to save".
const (
	maxNameLen = 150
	maxUnitLen = 20

	// no construction product costs this much; the ceiling doubles as overflow protection
	maxProductPrice = 1e15
)

// one product on the wire, independent of sqlc's near-identical row types so their pgtype wrappers
// never leak into json
type ProductResponse struct {
	ID       int64  `json:"id"`
	ShopID   int64  `json:"shop_id"`
	Name     string `json:"name"`
	Category string `json:"category"`
	Unit     string `json:"unit"`

	// a pointer, so an unpriced product is `null` and not `0` - "not priced yet" and "free" are
	// different facts, and the whole seeded-catalogue flow turns on the app telling them apart
	Price *int64 `json:"price"`

	Availability string `json:"availability"`

	// seeded from the category template: the "ваш товар" badge, and undeletable
	IsTemplate bool `json:"is_template"`

	// whether the owner may write the name. separate from IsTemplate because a обои slot is a
	// template row (locked category and unit) whose name is nonetheless the owner's to write.
	NameEditable bool `json:"name_editable"`

	// the full-size copy, what the edit screen loads; null for a product with no photo
	ImageURL *string `json:"image_url"`

	// the 400px copy a grid loads, null exactly when ImageURL is. **sent ready-made rather than
	// derived**: an apk that appended "_thumb" itself would freeze the convention in every build
	// already on a phone, so changing it would mean a Play release rather than a deploy.
	ImageThumbURL *string `json:"image_thumb_url"`

	// whether that photo is this shop's own upload rather than the shared catalogue shot. without
	// it "удалить фото" is a button that does nothing on most of a fresh shop's catalogue.
	OwnImage bool `json:"own_image"`

	// whether the owner may put their own photograph on this row at all - see templateFlags
	PhotoEditable bool `json:"photo_editable"`
}

// the three photo fields, derived together so a response cannot carry a url with the wrong answer
// beside it. **the database stores only the relative path**, never a full url: the host differs
// between a laptop, the tunnel and img.domix-api.uz, and a dump would carry the wrong one.
func productImage(urls imagestore.URLs, path pgtype.Text) (url, thumb *string, own bool) {
	if !path.Valid || path.String == "" {
		return nil, nil, false
	}
	full, small := urls.Master(path.String), urls.Thumb(path.String)
	return &full, &small, imagestore.IsUpload(path.String)
}

// the three flags, in one function so the five response sites and the Update branch cannot disagree
// about what a slot is. an invalid key is the owner's own row: (false, true, true).
//
// **photoEditable asks the catalogue, not the shop's category**: the rule is "an owner may
// photograph what we have not photographed". Everywhere else the picture is one file shared by every
// shop of the category, and replacing it would make two rows the index calls identical look different.
func templateFlags(key pgtype.Text) (isTemplate, nameEditable, photoEditable bool) {
	if !key.Valid {
		return false, true, true
	}
	return true, catalog.IsOwnerNamedSlot(key.String), catalog.TemplateImage(key.String) == ""
}

// what the database CHECK constraint accepts. the app sends a picker's value, already normalized.
var validAvailability = map[string]bool{
	"in_stock":    true,
	"on_order":    true,
	"unavailable": true,
}

// GET and POST on /api/shops/{id}/products. listing is public, adding is owner-only.
func (p *Products) RouteByShop(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		p.ListByShop(w, r)
	case http.MethodPost:
		auth.RequireAuth(p.JWTSecret, p.Queries, p.Create)(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// PUT and DELETE on /api/products/{id}: both mutate one product, both need the ownership check
func (p *Products) RouteByID(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPut:
		auth.RequireAuth(p.JWTSecret, p.Queries, p.Update)(w, r)
	case http.MethodDelete:
		auth.RequireAuth(p.JWTSecret, p.Queries, p.Delete)(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// public: every product in one shop. no pagination - a shop's catalogue is bounded by the template
// plus maxCustomProducts, so the whole thing is one small response by construction.
func (p *Products) ListByShop(w http.ResponseWriter, r *http.Request) {
	shopID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_shop_id", "invalid shop id")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	products, err := p.Queries.ListProductsByShop(ctx, shopID)
	if err != nil {
		if callerGone(r) {
			return
		}
		log.Printf("CRITICAL: failed to list products for shop %d: %v", shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to load products")
		return
	}

	response := make([]ProductResponse, 0, len(products))
	for _, product := range products {
		isTemplate, nameEditable, photoEditable := templateFlags(product.TemplateKey)
		imageURL, thumbURL, ownImage := productImage(p.URLs, product.ImagePath)
		response = append(response, ProductResponse{
			ID:            product.ID,
			ShopID:        product.ShopID,
			Name:          product.Name,
			Category:      product.Category,
			Unit:          product.Unit,
			Price:         nullableInt64(product.Price),
			Availability:  product.Availability,
			IsTemplate:    isTemplate,
			NameEditable:  nameEditable,
			ImageURL:      imageURL,
			ImageThumbURL: thumbURL,
			OwnImage:      ownImage,
			PhotoEditable: photoEditable,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// authenticated: the owner adds a product of their own, capped at maxCustomProducts
func (p *Products) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "unauthorized")
		return
	}

	shopID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_shop_id", "invalid shop id")
		return
	}

	var req productRequest
	if !decodeJSONBody(w, r, &req) {
		return
	}

	fields, accessErr := req.validate()
	if accessErr != nil {
		accessErr.write(w)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	if accessErr := authorizeShopAccess(ctx, p.Queries, userID, shopID); accessErr != nil {
		accessErr.write(w)
		return
	}

	// not a CHECK constraint, because "at most N rows matching a predicate" is not one. racy in
	// principle; the worst outcome is one product over the cap.
	customCount, err := p.Queries.CountCustomProducts(ctx, shopID)
	if err != nil {
		log.Printf("CRITICAL: failed to count custom products for shop %d: %v", shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to save product")
		return
	}
	if customCount >= maxCustomProducts {
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(map[string]any{
			"error": "custom product limit reached",
			"code":  "product_limit_reached",
			"limit": maxCustomProducts,
		})
		return
	}

	product, err := p.Queries.CreateCustomProduct(ctx, db.CreateCustomProductParams{
		ShopID:       shopID,
		Name:         fields.name,
		Price:        fields.price,
		Category:     fields.category,
		Unit:         fields.unit,
		Availability: fields.availability,
	})
	if err != nil {
		log.Printf("CRITICAL: failed to create product in shop %d: %v", shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to save product")
		return
	}

	isTemplate, nameEditable, photoEditable := templateFlags(product.TemplateKey)
	imageURL, thumbURL, ownImage := productImage(p.URLs, product.ImagePath)

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(ProductResponse{
		ID:            product.ID,
		ShopID:        product.ShopID,
		Name:          product.Name,
		Category:      product.Category,
		Unit:          product.Unit,
		Price:         nullableInt64(product.Price),
		Availability:  product.Availability,
		IsTemplate:    isTemplate,
		NameEditable:  nameEditable,
		ImageURL:      imageURL,
		ImageThumbURL: thumbURL,
		OwnImage:      ownImage,
		PhotoEditable: photoEditable,
	})
}

// authenticated: edit one product. the endpoint that fills in a seeded catalogue's missing prices,
// so by far the most-used of the four. how much may change depends on where the row came from, and
// the rule is enforced here rather than trusted to the app:
//
//   - a template row: price and availability only. name, category and unit are what make it the
//     *same* product as the one down the road, which is what the shared basket rests on.
//   - a slot: the name too. a обои slot names a *kind* of product, so writing in what the shop
//     actually sells is the point of the row. category and unit stay locked.
//   - the owner's own row: everything, since nothing outside this shop refers to it.
func (p *Products) Update(w http.ResponseWriter, r *http.Request) {
	existing, ok := p.authorizeProductAccess(w, r)
	if !ok {
		return
	}

	var req productRequest
	if !decodeJSONBody(w, r, &req) {
		return
	}

	// a fresh timeout: authorizeProductAccess's cancel() already fired when it returned
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	var (
		product db.UpdateProductRow
		err     error
	)

	isTemplate, nameEditable, photoEditable := templateFlags(existing.TemplateKey)

	switch {
	case isTemplate && nameEditable:
		// a slot: the name is validated as a custom product's is, category and unit are left out of
		// the statement entirely
		fields, accessErr := req.validateSlot()
		if accessErr != nil {
			accessErr.write(w)
			return
		}
		var slot db.UpdateProductSlotRow
		slot, err = p.Queries.UpdateProductSlot(ctx, db.UpdateProductSlotParams{
			ID:           existing.ID,
			Name:         fields.name,
			Price:        fields.price,
			Availability: fields.availability,
		})
		product = db.UpdateProductRow(slot)

	case isTemplate:
		// name/category/unit are ignored rather than rejected: the form submits them back read-only,
		// and UpdateProductPricing has no column for them, which is what makes ignoring them safe
		fields, accessErr := req.validatePricing()
		if accessErr != nil {
			accessErr.write(w)
			return
		}
		var priced db.UpdateProductPricingRow
		priced, err = p.Queries.UpdateProductPricing(ctx, db.UpdateProductPricingParams{
			ID:           existing.ID,
			Price:        fields.price,
			Availability: fields.availability,
		})
		// identical fields, distinct named types - sqlc emits one struct per query
		product = db.UpdateProductRow(priced)

	default:
		fields, accessErr := req.validate()
		if accessErr != nil {
			accessErr.write(w)
			return
		}
		product, err = p.Queries.UpdateProduct(ctx, db.UpdateProductParams{
			ID:           existing.ID,
			Name:         fields.name,
			Price:        fields.price,
			Category:     fields.category,
			Unit:         fields.unit,
			Availability: fields.availability,
		})
	}

	if err != nil {
		// it existed when we read it to authorize, so no-rows is a real race and not a client mistake
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "product_not_found", "product not found")
			return
		}
		log.Printf("CRITICAL: failed to update product %d: %v", existing.ID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to save product")
		return
	}

	imageURL, thumbURL, ownImage := productImage(p.URLs, product.ImagePath)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(ProductResponse{
		ID:            product.ID,
		ShopID:        product.ShopID,
		Name:          product.Name,
		Category:      product.Category,
		Unit:          product.Unit,
		Price:         nullableInt64(product.Price),
		Availability:  product.Availability,
		IsTemplate:    isTemplate,
		NameEditable:  nameEditable,
		ImageURL:      imageURL,
		ImageThumbURL: thumbURL,
		OwnImage:      ownImage,
		PhotoEditable: photoEditable,
	})
}

// authenticated: remove one of the owner's own products. template rows are refused, slots included
// (hence the branch on TemplateKey rather than templateFlags): they are the shared basket, and a
// shop that deleted half of them would look cheap by simply not stocking the expensive items.
func (p *Products) Delete(w http.ResponseWriter, r *http.Request) {
	existing, ok := p.authorizeProductAccess(w, r)
	if !ok {
		return
	}

	if existing.TemplateKey.Valid {
		writeAPIError(w, http.StatusForbidden, "template_product", "template products cannot be deleted")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := p.Queries.DeleteProduct(ctx, existing.ID)
	if err != nil {
		log.Printf("CRITICAL: failed to delete product %d: %v", existing.ID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to delete product")
		return
	}
	if rows == 0 {
		// same race as Update: it was there when we read it and is gone now
		writeAPIError(w, http.StatusNotFound, "product_not_found", "product not found")
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}

// the shared gate in front of Update and Delete. it authorizes against the shop_id stored on the
// row, never one the client sent, so a caller cannot pair their own shop with somebody else's
// product id. on failure it has already written the response, so callers just return.
func (p *Products) authorizeProductAccess(w http.ResponseWriter, r *http.Request) (db.GetProductRow, bool) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "unauthorized")
		return db.GetProductRow{}, false
	}

	productID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_product_id", "invalid product id")
		return db.GetProductRow{}, false
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	product, err := p.Queries.GetProduct(ctx, productID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "product_not_found", "product not found")
			return db.GetProductRow{}, false
		}
		log.Printf("CRITICAL: failed to look up product %d: %v", productID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to load product")
		return db.GetProductRow{}, false
	}

	if accessErr := authorizeShopAccess(ctx, p.Queries, userID, product.ShopID); accessErr != nil {
		accessErr.write(w)
		return db.GetProductRow{}, false
	}

	return product, true
}

// the body of both Create and Update - the form always submits every field, so a product is fully
// replaced rather than patched. Price is a pointer so `null` stays "not priced" and not zero.
type productRequest struct {
	Name         string `json:"name"`
	Category     string `json:"category"`
	Unit         string `json:"unit"`
	Price        *int64 `json:"price"`
	Availability string `json:"availability"`
}

// validated, trimmed and converted to the types the generated params want
type productFields struct {
	name, category, unit, availability string
	price                              pgtype.Int8
}

// the full check, for a row the owner owns outright. the three nest - pricing, then the name, then
// everything - so a field cannot be validated one way on one path and another on the next.
func (req productRequest) validate() (productFields, *accessError) {
	f, accessErr := req.validateSlot()
	if accessErr != nil {
		return f, accessErr
	}

	f.category = strings.TrimSpace(req.Category)
	f.unit = strings.TrimSpace(req.Unit)

	if f.category == "" || f.unit == "" {
		return f, &accessError{http.StatusBadRequest, "missing_fields", "name, category and unit are required"}
	}

	// runes, not bytes: cyrillic is two bytes a character and postgres counts varchar in characters
	if utf8.RuneCountInString(f.unit) > maxUnitLen {
		return f, &accessError{http.StatusBadRequest, "field_too_long", "a field is longer than allowed"}
	}

	// the only thing between this column and free text - there is no CHECK constraint behind it
	if !catalog.IsValidProductCategory(f.category) {
		return f, &accessError{http.StatusBadRequest, "invalid_category", "unknown product category"}
	}

	return f, nil
}

// a slot: the two pricing fields plus the owner's name, and nothing else. category and unit are
// deliberately not validated - the form submits them back read-only and UpdateProductSlot has no
// column for either, so checking them would only turn a truthful client into a 400.
func (req productRequest) validateSlot() (productFields, *accessError) {
	f, accessErr := req.validatePricing()
	if accessErr != nil {
		return f, accessErr
	}

	f.name = strings.TrimSpace(req.Name)
	if f.name == "" {
		return f, &accessError{http.StatusBadRequest, "missing_fields", "name is required"}
	}
	if utf8.RuneCountInString(f.name) > maxNameLen {
		return f, &accessError{http.StatusBadRequest, "field_too_long", "a field is longer than allowed"}
	}

	return f, nil
}

// the two fields a template product may change, and the shared prefix of the checks above
func (req productRequest) validatePricing() (productFields, *accessError) {
	f := productFields{availability: strings.TrimSpace(req.Availability)}

	if !validAvailability[f.availability] {
		return f, &accessError{http.StatusBadRequest, "invalid_availability", "invalid availability value"}
	}

	// a missing price is legal and means "not priced yet" - the state every template row starts in.
	// a negative one is not, and neither is one large enough to be a typo.
	if req.Price != nil {
		if *req.Price < 0 || float64(*req.Price) > maxProductPrice {
			return f, &accessError{http.StatusBadRequest, "invalid_price", "invalid price"}
		}
		f.price = pgtype.Int8{Int64: *req.Price, Valid: true}
	}

	return f, nil
}

// pgtype.Int8 -> *int64, the one place a nullable bigint becomes json's null
func nullableInt64(v pgtype.Int8) *int64 {
	if !v.Valid {
		return nil
	}
	// a local, not &v.Int64 - taking the field's address would alias the caller's struct
	price := v.Int64
	return &price
}
