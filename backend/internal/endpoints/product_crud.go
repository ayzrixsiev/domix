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
//	PUT    /api/products/{id}        - owner edits one product (price/stock always; the name also on
//	                                   a обои slot; everything only on their own products)
//	DELETE /api/products/{id}        - owner removes one of their own products
//
// most rows in a shop are not created here at all: picking a category when the shop is created
// seeds its catalogue from internal/catalog (see Shops.Create), and these endpoints are how the
// owner then fills in prices and adds the handful of products unique to their shop.
//
// there used to be a fifth endpoint here, POST /api/products/upload, which bulk-loaded a shop's
// catalogue from an .xlsx. it is gone: the spreadsheet existed so an owner wouldn't have to type a
// catalogue from nothing, and a shop no longer starts from nothing.
type Products struct {
	Queries   *db.Queries
	JWTSecret string

	// where an owner's uploaded product photos are written. an interface with two implementations
	// (a local directory, a Cloudflare R2 bucket) chosen once in main.go by whether the R2 keys are
	// in the environment - see internal/imagestore for why that abstraction earns its place and for
	// why the catalogue's own shots and these share one namespace without being able to delete each
	// other.
	Images imagestore.Storage

	// how a stored path becomes an address the app can fetch. the zero value serves from this api's
	// own /static/products/, which is the laptop and every test; IMAGE_BASE_URL points it at
	// img.domix-api.uz in production.
	URLs imagestore.URLs

	// the per-account ceiling on uploads, which the per-IP limiter in front of every route cannot
	// express. nil in the tests, which call the handlers directly.
	Uploads *ratelimit.Limiter
}

// how many products an owner may add on top of the category template. the template is what makes
// two shops comparable - same products, different prices - so this cap is what stops a shop from
// turning into an arbitrary catalogue that no longer lines up with anyone else's.
//
// it counts *only* the owner's own rows (CountCustomProducts, `template_key IS NULL`). the seeded
// rows are not part of the allowance - they are the same in every shop of the category, so charging
// an owner for them would leave a brand-new universal shop 100 products past its whole budget
// before the owner had touched anything.
//
// the same number for every shop category, deliberately: the allowance is "how far off the shared
// basket may a shop drift", which is the same question whether the template under it is 100 rows or
// 10. it is sent to the app in the `limit` field of the product_limit_reached error, so raising it
// is a backend deploy - the dart copy only greys a tile out early.
const maxCustomProducts = 30

// these mirror the varchar widths in db/migrations (000001 + 000004). a value wider than its column
// makes postgres reject the statement, which would surface to the owner as an unexplained "failed
// to save" rather than as "this name is too long".
const (
	maxNameLen = 150
	maxUnitLen = 20

	// no construction product costs this much; the ceiling doubles as overflow protection
	maxProductPrice = 1e15
)

// what we send back to flutter for one product. a clean shape independent of sqlc's four
// near-identical generated row types, so their pgtype wrappers never leak over the wire.
type ProductResponse struct {
	ID       int64  `json:"id"`
	ShopID   int64  `json:"shop_id"`
	Name     string `json:"name"`
	Category string `json:"category"`
	Unit     string `json:"unit"`

	// a *pointer*, so a product whose price the owner hasn't set yet serializes as `price: null`
	// rather than `price: 0`. those are different facts - "we haven't priced this" versus "this is
	// free" - and the whole seeded-catalogue flow depends on the app being able to tell them apart
	// to show its "укажите цену" prompt.
	Price *int64 `json:"price"`

	Availability string `json:"availability"`

	// true for a row seeded from the category template. the app uses it for the "ваш товар" badge
	// and to keep template rows undeletable; the key itself stays server-side.
	IsTemplate bool `json:"is_template"`

	// whether the owner may write this product's name. two booleans rather than one, because the
	// edit form asks two independent questions and a обои slot answers them differently: it *is* a
	// template row (locked category and unit, no delete button) whose name is nonetheless the
	// owner's to write - that is what a slot is. for every other row the two agree.
	NameEditable bool `json:"name_editable"`

	// the full-size copy: "/static/products/universal/001.jpg" on a laptop, an absolute
	// "https://img.domix-api.uz/universal/001.jpg" once IMAGE_BASE_URL is set. null for a product
	// with no photo, which the app draws as the placeholder banner it drew for every product before
	// this existed.
	//
	// What the *edit screen* loads. A grid loads [ProductResponse.ImageThumbURL].
	ImageURL *string `json:"image_url"`

	// the 400px copy of the same photo, and null exactly when ImageURL is.
	//
	// **Sent ready-made rather than derived in the app, and that is the whole reason it is a second
	// field instead of a documented suffix.** An apk that appended "_thumb" itself would freeze the
	// naming convention inside every build already on a phone, so changing it would mean a release
	// in Play rather than a deploy - and there is no way to fix an old build that guessed wrong.
	// The app's only rule is "prefer this one, fall back to image_url if it is absent", which is
	// what a build talking to a backend from before thumbnails existed does by itself.
	ImageThumbURL *string `json:"image_thumb_url"`

	// whether that photo is this shop's own upload rather than the shared catalogue shot the row was
	// seeded with. the third derived boolean on this struct, and it is here for the same reason the
	// other two are: it answers a question the app has to ask before drawing a control.
	//
	// **"удалить фото" means two different things and only this tells them apart.** On an owner's own
	// upload it removes the photo, and on a seeded row it puts the catalogue's shot back. On a row
	// still showing the catalogue's shot it would do nothing at all - so without this the app draws a
	// delete button that is dead on most of a fresh shop's catalogue.
	OwnImage bool `json:"own_image"`

	// whether the owner may put their own photograph on this row at all. see templateFlags, which
	// derives it - and product_image.go, which is what actually refuses.
	//
	// sent rather than re-derived in the app for the reason `name_editable` is: the rule is about
	// what the *catalogue* holds, which is a fact only the server has, and a Flutter build that
	// worked it out for itself would go stale the day a catalogue is photographed.
	PhotoEditable bool `json:"photo_editable"`
}

// the three photo fields, filled from the one column that carries the fact. together rather than
// one each, so a response can never leave with a url and the wrong answer beside it - the same
// reason templateFlags derives its trio in one place.
//
// **The database stores only the path inside the images namespace** ("universal/001.jpg"), never a
// full url, because the host differs between the ngrok tunnel, a laptop and img.domix-api.uz - a
// stored absolute url would be wrong in two of the three, changing the host would mean rewriting
// every row, and a dump taken from production would point every local tile at production.
func productImage(urls imagestore.URLs, path pgtype.Text) (url, thumb *string, own bool) {
	if !path.Valid || path.String == "" {
		return nil, nil, false
	}
	full, small := urls.Master(path.String), urls.Thumb(path.String)
	return &full, &small, imagestore.IsUpload(path.String)
}

// the three flags above, all derived from the one column that carries the fact. kept in a single
// function so the five response sites and the Update branch can never disagree about what a slot is.
//
// an invalid pgtype.Text is a row the owner added themselves, and it comes out (false, true, true):
// not a template row, the name is theirs, the photograph is theirs.
//
// **photoEditable is asked of the catalogue, not of the shop's category, and that is the whole
// design.** The rule is "an owner may photograph what we have not photographed" - which today means
// обои and nothing else, whose slots name a *kind* of wallpaper and so have nothing to shoot.
// Everywhere else the picture is the catalogue's: one file on disk shared by every shop of that
// category, and an owner replacing it makes their tile disagree with the identical row in the shop
// across the road while the basket index says the two are the same product.
//
// Written as `TemplateImage(key) == ""` rather than as a list of category codes because a hand-kept
// list of "the unphotographed categories" is a second copy of a fact the template already holds -
// the same argument that keeps the обои slot keys derived rather than written down (see
// catalog.IsOwnerNamedSlot). **That has now been collected on**: migration 000005 photographed
// пиломатериалы, and those five rows locked themselves - shooting the catalogue was the whole
// change, with nothing to remember here afterwards.
func templateFlags(key pgtype.Text) (isTemplate, nameEditable, photoEditable bool) {
	if !key.Valid {
		return false, true, true
	}
	return true, catalog.IsOwnerNamedSlot(key.String), catalog.TemplateImage(key.String) == ""
}

// the availability values the database CHECK constraint accepts (db/migrations/000004). the app
// sends a picker's value rather than something the owner typed, so these arrive already normalized.
var validAvailability = map[string]bool{
	"in_stock":    true,
	"on_order":    true,
	"unavailable": true,
}

// GET and POST on /api/shops/{id}/products. listing is public - a customer browsing the map has no
// account - while adding a product is an owner-only mutation, hence the split.
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

// PUT and DELETE on /api/products/{id}. both mutate one existing product, so both need the same
// ownership check and neither has a public variant.
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

// public: every product in one shop, for the grid on the shop's card and for the owner's own
// management screen. no pagination - a shop holds at most 50 template rows plus 20 of its own, so
// the whole catalogue is one small response by construction.
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

// authenticated: the owner adds a product of their own, on top of whatever the category template
// already gave them. capped at maxCustomProducts.
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

	// checked here rather than by a database constraint because "at most 20 rows matching a
	// predicate" isn't something a CHECK can express. it is therefore racy in principle - two
	// requests could both read 19 - but the two requests would have to be the same owner tapping
	// "save" twice in the same instant, and the worst outcome is a 21st product.
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

// authenticated: edit one product. this is the endpoint that fills in the prices a freshly seeded
// catalogue is missing, so it is by far the most-used of the four.
//
// how much of the product may change depends on where it came from, and the split is enforced here
// rather than trusted to the app:
//
//   - a template row: price and availability only. those are the two facts that genuinely differ
//     between two shops stocking the same item, and they are the entire reason the seeded catalogue
//     arrives unpriced. its name, category and unit are what make it the *same* product as the one
//     in the shop down the road - let one owner reword them and the shared basket the map's average
//     check is computed over stops being shared.
//   - a slot: name, price and availability. a обои slot names a *kind* of product ("премиальные
//     российские обои") rather than a product, precisely because no two обои shops stock the same
//     rolls - so writing in the collection the shop actually sells is the point of the row, not an
//     attack on it. category and unit stay locked, which is what keeps the ten slots a basket.
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

	// a fresh timeout, not the one authorizeProductAccess used: that one's cancel() already fired
	// when the helper returned, so reusing its context would hit an already-cancelled deadline
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	var (
		product db.UpdateProductRow
		err     error
	)

	isTemplate, nameEditable, photoEditable := templateFlags(existing.TemplateKey)

	switch {
	case isTemplate && nameEditable:
		// a slot. the name is validated the same way a custom product's is - the owner typed it, so
		// it can be blank or over-long in exactly the same ways - while category and unit are left
		// out of the statement entirely, same as the plain template path below.
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
		// the name/category/unit the app sent are ignored rather than rejected: the edit form shows
		// them read-only and submits them back unchanged, so a 400 here would only punish an honest
		// client for being consistent. UpdateProductPricing has no column for them at all, which is
		// what makes ignoring them safe.
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
		// the two generated row types have identical fields but are distinct named types, so the
		// conversion has to be written out; sqlc emits one struct per query by design
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
		// it existed a moment ago (we just read it to authorize), so no-rows here means it was
		// deleted in between - a real race, not a client mistake
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

// authenticated: remove one of the owner's own products. template rows are refused - they are the
// shared basket every shop of this category is measured on, and a shop that deleted half of them
// would look cheap by simply not stocking the expensive items.
//
// slots are refused on the same rule and by the same line, which is why this branches on
// TemplateKey rather than on templateFlags: an обои shop is ranked on ten slots, so deleting the
// премиум ones would be the same trick with the same payoff.
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
		// same race as Update above: it was there when we read it and is gone now
		writeAPIError(w, http.StatusNotFound, "product_not_found", "product not found")
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}

// the shared gate in front of Update and Delete. it reads the product first and authorizes against
// the shop_id stored on that row - never a shop_id the client sent - so a caller can't pair their
// own shop's id with someone else's product id and have the ownership check pass.
//
// on failure it has already written the response, so callers just return. the product it returns is
// the *current* row, which Delete then uses to refuse template products.
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

// the json body of both Create and Update - the edit form always submits every field, so the two
// endpoints take the same shape and a product is fully replaced rather than patched.
//
// Price is *int64 for the same reason ProductResponse's is: the app sends `null` for a product it
// hasn't priced yet, and a plain int64 would silently turn that into a real price of zero.
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

// the full check, for a product the owner owns outright. the three checks nest - pricing, then
// pricing plus the name, then everything - so a field can never be validated one way on one path
// and another way on the next.
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

	// rune count, not len(): these are cyrillic strings, where one character is two bytes, and
	// postgres counts varchar limits in characters
	if utf8.RuneCountInString(f.unit) > maxUnitLen {
		return f, &accessError{http.StatusBadRequest, "field_too_long", "a field is longer than allowed"}
	}

	// a code from internal/catalog, not free text. the app sends the value of a fixed dropdown, so
	// anything else is a client that has gone wrong rather than an owner mistyping - but this is the
	// only thing standing between the column and free text, since there is no CHECK constraint
	// behind it (see IsValidProductCategory for why).
	if !catalog.IsValidProductCategory(f.category) {
		return f, &accessError{http.StatusBadRequest, "invalid_category", "unknown product category"}
	}

	return f, nil
}

// a slot: the two pricing fields plus the name the owner writes in, and nothing else.
//
// the name check is lifted out of validate() rather than repeated, so a name that would be refused
// on a custom product is refused here too - the column it lands in is the same one, with the same
// 150-character limit. what it deliberately does *not* do is validate category and unit: the app
// draws those as locked text and submits them back unchanged, and UpdateProductSlot has no column
// for either, so validating them would only turn a truthful client into a 400.
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

// the two fields a template product is allowed to change, and the shared prefix of the full check
// above - so price and availability can never end up validated one way on one path and another way
// on the other.
func (req productRequest) validatePricing() (productFields, *accessError) {
	f := productFields{availability: strings.TrimSpace(req.Availability)}

	if !validAvailability[f.availability] {
		return f, &accessError{http.StatusBadRequest, "invalid_availability", "invalid availability value"}
	}

	// a missing price is legal and means "not priced yet" - that is the state every template row
	// starts in, and clearing the field is how an owner puts one back into it. a *negative* price is
	// not legal, and neither is one large enough to be a typo.
	if req.Price != nil {
		if *req.Price < 0 || float64(*req.Price) > maxProductPrice {
			return f, &accessError{http.StatusBadRequest, "invalid_price", "invalid price"}
		}
		f.price = pgtype.Int8{Int64: *req.Price, Valid: true}
	}

	return f, nil
}

// pgtype.Int8 -> *int64. pgx models a nullable bigint as a struct with a Valid flag rather than a
// pointer, so this is the one place that translation happens on the way out to json.
func nullableInt64(v pgtype.Int8) *int64 {
	if !v.Valid {
		return nil
	}
	// the address of the loop-independent local, not of v.Int64 - taking the field's address would
	// alias the caller's struct
	price := v.Int64
	return &price
}
