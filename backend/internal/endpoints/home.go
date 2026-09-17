package endpoints

import (
	"encoding/json"
	"log"
	"net/http"
	"regexp"
	"strings"
	"unicode/utf8"

	"domix/backend/db"
	"domix/backend/internal/catalog"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
)

// everything behind the home screen's three sections - VIP Магазины, Популярные категории and
// Лучшие предложения - plus the drill-down a category tile opens.
//
// all of it is public. the home screen is the first thing the app draws, before anyone has logged
// in, so none of this can sit behind RequireAuth. that is also why this struct holds only Queries
// and no JWTSecret, unlike Shops and Products: there is nothing here to authorize.
type Home struct {
	Queries *db.Queries

	// how a stored image path becomes an address the app can fetch. the zero value serves from this
	// api's own /static/products/; IMAGE_BASE_URL points it at img.domix-api.uz in production.
	URLs imagestore.URLs

	// how many searches may run at once - a send takes a slot, a receive frees it. nil = no cap (tests).
	// this is what protects the database: a per-caller limit cannot bound the total, since hundreds of
	// phones share one address on a mobile network and a distributed caller has as many as it likes.
	SearchSlots chan struct{}
}

const (
	// **five, because five is the entire inventory.** VIP placement is a product with a fixed number
	// of units, and the app draws all five whether or not they are sold - an empty slot is what tells
	// a shop owner scrolling past that a place is still available. so this is not a display cap that
	// can be raised without thinking: it is how many of a thing exist, and the app's own
	// VipShopsCarousel.slotCount is the other half of that number.
	//
	// the app never *drops* a shop it was sent, so a server that grew this to six would grow the
	// carousel rather than hide a placement somebody paid for - but the two are meant to agree.
	vipShopsLimit = 5

	// per *shop category*, not overall - "Лучшие предложения" is a tab strip, and each tab is its own
	// ranking. so the worst case is four categories x fifteen shops in one response, which is bounded
	// forever by the LIMIT rather than growing with the market.
	//
	// fifteen and not ten because the app pads each tab out to a fixed number of slots: the empty
	// rows say how many places in this category's ranking are still open, which is the one message
	// that reaches an owner who has not finished pricing. BestOffersList.slotCount mirrors it.
	bestOffersLimit = 15

	// the category drill-down. longer than the home sections because it is a full screen someone
	// scrolls, not a strip they glance at - but still capped, since "every плитка on the market" is
	// unbounded and nobody scrolls past a hundred tiles.
	categoryProductsLimit = 100

	// search results. the same cap as the category drill-down, because it is the same screen and the
	// same grid - a search that returned more than a browse would just be a longer list nobody reads
	// to the end of.
	searchResultsLimit = 100

	// three characters, in at least one word: the shortest piece the search index can look up, since it
	// stores three-letter runs (migration 000002). the app enforces the same rule before sending.
	minSearchWordLen = 3

	// long enough for any name in the catalogue. an unbounded string here is an anonymous caller
	// deciding how much work the database does.
	maxSearchQueryLen = 60
)

// the payload behind GET /api/home.
//
// one endpoint for three sections rather than three endpoints, because the home screen always
// renders all three at once and never one alone. that makes it one round trip instead of three, one
// spinner instead of three, and one error state instead of three-that-can-disagree - the screen
// either has content or it doesn't. the cost is a less reusable endpoint, which is the right trade
// for a screen-shaped read; anything that genuinely needs shops on their own still has
// GET /api/shops.
type HomeResponse struct {
	VipShops []ShopResponse `json:"vip_shops"`

	// "Лучшие предложения", grouped into one entry per shop category - the tabs on that section.
	//
	// grouped rather than flat because a Basket Price Index only compares shops of the same
	// category: a Сантехника shop's basket is a different list of goods from a Универсальный
	// shop's, so "6% cheaper than market" means a different market on each row. A single mixed
	// ranking would still be *ordered* correctly (that is what normalising the index buys) but the
	// badges next to each other would invite a comparison that isn't there.
	//
	// all four groups arrive in one response rather than one request per tab, because switching a
	// tab must be instant - a spinner between two tabs of the same section reads as the app
	// reloading, not as it filtering.
	BestOffers []CategoryOffersResponse `json:"best_offers"`
}

// one tab of "Лучшие предложения": a shop category and its cheapest shops.
//
// only categories that actually have ranked shops are sent. the app draws one tab per entry, so an
// empty category would be a tab that leads nowhere - and with one shop category populated (which is
// where this launches) the app can then skip the tab strip entirely rather than drawing a strip
// with three dead options.
type CategoryOffersResponse struct {
	Category string         `json:"category"`
	Shops    []ShopResponse `json:"shops"`
}

// the "Популярные категории" grid is **not** in this payload, and that is deliberate. the twelve
// tiles are a fixed list the app already holds (features/products/data/product_category.dart), so
// there is nothing to fetch: labels and glyphs are presentation, and the counts that used to ride
// along here were dropped with the badges that displayed them. tapping a tile fetches its products
// on its own, which is the only part that needs the database.

// GET /api/home
func (h *Home) Get(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// five queries (one VIP, four best-offer tabs), run one after another rather than concurrently.
	// it is tempting to fan them out into goroutines and wait on the slowest, and at some scale that
	// is right - but each is a single indexed read, and running them in parallel would take five
	// connections out of a pool of ten to serve one request. under any real concurrency that starves
	// the pool far faster than the serial version is slow. worth revisiting when there is a
	// measurement saying so, not before.
	vip, err := h.Queries.ListVipShops(ctx, vipShopsLimit)
	if err != nil {
		if callerGone(r) {
			return
		}
		log.Printf("CRITICAL: failed to list vip shops: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to load home content")
		return
	}

	// one call per shop category rather than one window-function query for all four - see the note
	// on ListBestOffersInCategory in db/queries/shops.sql for why sqlc could not compile the
	// window version. four extra round trips on one endpoint, each a single indexed read.
	offers := make([]CategoryOffersResponse, 0, len(catalog.AllShopCategories))
	for _, category := range catalog.AllShopCategories {
		rows, err := h.Queries.ListBestOffersInCategory(ctx, db.ListBestOffersInCategoryParams{
			Category: string(category),
			Limit:    bestOffersLimit,
		})
		if err != nil {
			if callerGone(r) {
				return
			}
			log.Printf("CRITICAL: failed to list best offers for %q: %v", category, err)
			writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to load home content")
			return
		}
		// a category nobody has priced enough shops in produces no tab at all
		if len(rows) == 0 {
			continue
		}

		group := CategoryOffersResponse{
			Category: string(category),
			Shops:    make([]ShopResponse, 0, len(rows)),
		}
		for _, shop := range rows {
			group.Shops = append(group.Shops, shopFromRanked(shop))
		}
		offers = append(offers, group)
	}

	response := HomeResponse{
		// make(..., 0, len): a nil slice encodes as `null`, and that is exactly what this endpoint
		// returns with no shops in the database. the app decodes it as a list, so `null` would be a
		// crash on the one path that is currently guaranteed. `offers` is already a made slice.
		VipShops:   make([]ShopResponse, 0, len(vip)),
		BestOffers: offers,
	}

	for _, shop := range vip {
		// its own mapper, not the ranked one: ListVipShops left-joins the basket index, so a
		// placement that has been paid for appears the moment it is granted and simply carries no
		// price yet. see shopFromVip in shop_dto.go.
		response.VipShops = append(response.VipShops, shopFromVip(shop))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// GET /api/categories/{code}/products - the drill-down behind a "Популярные категории" tile.
//
// Products, not shops. The question someone taps "Сантехника" to ask is "what plumbing can I buy
// and for how much", and a list of shop names answers a different one - they would then have to
// open each shop and search it. The shop's name rides on every row instead, so the list answers
// both at once.
func (h *Home) ProductsByCategory(w http.ResponseWriter, r *http.Request) {
	code := r.PathValue("code")

	// validated against the same twelve codes the write path uses. without this, any string in the
	// url would come back as an empty list, which reads to the app as "nothing in this category"
	// rather than "that is not a category" - and would quietly hide a typo in a link forever.
	if !catalog.IsValidProductCategory(code) {
		writeAPIError(w, http.StatusNotFound, "unknown_category", "unknown product category")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := h.Queries.ListProductsByCategory(ctx, db.ListProductsByCategoryParams{
		Category: code,
		Limit:    categoryProductsLimit,
	})
	if err != nil {
		if callerGone(r) {
			return
		}
		log.Printf("CRITICAL: failed to list products for category %q: %v", code, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to load products")
		return
	}

	response := make([]CategoryProductResponse, 0, len(rows))
	for _, row := range rows {
		response = append(response, categoryProductFromRow(h.URLs, row))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// GET /api/products/search?q=... - the home screen's search field.
//
// Products across every shop, not shops, for the same reason the category drill-down is products:
// someone typing "цемент" is asking what it costs and who has it, and a list of shop names makes
// them open each one and look. It answers with the exact shape ProductsByCategory does, so the app
// renders the results with the grid it already has.
//
// Public, like the rest of this file - searching is the first thing a stranger does, before there is
// any account to attach the query to.
//
// **Every word counts, in any order**: "пвс кабель" finds "Кабель медный ПВС 2х1,5". Names and query
// are both compared lowercased, with ё written as е - see searchPatterns.
func (h *Home) SearchProducts(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))

	// RuneCountInString, not len(): len counts *bytes*, and every letter in "цемент" is two of them
	// in UTF-8, so a byte-length ceiling would cut a Russian query off at half the words an English
	// one gets. searchPatterns counts its floor the same way.
	if utf8.RuneCountInString(query) > maxSearchQueryLen {
		writeAPIError(w, http.StatusBadRequest, "query_too_long", "search query is too long")
		return
	}
	anchor, patterns, ok := searchPatterns(query)
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "query_too_short", "search query is too short")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// a slot before a connection (see Home.SearchSlots). the wait is the query's own deadline, so a
	// burst queues rather than being refused, and one that never gets a slot is told to come back.
	if h.SearchSlots != nil {
		select {
		case h.SearchSlots <- struct{}{}:
		case <-ctx.Done():
			if callerGone(r) {
				return
			}
			w.Header().Set("Retry-After", "2")
			writeAPIError(w, http.StatusServiceUnavailable, "search_busy", "search is busy, try again shortly")
			return
		}
	}

	rows, err := h.Queries.SearchProducts(ctx, db.SearchProductsParams{
		Anchor:      anchor,
		Patterns:    patterns,
		ResultLimit: searchResultsLimit,
	})
	// given back as soon as the rows are in, not held while a slow phone downloads them
	if h.SearchSlots != nil {
		<-h.SearchSlots
	}
	if err != nil {
		if callerGone(r) {
			return
		}
		log.Printf("CRITICAL: product search failed: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "search failed")
		return
	}

	response := make([]CategoryProductResponse, 0, len(rows))
	for _, row := range rows {
		// the two row structs are field-for-field identical - both queries select the same columns in
		// the same order - so one converts to the other and both endpoints share a mapper. the
		// conversion is checked by the compiler, so a column added to one query and not the other
		// stops the build instead of silently changing what search returns.
		response = append(response, categoryProductFromRow(h.URLs, db.ListProductsByCategoryRow(row)))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// turns one product row into the wire shape, for the two endpoints that return products across
// shops. it exists so a change to what a product looks like on the wire happens once.
func categoryProductFromRow(urls imagestore.URLs, row db.ListProductsByCategoryRow) CategoryProductResponse {
	isTemplate, nameEditable, photoEditable := templateFlags(row.TemplateKey)
	imageURL, thumbURL, ownImage := productImage(urls, row.ImagePath)
	return CategoryProductResponse{
		ProductResponse: ProductResponse{
			ID:            row.ID,
			ShopID:        row.ShopID,
			Name:          row.Name,
			Category:      row.Category,
			Unit:          row.Unit,
			Price:         nullableInt64(row.Price),
			Availability:  row.Availability,
			IsTemplate:    isTemplate,
			NameEditable:  nameEditable,
			ImageURL:      imageURL,
			ImageThumbURL: thumbURL,
			OwnImage:      ownImage,
			PhotoEditable: photoEditable,
		},
		ShopName: row.ShopName,
	}
}

// turns what a customer typed into the two arguments SearchProducts takes: one pattern per word (all
// required, in any order), plus the longest word again as the anchor - the only one the trigram index
// can look up, since it cannot serve `~ ALL`. Lowercased with ё as е, exactly as migration 000002
// indexes the names. `ok` is false when no word reaches minSearchWordLen.
func searchPatterns(query string) (anchor string, patterns []string, ok bool) {
	longest := 0
	for _, word := range strings.Fields(strings.ReplaceAll(strings.ToLower(query), "ё", "е")) {
		pattern := wordPattern(word)
		patterns = append(patterns, pattern)
		if n := utf8.RuneCountInString(word); n > longest {
			longest, anchor = n, pattern
		}
	}
	return anchor, patterns, longest >= minSearchWordLen
}

// one word as a regex: the word itself, plus its Cyrillic spelling when it was typed in Latin
// ("kabel" -> "кабел"). Both, because catalogue names carry Latin brands too - VERO, TYTAN, LED.
// QuoteMeta is what keeps a typed "." or "*" a character rather than a pattern.
func wordPattern(word string) string {
	pattern := regexp.QuoteMeta(word)
	if cyrillic := catalog.Cyrillic(word); cyrillic != "" && cyrillic != word {
		pattern = "(" + pattern + "|" + regexp.QuoteMeta(cyrillic) + ")"
	}
	return pattern
}

// a product plus the name of the shop selling it.
//
// Embedding ProductResponse rather than redeclaring its fields keeps one definition of what a
// product looks like on the wire - Go flattens an embedded struct into the parent object when
// encoding, so this serializes as a product object with one extra key, and the app decodes it with
// the same Product.fromJson it already has.
type CategoryProductResponse struct {
	ProductResponse
	ShopName string `json:"shop_name"`
}
