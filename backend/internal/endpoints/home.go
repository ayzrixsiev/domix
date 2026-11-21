package endpoints

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"domix/backend/db"
	"domix/backend/internal/catalog"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
)

// everything behind the home screen - VIP Магазины, Популярные категории, Лучшие предложения - plus
// the drill-down a category tile opens. all of it public: the home screen is drawn before anyone has
// logged in.
type Home struct {
	Queries *db.Queries

	// read only to tell a seller from a buyer on GET /api/home - see viewerOf
	JWTSecret string

	// how a stored path becomes a fetchable address. zero value = this api's own /images/
	URLs imagestore.URLs

	// how many searches may run at once - a send takes a slot, a receive frees it. nil = no cap.
	// this is what protects the database: a per-caller limit cannot bound the total, since hundreds
	// of phones share one address on a mobile network.
	SearchSlots chan struct{}

	// the home payload and each category listing, held for a few seconds. nil = build every time,
	// which is what the tests do. see publicCache for why search is not in it.
	Cache *publicCache
}

const (
	// **not a display cap - this is the whole inventory.** VIP is a product with a fixed number of
	// units, and the app draws all five whether or not they are sold, because an empty slot is what
	// tells a passing owner that a place is for sale. VipShopsCarousel.slotCount is the other half.
	vipShopsLimit = 5

	// per *shop category*: "Лучшие предложения" is a tab strip and each tab is its own ranking, so
	// the worst case is four × fifteen. BestOffersList.slotCount mirrors it.
	bestOffersLimit = 15

	// the category drill-down and search: the same screen and the same grid, so the same cap
	categoryProductsLimit = 100
	searchResultsLimit    = 100

	// how many shops' prices a category shows for one product before moving to the next - two rows of the
	// grid. without it a popular category is one product repeated, since every shop prices the same rows.
	categoryOffersPerLine = 4

	// the same rule for search, a little wider: the caller named the product, so more of its offers are
	// the answer. a full page is the app's only sign that more may follow - see SearchProducts.
	searchOffersPerLine = 6

	// three characters in at least one word - the shortest piece the trigram index can look up
	// the app enforces the same rule before sending.
	minSearchWordLen = 3

	// an unbounded query string is an anonymous caller deciding how much work the database does
	maxSearchQueryLen = 60

	// rows in the as-you-type panel. a short list a thumb can read without scrolling, and the panel
	// covers the results underneath it - ProductSuggestionsPanel.maxRows is the other half.
	suggestLimit = 8
)

// the payload behind GET /api/home. one endpoint rather than three, because the screen renders all of it
// at once: one round trip, one spinner, one error state.
type HomeResponse struct {
	VipShops []ShopResponse `json:"vip_shops"`

	// "Лучшие предложения", one entry per shop category - the tabs on that section. grouped rather than
	// flat because the index only compares shops of the same category, so "6% cheaper" means a different
	// market on each row. all groups arrive together so switching a tab is instant.
	BestOffers []CategoryOffersResponse `json:"best_offers"`

	// how many products a new shop of each category is seeded with. the same for everybody, so it
	// rides in the cached read; the "add shop" form shows it before the shop exists.
	TemplateSizes map[string]int `json:"template_sizes"`

	// the seller's copy: no comparison on any shop and no ranking, whose order alone would be the
	// index. the app says why the section is empty instead of drawing fifteen open slots
	IndexHidden bool `json:"index_hidden"`
}

// one tab of "Лучшие предложения". only categories with ranked shops are sent: the app draws one
// tab per entry, so an empty category would be a tab that leads nowhere.
type CategoryOffersResponse struct {
	Category string         `json:"category"`
	Shops    []ShopResponse `json:"shops"`
}

// "Популярные категории" is deliberately not in this payload: the twelve tiles are a fixed list the
// app already holds (features/products/data/product_category.dart). tapping one fetches its products.

// GET /api/home - the same bytes for everybody of one audience, so it is answered from publicCache
func (h *Home) Get(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()
	who := viewerOf(ctx, r, h.JWTSecret, h.Queries)

	h.Cache.serve(w, r, who.cacheKey("home"), "home content", func(ctx context.Context) (any, error) {
		content, err := h.homeContent(ctx)
		if err != nil || who.audience == buyers {
			return content, err
		}
		return withoutIndex(content), nil
	})
}

func withoutIndex(content HomeResponse) HomeResponse {
	for i := range content.VipShops {
		content.VipShops[i].hidePricing()
	}
	// ListVipShops orders on basket price, which would rank the placements without a single number
	slices.SortFunc(content.VipShops, func(a, b ShopResponse) int { return cmp.Compare(a.ID, b.ID) })

	content.BestOffers = []CategoryOffersResponse{}
	content.IndexHidden = true
	return content
}

func (h *Home) homeContent(ctx context.Context) (HomeResponse, error) {
	// five queries, sequential rather than fanned out: each is one indexed read, and running them in
	// parallel would take five connections out of a pool of ten to serve a single request
	vip, err := h.Queries.ListVipShops(ctx, vipShopsLimit)
	if err != nil {
		return HomeResponse{}, fmt.Errorf("listing vip shops: %w", err)
	}

	// one call per category rather than one window function: sqlc could not compile the window
	// version. four extra round trips, each a single indexed read.
	offers := make([]CategoryOffersResponse, 0, len(catalog.AllShopCategories))
	for _, category := range catalog.AllShopCategories {
		rows, err := h.Queries.ListBestOffersInCategory(ctx, db.ListBestOffersInCategoryParams{
			Category: string(category),
			Limit:    bestOffersLimit,
		})
		if err != nil {
			return HomeResponse{}, fmt.Errorf("listing best offers for %q: %w", category, err)
		}
		// a category with no ranked shops produces no tab at all
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
		// a nil slice encodes as `null` and the app decodes this as a list - which is a crash on the
		// one path an empty database guarantees
		VipShops:   make([]ShopResponse, 0, len(vip)),
		BestOffers: offers,
	}

	response.TemplateSizes = make(map[string]int, len(catalog.AllShopCategories))
	for _, category := range catalog.AllShopCategories {
		response.TemplateSizes[string(category)] = catalog.Size(string(category))
	}

	for _, shop := range vip {
		// its own mapper: ListVipShops LEFT JOINs the index, so a paid placement appears the moment it
		// is granted and simply carries no price yet
		response.VipShops = append(response.VipShops, shopFromVip(h.URLs, shop))
	}
	return response, nil
}

// GET /api/categories/{code}/products - the drill-down behind a "Популярные категории" tile.
// products, not shops: the question is "what can I buy and for how much", and the shop's name rides
// on every row so the list answers both at once.
func (h *Home) ProductsByCategory(w http.ResponseWriter, r *http.Request) {
	code := r.PathValue("code")

	// without this any string in the url comes back as an empty list, which reads as "nothing here"
	// rather than "that is not a category"
	if !catalog.IsValidProductCategory(code) {
		writeAPIError(w, http.StatusNotFound, "unknown_category", "unknown product category")
		return
	}

	// the twelve codes are validated above, so the cache's key space is fixed
	h.Cache.serve(w, r, "category:"+code, "products", func(ctx context.Context) (any, error) {
		rows, err := h.Queries.ListProductsByCategory(ctx, db.ListProductsByCategoryParams{
			Category:      code,
			OffersPerLine: categoryOffersPerLine,
			ResultLimit:   categoryProductsLimit,
		})
		if err != nil {
			return nil, fmt.Errorf("listing products for category %q: %w", code, err)
		}

		response := make([]CategoryProductResponse, 0, len(rows))
		for _, row := range rows {
			response = append(response, categoryProductFromRow(h.URLs, row))
		}
		return response, nil
	})
}

// GET /api/products/search?q=... - the home screen's search field. products across every shop, in
// the same shape ProductsByCategory answers with, so the app reuses its grid.
//
// **every word counts, in any order**: "пвс кабель" finds "Кабель медный ПВС 2х1,5". names and query
// are both lowercased with ё written as е - see searchPatterns.
//
// **paged by `offset`, a hundred rows a page, and a page shorter than `searchResultsLimit` is the last
// one**: the app shows "Ещё" only after a full page and sends nothing otherwise. A result of exactly a
// hundred costs one empty follow-up request.
func (h *Home) SearchProducts(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))

	// runes, not bytes: every letter in "цемент" is two bytes, so a byte ceiling would cut a russian
	// query off at half the words an english one gets
	if utf8.RuneCountInString(query) > maxSearchQueryLen {
		writeAPIError(w, http.StatusBadRequest, "query_too_long", "search query is too long")
		return
	}
	anchor, patterns, ok := searchPatterns(query)
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "query_too_short", "search query is too short")
		return
	}

	offset := int64(0)
	if raw := r.URL.Query().Get("offset"); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 32)
		if err != nil || parsed < 0 {
			writeAPIError(w, http.StatusBadRequest, "bad_offset", "offset must be a non-negative number")
			return
		}
		offset = parsed
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// a slot before a connection. the wait is the query's own deadline, so a burst queues rather
	// than being refused and a caller that never gets one is told to come back.
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
		Anchor:        anchor,
		Patterns:      patterns,
		OffersPerLine: searchOffersPerLine,
		ResultOffset:  int32(offset),
		ResultLimit:   searchResultsLimit,
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
		// the two row structs are field-for-field identical, so the conversion is compiler-checked: a
		// column added to one query and not the other stops the build
		response = append(response, categoryProductFromRow(h.URLs, db.ListProductsByCategoryRow(row)))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// GET /api/products/suggest?q=... - the names offered under the search field as it is typed, as a
// json array of strings.
//
// **answered from internal/catalog's in-memory copy, with no query at all**: this is the one read the
// app makes while a thumb is still moving, and a database round trip per keystroke is the shape of
// request that takes the pool down. What it costs is a few hundred substring comparisons.
func (h *Home) SuggestProducts(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))

	if utf8.RuneCountInString(query) > maxSearchQueryLen {
		writeAPIError(w, http.StatusBadRequest, "query_too_long", "search query is too long")
		return
	}

	// too short is an empty list rather than the 400 the search answers with: here it is the ordinary
	// state of a field somebody is halfway through typing, not a request that went wrong
	var names []string
	if _, ok := searchable(query); ok {
		names = catalog.Suggest(query, suggestLimit)
	}
	if names == nil {
		names = []string{}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(names)
}

// one product row into the wire shape, shared by the two endpoints that return products across shops
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
			Specs:         row.Specs,
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

// what a customer typed, as the two arguments SearchProducts takes: one pattern per word (all
// required, any order) plus the longest word again as the anchor - the only one the trigram index
// can serve, since it cannot do `~ ALL`.
func searchPatterns(query string) (anchor string, patterns []string, ok bool) {
	words, ok := searchable(query)
	if !ok {
		return "", nil, false
	}

	longest := 0
	for _, word := range words {
		pattern := wordPattern(word)
		patterns = append(patterns, pattern)
		if n := utf8.RuneCountInString(word); n > longest {
			longest, anchor = n, pattern
		}
	}
	return anchor, patterns, true
}

// the words of a query, and whether one of them is long enough to look up at all
func searchable(query string) (words []string, ok bool) {
	words = catalog.QueryWords(query)
	for _, word := range words {
		if utf8.RuneCountInString(word) >= minSearchWordLen {
			return words, true
		}
	}
	return words, false
}

// one word as a regex: the word itself plus its cyrillic spelling when typed in latin ("kabel" ->
// "кабел"). both, because catalogue names carry latin brands too - VERO, TYTAN, LED.
func wordPattern(word string) string {
	pattern := regexp.QuoteMeta(word)
	if cyrillic := catalog.Cyrillic(word); cyrillic != "" && cyrillic != word {
		pattern = "(" + pattern + "|" + regexp.QuoteMeta(cyrillic) + ")"
	}
	return pattern
}

// a product plus the name of the shop selling it. embedded rather than redeclared, so it serializes
// as a product object with one extra key and the app decodes it with the same Product.fromJson.
type CategoryProductResponse struct {
	ProductResponse
	ShopName string `json:"shop_name"`
}
