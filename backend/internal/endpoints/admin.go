package endpoints

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
)

// the admin panel's api: the dashboard's statistics, moderation, the template editor and the
// orphaned-photo sweep.
//
// **the whole privileged surface is deliberately in one file, middleware included.** it is the only
// place in the api where one caller acts on another user's data, so "read this file and you have
// read the entire privileged path" is worth more here than tidy layering.
type Admin struct {
	// the pool, not just Queries, because the template sync is three statements that must land
	// together - see SyncTemplate
	Pool    *pgxpool.Pool
	Queries *db.Queries

	// shared with the app-facing endpoints, so the panel shows the same urls the phone does
	URLs imagestore.URLs

	// where uploaded photos live, for the orphan sweep at the bottom of this file
	Images imagestore.Storage
}

// how many rows one list request may return. the panel filters and sorts client-side so it wants
// the whole set in one request; offset is wired through for the day it needs a pager.
const (
	adminListDefaultLimit = 200
	adminListMaxLimit     = 500

	// a ceiling, not a page: the panel lists every unfinished catalogue in one modal
	adminAttentionLimit = 100

	// **a design number, not a page size**: the card asks whether anybody is competing for the
	// cheapest place, and the sixth shop in a market says nothing the fifth did not
	adminRankingDepth = 5
)

// RequireAdmin refuses anyone whose role is not `admin` - the only thing between a logged-in shop
// owner and everybody else's account. it must be composed *inside* auth.RequireAuth, which is what
// puts the caller's id on the context.
//
// **the role is read from the database on every request and never from the token**: jwt.go carries
// no role claim, so a demoted admin stops administering immediately rather than when their token
// expires.
func (a *Admin) RequireAdmin(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := auth.UserIDFromContext(r.Context())
		if !ok {
			// unreachable unless this was wired without RequireAuth above it - fail closed
			writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
			return
		}

		ctx, cancel := dbctx.WithTimeout(r.Context())
		defer cancel()

		role, err := a.Queries.GetUserRole(ctx, userID)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				writeAPIError(w, http.StatusUnauthorized, "account_deleted", "this account no longer exists")
				return
			}
			// 503 rather than 403: a minute of database trouble must not read as "you are not
			// allowed", which sends somebody hunting for a permissions problem that does not exist
			log.Printf("CRITICAL: cannot verify admin role for user %d: %v", userID, err)
			writeAPIError(w, http.StatusServiceUnavailable, "service_unavailable", "could not verify permissions")
			return
		}

		if role != "admin" {
			// the same answer for a customer and for a shop owner - nothing is gained by saying which
			writeAPIError(w, http.StatusForbidden, "forbidden_role", "administrator access required")
			return
		}

		next(w, r)
	}
}

// ─────────────────────────────── statistics ───────────────────────────────

type adminStatsResponse struct {
	Users          adminUserCounts     `json:"users"`
	Shops          adminShopCounts     `json:"shops"`
	Products       adminProductCounts  `json:"products"`
	Signups        []adminSignupDay    `json:"signups"`
	ShopCategories []adminShopCategory `json:"shop_categories"`

	// where every shop sits between "created" and "publishing prices" - the one figure here that
	// says where the product is losing people rather than how much of it exists
	Funnel adminFunnel `json:"funnel"`

	// the shops worth phoning, nearest to finishing first
	Attention []adminAttentionShop `json:"attention"`

	// the cheapest few shops in each market, in order
	Rankings []adminRankedShop `json:"rankings"`

	// what a basket costs in each market today, and the last 30 days of it
	Baskets       []adminCategoryBasket `json:"baskets"`
	BasketHistory []adminBasketDay      `json:"basket_history"`

	// live paid placements, soonest to lapse first
	VIP []adminVipPlacement `json:"vip"`

	GeneratedAt string `json:"generated_at"`
}

// three buckets. the panel sums `empty` and `started` into "not in the comparison", which is the
// only distinction the all-or-nothing rule makes - they stay apart here because the query holds them.
type adminFunnel struct {
	Shops    int64 `json:"shops"`
	Empty    int64 `json:"empty"`
	Started  int64 `json:"started"`
	Complete int64 `json:"complete"`
}

// one unfinished catalogue plus everything needed to act on it: the age, what is missing, and the
// number to ring
type adminAttentionShop struct {
	ID           int64  `json:"id"`
	Name         string `json:"name"`
	Category     string `json:"category"`
	CreatedAt    string `json:"created_at"`
	ContactPhone string `json:"contact_phone"`
	OwnerName    string `json:"owner_name"`
	OwnerPhone   string `json:"owner_phone"`
	TemplateRows int64  `json:"template_rows"`
	PricedRows   int64  `json:"priced_rows"`
	Remaining    int64  `json:"remaining"`
}

// one shop inside one market's ranking, cheapest first - the position in the slice is the rank.
//
// **the raw price index is here, and the panel is the one surface allowed to carry it**: an admin is
// the reader who has been taught that 100 is the market price. the app gets a tier and a percentage.
type adminRankedShop struct {
	Category    string `json:"category"`
	ShopID      int64  `json:"shop_id"`
	ShopName    string `json:"shop_name"`
	PriceIndex  int64  `json:"price_index"`
	BasketPrice int64  `json:"basket_price"`
}

// what one market costs today. `shops` is how many baskets went into the average: a figure that
// moved because three shops became nine is a different event from one that moved on a price change.
type adminCategoryBasket struct {
	Category  string `json:"category"`
	Shops     int64  `json:"shops"`
	AvgBasket int64  `json:"avg_basket"`
	MinBasket int64  `json:"min_basket"`
	MaxBasket int64  `json:"max_basket"`
}

// one day of one market. a day with no row is a day the server was not running, and the panel draws
// the gap rather than inventing a point.
type adminBasketDay struct {
	Day       string `json:"day"`
	Category  string `json:"category"`
	Shops     int32  `json:"shops"`
	AvgBasket int64  `json:"avg_basket"`
}

type adminVipPlacement struct {
	ID       int64  `json:"id"`
	Name     string `json:"name"`
	Category string `json:"category"`
	Until    string `json:"until"`
	DaysLeft int32  `json:"days_left"`
}

type adminUserCounts struct {
	Total      int64 `json:"total"`
	Customers  int64 `json:"customers"`
	ShopOwners int64 `json:"shop_owners"`
	Admins     int64 `json:"admins"`
	New7d      int64 `json:"new_7d"`
	New30d     int64 `json:"new_30d"`
}

type adminShopCounts struct {
	Total int64 `json:"total"`
	New7d int64 `json:"new_7d"`
	VIP   int64 `json:"vip"`
	// inventory, sent rather than written into the panel: a panel with its own copy would keep
	// reporting «3 из 5» the day the carousel grew to six
	VipSlots int64 `json:"vip_slots"`
	// shops that have priced their whole template and so appear in the comparison - the number that
	// decides whether the home screen has anything on it
	Ranked int64 `json:"ranked"`
}

type adminProductCounts struct {
	Total  int64 `json:"total"`
	Priced int64 `json:"priced"`
	Custom int64 `json:"custom"`
}

type adminSignupDay struct {
	Day   string `json:"day"`
	Users int64  `json:"users"`
	Shops int64  `json:"shops"`
}

type adminShopCategory struct {
	Category string `json:"category"`
	Shops    int64  `json:"shops"`
	Ranked   int64  `json:"ranked"`
	VIP      int64  `json:"vip"`
}

// GET /api/admin/stats - everything the dashboard draws, in one request.
//
// the queries run sequentially on one shared deadline, the same shape Home.Get uses: fanning them
// out would take most of the pool to serve one screen, and half a dashboard is not a useful answer.
func (a *Admin) Stats(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	fail := func(what string, err error) {
		log.Printf("CRITICAL: admin stats (%s) failed: %v", what, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load statistics")
	}

	overview, err := a.Queries.AdminOverview(ctx)
	if err != nil {
		fail("overview", err)
		return
	}
	signups, err := a.Queries.AdminSignupsByDay(ctx)
	if err != nil {
		fail("signups", err)
		return
	}
	shopCats, err := a.Queries.AdminShopsByCategory(ctx)
	if err != nil {
		fail("shop categories", err)
		return
	}
	funnel, err := a.Queries.AdminCatalogueFunnel(ctx)
	if err != nil {
		fail("funnel", err)
		return
	}
	// every unfinished shop, not a top 8 - the ceiling is only so one broken market cannot unbound it
	attention, err := a.Queries.AdminShopsNeedingAttention(ctx, adminAttentionLimit)
	if err != nil {
		fail("attention", err)
		return
	}
	placements, err := a.Queries.AdminVipPlacements(ctx, 8)
	if err != nil {
		fail("vip", err)
		return
	}
	rankings, err := a.Queries.AdminMarketRankings(ctx, adminRankingDepth)
	if err != nil {
		fail("market rankings", err)
		return
	}
	baskets, err := a.Queries.AdminCategoryBaskets(ctx)
	if err != nil {
		fail("category baskets", err)
		return
	}
	basketDays, err := a.Queries.AdminBasketHistory(ctx)
	if err != nil {
		fail("basket history", err)
		return
	}
	// make(..., 0, n) rather than nil: a nil encodes as `null` and the panel iterates what it gets
	response := adminStatsResponse{
		Users: adminUserCounts{
			Total: overview.UsersTotal, Customers: overview.UsersCustomers,
			ShopOwners: overview.UsersShopOwners, Admins: overview.UsersAdmins,
			New7d: overview.UsersNew7d, New30d: overview.UsersNew30d,
		},
		Shops: adminShopCounts{
			Total: overview.ShopsTotal, New7d: overview.ShopsNew7d,
			VIP: overview.ShopsVip, VipSlots: vipShopsLimit, Ranked: overview.ShopsRanked,
		},
		Products: adminProductCounts{
			Total: overview.ProductsTotal, Priced: overview.ProductsPriced, Custom: overview.ProductsCustom,
		},
		Funnel: adminFunnel{
			Shops: funnel.Shops, Empty: funnel.Empty, Started: funnel.Started,
			Complete: funnel.Complete,
		},
		Signups:        make([]adminSignupDay, 0, len(signups)),
		ShopCategories: make([]adminShopCategory, 0, len(shopCats)),
		Attention:      make([]adminAttentionShop, 0, len(attention)),
		Rankings:       make([]adminRankedShop, 0, len(rankings)),
		Baskets:        make([]adminCategoryBasket, 0, len(baskets)),
		BasketHistory:  make([]adminBasketDay, 0, len(basketDays)),
		VIP:            make([]adminVipPlacement, 0, len(placements)),
		GeneratedAt:    time.Now().UTC().Format(time.RFC3339),
	}

	for _, row := range signups {
		response.Signups = append(response.Signups, adminSignupDay{Day: row.Day, Users: row.Users, Shops: row.Shops})
	}
	for _, row := range shopCats {
		response.ShopCategories = append(response.ShopCategories, adminShopCategory{
			Category: row.Category, Shops: row.Shops, Ranked: row.Ranked, VIP: row.Vip,
		})
	}
	for _, row := range attention {
		response.Attention = append(response.Attention, adminAttentionShop{
			ID: row.ID, Name: row.Name, Category: row.Category,
			CreatedAt: timestampString(row.CreatedAt), ContactPhone: row.ContactPhone,
			OwnerName: row.OwnerName.String, OwnerPhone: row.OwnerPhone,
			TemplateRows: row.TemplateRows, PricedRows: row.PricedRows, Remaining: row.Remaining,
		})
	}
	for _, row := range rankings {
		response.Rankings = append(response.Rankings, adminRankedShop{
			Category: row.Category, ShopID: row.ShopID, ShopName: row.ShopName,
			PriceIndex: row.PriceIndex, BasketPrice: row.BasketPrice,
		})
	}
	for _, row := range baskets {
		response.Baskets = append(response.Baskets, adminCategoryBasket{
			Category: row.Category, Shops: row.Shops, AvgBasket: row.AvgBasket,
			MinBasket: row.MinBasket, MaxBasket: row.MaxBasket,
		})
	}
	for _, row := range basketDays {
		response.BasketHistory = append(response.BasketHistory, adminBasketDay{
			Day: row.Day, Category: row.Category, Shops: row.Shops, AvgBasket: row.AvgBasket,
		})
	}
	for _, row := range placements {
		response.VIP = append(response.VIP, adminVipPlacement{
			ID: row.ID, Name: row.Name, Category: row.Category,
			Until: timestampString(row.VipUntil), DaysLeft: row.DaysLeft,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// ─────────────────────────────── users ───────────────────────────────

type adminUserResponse struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	Phone     string `json:"phone"`
	Role      string `json:"role"`
	ShopCount int64  `json:"shop_count"`
	CreatedAt string `json:"created_at"`
}

// GET /api/admin/users
func (a *Admin) ListUsers(w http.ResponseWriter, r *http.Request) {
	limit, offset := adminPaging(r)

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := a.Queries.AdminListUsers(ctx, db.AdminListUsersParams{Limit: limit, Offset: offset})
	if err != nil {
		log.Printf("CRITICAL: admin user list failed: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load users")
		return
	}

	users := make([]adminUserResponse, 0, len(rows))
	for _, row := range rows {
		users = append(users, adminUserResponse{
			ID:        row.ID,
			Name:      row.Name.String,
			Phone:     row.Phone,
			Role:      row.Role,
			ShopCount: row.ShopCount,
			CreatedAt: timestampString(row.CreatedAt),
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"users": users, "limit": limit, "offset": offset})
}

// DELETE /api/admin/users/{id} - an admin destroying somebody else's account.
//
// the same cascade DELETE /api/me runs: the shops go, and each takes its products. a hard delete for
// the same reason - a row nobody can reach is still a phone number somebody asked to have erased.
// the only account it refuses is the last admin, which is the one state with no way back.
func (a *Admin) DeleteUser(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	targetID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || targetID <= 0 {
		writeAPIError(w, http.StatusBadRequest, "invalid_id", "user id must be a positive integer")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// read before deleting - afterwards there is nothing left to read, and this is what turns "no
	// such user" into a 404 rather than a silent success
	role, err := a.Queries.GetUserRole(ctx, targetID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "user_not_found", "no user with that id")
			return
		}
		log.Printf("CRITICAL: admin %d could not read role of user %d: %v", adminID, targetID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the user")
		return
	}

	if role == "admin" && !a.anotherAdminRemains(w, adminID, targetID, ctx) {
		return
	}

	deleted, err := a.Queries.AdminDeleteUser(ctx, targetID)
	if err != nil {
		log.Printf("CRITICAL: admin %d failed to delete user %d: %v", adminID, targetID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the user")
		return
	}
	if deleted == 0 {
		// it existed when we read its role, so it went between the two statements
		writeAPIError(w, http.StatusNotFound, "user_not_found", "no user with that id")
		return
	}

	// ids and a role only: an audit line says who did what to whom, and the name and number of the
	// account just erased are exactly what must not be copied into a log on the way out
	log.Printf("ADMIN %d deleted user %d (role=%s)", adminID, targetID, role)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}

// ─────────────────────────────── shops ───────────────────────────────

type adminShopResponse struct {
	ID           int64  `json:"id"`
	Name         string `json:"name"`
	Category     string `json:"category"`
	Address      string `json:"address"`
	ContactPhone string `json:"contact_phone"`
	IsVIP        bool   `json:"is_vip"`
	VipUntil     string `json:"vip_until,omitempty"`
	// suspended by an admin, independent of catalogue completeness - see AdminSetShopExcluded
	ExcludedFromIndex bool `json:"excluded_from_index"`

	OwnerID    int64  `json:"owner_id"`
	OwnerName  string `json:"owner_name"`
	OwnerPhone string `json:"owner_phone"`

	ProductsTotal int64 `json:"products_total"`
	// the catalogue progress bar, over template rows only - the owner's own products are not in the
	// shared basket
	TemplateTotal  int64 `json:"template_total"`
	TemplatePriced int64 `json:"template_priced"`

	// null together or present together - the index row has no partial state
	PriceIndex  *int64 `json:"price_index"`
	BasketPrice *int64 `json:"basket_price"`

	CreatedAt string `json:"created_at"`
}

// GET /api/admin/shops - one of the two places the raw price index leaves the server. everywhere
// else ShopResponse carries a tier and a percentage instead.
func (a *Admin) ListShops(w http.ResponseWriter, r *http.Request) {
	limit, offset := adminPaging(r)

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := a.Queries.AdminListShops(ctx, db.AdminListShopsParams{Limit: limit, Offset: offset})
	if err != nil {
		log.Printf("CRITICAL: admin shop list failed: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load shops")
		return
	}

	shops := make([]adminShopResponse, 0, len(rows))
	for _, row := range rows {
		shop := adminShopResponse{
			ID:                row.ID,
			Name:              row.Name,
			Category:          row.Category,
			Address:           row.Address,
			ContactPhone:      row.ContactPhone,
			IsVIP:             row.IsVip,
			VipUntil:          timestampString(row.VipUntil),
			ExcludedFromIndex: row.ExcludedFromIndex,
			OwnerID:           row.OwnerID,
			OwnerName:         row.OwnerName.String,
			OwnerPhone:        row.OwnerPhone,
			ProductsTotal:     row.ProductsTotal,
			TemplateTotal:     row.TemplateTotal,
			TemplatePriced:    row.TemplatePriced,
			CreatedAt:         timestampString(row.CreatedAt),
		}
		if row.PriceIndex.Valid {
			index := row.PriceIndex.Int64
			shop.PriceIndex = &index
		}
		if row.BasketPrice.Valid {
			basket := row.BasketPrice.Int64
			shop.BasketPrice = &basket
		}
		shops = append(shops, shop)
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"shops": shops, "limit": limit, "offset": offset})
}

// DELETE /api/admin/shops/{id} - the shop and its products, leaving the owner's account alone. no
// ownership check beyond RequireAdmin: acting on other people's shops is what this panel is for.
func (a *Admin) DeleteShop(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	shopID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || shopID <= 0 {
		writeAPIError(w, http.StatusBadRequest, "invalid_id", "shop id must be a positive integer")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	deleted, err := a.Queries.DeleteShop(ctx, shopID)
	if err != nil {
		log.Printf("CRITICAL: admin %d failed to delete shop %d: %v", adminID, shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the shop")
		return
	}
	if deleted == 0 {
		writeAPIError(w, http.StatusNotFound, "shop_not_found", "no shop with that id")
		return
	}

	log.Printf("ADMIN %d deleted shop %d", adminID, shopID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}

// ─────────────────────────────── helpers ───────────────────────────────

// ?limit= and ?offset=, clamped rather than rejected - a 400 because somebody typed limit=0 in a
// url bar is worse than quietly giving them the default
func adminPaging(r *http.Request) (limit, offset int32) {
	limit = adminListDefaultLimit
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			limit = int32(min(n, adminListMaxLimit))
		}
	}
	if raw := r.URL.Query().Get("offset"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			offset = int32(n)
		}
	}
	return limit, offset
}

// a nullable postgres timestamp as RFC3339, or "" when null - a zero time would arrive as
// "0001-01-01T00:00:00Z" and render as a date in the year one
func timestampString(ts pgtype.Timestamptz) string {
	if !ts.Valid {
		return ""
	}
	return ts.Time.UTC().Format(time.RFC3339)
}

// ─────────────────────────── editing ───────────────────────────

// the roles an admin may assign through the panel.
//
// **`admin` is in this set, which means a stolen admin token is a permanent compromise** rather than
// one that ends when the token expires. the founder asked for the power; this is the cost of it.
//
// what must not change: **nothing unauthenticated can assign it.** the login maps anything that is
// not shop_owner to customer, and only ever upgrades customer -> shop_owner.
var assignableRoles = map[string]bool{"customer": true, "shop_owner": true, "admin": true}

// anotherAdminRemains is the whole of what stops the panel destroying its own access. **409 rather
// than 403 on purpose**: the panel signs itself out on a 403, and this is not a revoked admin - it
// is a request that was understood, allowed and impossible in the current state.
//
// the count and the write are not one transaction: two admins demoting each other in the same second
// could both pass, which at one machine is not a race worth a lock.
func (a *Admin) anotherAdminRemains(w http.ResponseWriter, adminID, targetID int64, ctx context.Context) bool {
	admins, err := a.Queries.AdminCountAdmins(ctx)
	if err != nil {
		log.Printf("CRITICAL: admin %d could not count administrators before changing user %d: %v",
			adminID, targetID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not check administrators")
		return false
	}
	if admins <= 1 {
		writeAPIError(w, http.StatusConflict, "last_admin",
			"this is the last administrator - grant the role to somebody else first")
		return false
	}
	return true
}

// PUT /api/admin/users/{id} - name and role. phone is not editable: it is the identity key every
// login looks an account up by, so retyping it would orphan the account from its own login.
func (a *Admin) UpdateUser(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	targetID, ok := adminPathID(w, r, "user")
	if !ok {
		return
	}

	var req struct {
		Name string `json:"name"`
		Role string `json:"role"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeAPIError(w, http.StatusBadRequest, "name_required", "a name is required")
		return
	}
	if utf8.RuneCountInString(req.Name) > maxUserNameLen {
		writeAPIError(w, http.StatusBadRequest, "name_too_long", "name is longer than the maximum allowed length")
		return
	}
	if !assignableRoles[req.Role] {
		writeAPIError(w, http.StatusBadRequest, "invalid_role", "role must be customer, shop_owner or admin")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	current, err := a.Queries.GetUserRole(ctx, targetID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "user_not_found", "no user with that id")
			return
		}
		log.Printf("CRITICAL: admin %d could not read role of user %d: %v", adminID, targetID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not update the user")
		return
	}
	// the one refusal left, and it is arithmetic rather than policy: zero administrators is the one
	// state with no way back through any screen. demoting the second-to-last is fine, yourself included.
	if current == "admin" && req.Role != "admin" && !a.anotherAdminRemains(w, adminID, targetID, ctx) {
		return
	}

	updated, err := a.Queries.AdminUpdateUser(ctx, db.AdminUpdateUserParams{
		ID:   targetID,
		Name: pgtype.Text{String: req.Name, Valid: true},
		Role: req.Role,
	})
	if err != nil {
		log.Printf("CRITICAL: admin %d failed to update user %d: %v", adminID, targetID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not update the user")
		return
	}

	log.Printf("ADMIN %d updated user %d (role %s -> %s)", adminID, targetID, current, updated.Role)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(adminUserResponse{
		ID:        updated.ID,
		Name:      updated.Name.String,
		Phone:     updated.Phone,
		Role:      updated.Role,
		CreatedAt: timestampString(updated.CreatedAt),
	})
}

// PUT /api/admin/shops/{id} - the same fields the owner's own edit form submits. it reuses
// UpdateShop, which keeps `category` and `vip_until` out of reach by construction: category decided
// which template seeded this catalogue, and vip_until is a paid placement with its own endpoint.
func (a *Admin) UpdateShop(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	shopID, ok := adminPathID(w, r, "shop")
	if !ok {
		return
	}

	var req struct {
		Name         string  `json:"name"`
		Address      string  `json:"address"`
		ContactPhone string  `json:"contact_phone"`
		Latitude     float64 `json:"latitude"`
		Longitude    float64 `json:"longitude"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	req.Name = strings.TrimSpace(req.Name)
	req.Address = strings.TrimSpace(req.Address)
	req.ContactPhone = strings.TrimSpace(req.ContactPhone)
	if req.Name == "" || req.Address == "" || req.ContactPhone == "" {
		writeAPIError(w, http.StatusBadRequest, "missing_fields", "name, address and contact phone are required")
		return
	}
	if utf8.RuneCountInString(req.Name) > 150 || utf8.RuneCountInString(req.ContactPhone) > 50 {
		writeAPIError(w, http.StatusBadRequest, "field_too_long", "a field is longer than the maximum allowed length")
		return
	}
	if failure := validateCoordinates(req.Latitude, req.Longitude); failure != nil {
		failure.write(w)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	updated, err := a.Queries.UpdateShop(ctx, db.UpdateShopParams{
		ID:            shopID,
		Name:          req.Name,
		ContactPhone:  req.ContactPhone,
		Address:       req.Address,
		StMakepoint:   req.Longitude, // ST_MakePoint takes (longitude, latitude) - the reverse of the spoken order
		StMakepoint_2: req.Latitude,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "shop_not_found", "no shop with that id")
			return
		}
		log.Printf("CRITICAL: admin %d failed to update shop %d: %v", adminID, shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not update the shop")
		return
	}

	log.Printf("ADMIN %d updated shop %d", adminID, shopID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"id": updated.ID, "name": updated.Name, "updated": true})
}

// PUT /api/admin/shops/{id}/vip - grant or revoke a paid placement.
//
// logged like a deletion, because it is a commercial decision with money behind it and "when did
// this shop become VIP" is a question somebody will ask. `days` rather than an absolute date,
// because the panel's realistic input is "sold them a month"; zero or missing revokes.
func (a *Admin) SetVIP(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	shopID, ok := adminPathID(w, r, "shop")
	if !ok {
		return
	}

	var req struct {
		Days int `json:"days"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}
	// a slipped keypress in a number box should not sell a placement until the year 2190
	if req.Days > 730 {
		writeAPIError(w, http.StatusBadRequest, "invalid_period", "a placement cannot be granted for more than 730 days")
		return
	}

	until := pgtype.Timestamptz{}
	if req.Days > 0 {
		until = pgtype.Timestamptz{Time: time.Now().AddDate(0, 0, req.Days), Valid: true}
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	updated, err := a.Queries.SetShopVIP(ctx, db.SetShopVIPParams{ID: shopID, VipUntil: until})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "shop_not_found", "no shop with that id")
			return
		}
		log.Printf("CRITICAL: admin %d failed to set vip on shop %d: %v", adminID, shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not update the placement")
		return
	}

	if req.Days > 0 {
		log.Printf("ADMIN %d granted shop %d a VIP placement for %d days", adminID, shopID, req.Days)
	} else {
		log.Printf("ADMIN %d revoked shop %d's VIP placement", adminID, shopID)
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"id":        updated.ID,
		"is_vip":    updated.IsVip,
		"vip_until": timestampString(updated.VipUntil),
	})
}

// PUT /api/admin/shops/{id}/exclude - pull a shop out of its market's comparison, or put it back.
//
// separate from catalogue completeness on purpose: shop_basket_index answers "is every product
// priced" and is derived from products, where this flag is an admin's own decision and has to win
// even when every price is filled in. flipping the column is all this does - a trigger recomputes.
func (a *Admin) SetExcluded(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	shopID, ok := adminPathID(w, r, "shop")
	if !ok {
		return
	}

	var req struct {
		Excluded bool `json:"excluded"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	updated, err := a.Queries.AdminSetShopExcluded(ctx, db.AdminSetShopExcludedParams{ID: shopID, ExcludedFromIndex: req.Excluded})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "shop_not_found", "no shop with that id")
			return
		}
		log.Printf("CRITICAL: admin %d failed to set excluded=%v on shop %d: %v", adminID, req.Excluded, shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not update the shop")
		return
	}

	if req.Excluded {
		log.Printf("ADMIN %d excluded shop %d from the price index", adminID, shopID)
	} else {
		log.Printf("ADMIN %d returned shop %d to the price index", adminID, shopID)
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"id":                  updated.ID,
		"excluded_from_index": updated.ExcludedFromIndex,
	})
}

// ─────────────────────────── products ───────────────────────────

// GET /api/admin/shops/{id}/products - one shop's whole catalogue, unfiltered. unlike the
// customer-facing grid: an admin opens this for the unpriced rows, or a price that looks wrong.
func (a *Admin) ListShopProducts(w http.ResponseWriter, r *http.Request) {
	shopID, ok := adminPathID(w, r, "shop")
	if !ok {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := a.Queries.ListProductsByShop(ctx, shopID)
	if err != nil {
		log.Printf("CRITICAL: admin product list for shop %d failed: %v", shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load products")
		return
	}

	products := make([]ProductResponse, 0, len(rows))
	for _, row := range rows {
		isTemplate, nameEditable, photoEditable := templateFlags(row.TemplateKey)
		imageURL, thumbURL, ownImage := productImage(a.URLs, row.ImagePath)
		products = append(products, ProductResponse{
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
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"products": products})
}

// PUT /api/admin/products/{id}
//
// **an admin gets the same three-way rule the owner gets, not a bypass of it.** the rule is data
// integrity rather than permissions: a renamed template row stops being the same product as its
// counterpart down the road, and an admin breaks the comparison exactly as thoroughly as an owner.
// what an admin actually needs here is the price, and that is editable on every row.
func (a *Admin) UpdateProduct(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	productID, ok := adminPathID(w, r, "product")
	if !ok {
		return
	}

	var req productRequest
	if !decodeJSONBody(w, r, &req) {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// read first, so the branch is decided by the database's template_key and never by the client
	existing, err := a.Queries.GetProduct(ctx, productID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "product_not_found", "no product with that id")
			return
		}
		log.Printf("CRITICAL: admin %d could not read product %d: %v", adminID, productID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not update the product")
		return
	}

	// a local shape: the three UPDATE statements each get their own sqlc row type and none converts
	// to another, so one struct assigned in three places is what lets the response be built once
	var updated struct {
		ID, ShopID                         int64
		Name, Category, Unit, Availability string
		Price                              pgtype.Int8
		TemplateKey, ImagePath             pgtype.Text
	}

	switch {
	case existing.TemplateKey.Valid && catalog.IsOwnerNamedSlot(existing.TemplateKey.String):
		fields, failure := req.validate()
		if failure != nil {
			failure.write(w)
			return
		}
		row, slotErr := a.Queries.UpdateProductSlot(ctx, db.UpdateProductSlotParams{
			ID: productID, Name: fields.name, Price: fields.price, Availability: fields.availability,
		})
		err = slotErr
		updated.ID, updated.ShopID, updated.Name = row.ID, row.ShopID, row.Name
		updated.Category, updated.Unit, updated.Availability = row.Category, row.Unit, row.Availability
		updated.Price, updated.TemplateKey, updated.ImagePath = row.Price, row.TemplateKey, row.ImagePath

	case existing.TemplateKey.Valid:
		fields, failure := req.validatePricing()
		if failure != nil {
			failure.write(w)
			return
		}
		row, priceErr := a.Queries.UpdateProductPricing(ctx, db.UpdateProductPricingParams{
			ID: productID, Price: fields.price, Availability: fields.availability,
		})
		err = priceErr
		updated.ID, updated.ShopID, updated.Name = row.ID, row.ShopID, row.Name
		updated.Category, updated.Unit, updated.Availability = row.Category, row.Unit, row.Availability
		updated.Price, updated.TemplateKey, updated.ImagePath = row.Price, row.TemplateKey, row.ImagePath

	default:
		fields, failure := req.validate()
		if failure != nil {
			failure.write(w)
			return
		}
		if !catalog.IsValidProductCategory(fields.category) {
			writeAPIError(w, http.StatusBadRequest, "invalid_category", "unknown product category")
			return
		}
		row, ownErr := a.Queries.UpdateProduct(ctx, db.UpdateProductParams{
			ID: productID, Name: fields.name, Price: fields.price,
			Category: fields.category, Unit: fields.unit, Availability: fields.availability,
		})
		err = ownErr
		updated.ID, updated.ShopID, updated.Name = row.ID, row.ShopID, row.Name
		updated.Category, updated.Unit, updated.Availability = row.Category, row.Unit, row.Availability
		updated.Price, updated.TemplateKey, updated.ImagePath = row.Price, row.TemplateKey, row.ImagePath
	}

	if err != nil {
		log.Printf("CRITICAL: admin %d failed to update product %d: %v", adminID, productID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not update the product")
		return
	}

	log.Printf("ADMIN %d updated product %d (shop %d)", adminID, productID, updated.ShopID)

	isTemplate, nameEditable, photoEditable := templateFlags(updated.TemplateKey)
	imageURL, thumbURL, ownImage := productImage(a.URLs, updated.ImagePath)
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(ProductResponse{
		ID: updated.ID, ShopID: updated.ShopID, Name: updated.Name,
		Category: updated.Category, Unit: updated.Unit,
		Price: nullableInt64(updated.Price), Availability: updated.Availability,
		IsTemplate: isTemplate, NameEditable: nameEditable,
		ImageURL: imageURL, ImageThumbURL: thumbURL, OwnImage: ownImage, PhotoEditable: photoEditable,
	})
}

// ─────────────────────────── anomalies ───────────────────────────

// how far off the market a price has to be before the report mentions it, and how many shops must
// have priced a line before "the market" means anything. both are query parameters and these are
// guesses until there is real data - 50% is deliberately loose, since at launch a genuinely cheap
// shop and a typo look alike.
const (
	anomalyDefaultThreshold = 0.5
	anomalyMinShops         = 3
	anomalyLimit            = 200
)

type adminAnomaly struct {
	ProductID    int64  `json:"product_id"`
	ShopID       int64  `json:"shop_id"`
	ShopName     string `json:"shop_name"`
	ShopCategory string `json:"shop_category"`
	Name         string `json:"name"`
	TemplateKey  string `json:"template_key"`
	// a row here is a phone call waiting to be made. both numbers travel: contact_phone is what the
	// shop publishes, owner_phone is the account the price was typed from.
	ContactPhone string `json:"contact_phone"`
	OwnerName    string `json:"owner_name"`
	OwnerPhone   string `json:"owner_phone"`
	Price        int64  `json:"price"`
	MedianPrice  int64  `json:"median_price"`
	MarketShops  int64  `json:"market_shops"`
	// signed: positive means dearer than the market's median for the same basket line
	DeviationPercent int64 `json:"deviation_percent"`
}

// GET /api/admin/anomalies?threshold=0.5&min_shops=3
func (a *Admin) Anomalies(w http.ResponseWriter, r *http.Request) {
	threshold := anomalyDefaultThreshold
	if raw := r.URL.Query().Get("threshold"); raw != "" {
		if v, err := strconv.ParseFloat(raw, 64); err == nil && v > 0 && v <= 100 {
			threshold = v
		}
	}
	minShops := int64(anomalyMinShops)
	if raw := r.URL.Query().Get("min_shops"); raw != "" {
		if v, err := strconv.ParseInt(raw, 10, 64); err == nil && v >= 2 {
			minShops = v
		}
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := a.Queries.AdminPriceAnomalies(ctx, db.AdminPriceAnomaliesParams{
		Column1: minShops,
		Column2: threshold,
		Limit:   anomalyLimit,
	})
	if err != nil {
		log.Printf("CRITICAL: admin anomaly report failed: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the report")
		return
	}

	anomalies := make([]adminAnomaly, 0, len(rows))
	for _, row := range rows {
		anomalies = append(anomalies, adminAnomaly{
			ProductID: row.ProductID, ShopID: row.ShopID, ShopName: row.ShopName,
			ShopCategory: row.ShopCategory, Name: row.Name, TemplateKey: row.TemplateKey.String,
			ContactPhone: row.ContactPhone, OwnerName: row.OwnerName.String, OwnerPhone: row.OwnerPhone,
			Price: row.Price, MedianPrice: row.MedianPrice, MarketShops: row.Shops,
			DeviationPercent: row.DeviationPercent,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"anomalies": anomalies,
		"threshold": threshold,
		"min_shops": minShops,
	})
}

// ─────────────────────────── templates ───────────────────────────

type adminTemplateItem struct {
	ID        int64  `json:"id"`
	Key       string `json:"key"`
	Name      string `json:"name"`
	Category  string `json:"category"`
	Unit      string `json:"unit"`
	ImagePath string `json:"image_path,omitempty"`
}

type adminTemplateCategory struct {
	Category    string              `json:"category"`
	Size        int                 `json:"size"`
	OwnerNamed  bool                `json:"owner_named"`
	Items       []adminTemplateItem `json:"items"`
	Shops       int64               `json:"shops"`
	MissingRows int64               `json:"missing_rows"`
	StaleRows   int64               `json:"stale_rows"`
}

// GET /api/admin/templates - what each category's template holds, and how far the shops seeded from
// it have drifted.
func (a *Admin) Templates(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	out := make([]adminTemplateCategory, 0, len(catalog.AllShopCategories))
	for _, category := range catalog.AllShopCategories {
		code := string(category)

		// from the table rather than the in-memory copy: the editor needs each row's id, and
		// internal/catalog holds what seeding needs - the product, not the record
		stored, err := a.Queries.AdminListTemplateItems(ctx, code)
		if err != nil {
			log.Printf("CRITICAL: template items for %s failed: %v", code, err)
			writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load templates")
			return
		}

		keys := make([]string, 0, len(stored))
		wire := make([]adminTemplateItem, 0, len(stored))
		for _, item := range stored {
			keys = append(keys, item.TemplateKey)
			wire = append(wire, adminTemplateItem{
				ID: item.ID, Key: item.TemplateKey, Name: item.Name,
				Category: item.Category, Unit: item.Unit, ImagePath: item.ImagePath.String,
			})
		}

		status, err := a.Queries.AdminTemplateStatus(ctx, db.AdminTemplateStatusParams{
			Category: code,
			Column2:  keys,
		})
		if err != nil {
			log.Printf("CRITICAL: template status for %s failed: %v", code, err)
			writeAPIError(w, http.StatusInternalServerError, "server_error", "could not read template status")
			return
		}

		out = append(out, adminTemplateCategory{
			Category:   code,
			Size:       len(stored),
			OwnerNamed: catalog.IsOwnerNamedCategory(code),
			Items:      wire,
			Shops:      status.Shops,
			// what every shop of this category should hold minus what they do: a shop created before a
			// product was added to the template is missing that row and nothing tells it
			MissingRows: status.Shops*int64(len(stored)) - status.PresentRows,
			StaleRows:   status.StaleRows,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"templates": out})
}

// POST /api/admin/templates/{category}/sync - push the current template into every existing shop of
// that category. seeding happens once at creation, so without this a template edit reaches nobody.
//
//	insert  - rows the template has and the shop does not, unpriced
//	update  - names/units/categories/photos for rows both have, prices untouched
//	delete  - rows the shop has and the template no longer does
//
// **the transaction is not decoration**: a shop left with the new rows inserted but the stale ones
// still there holds two versions of its own basket, and the index would total both.
//
// **two consequences worth knowing before pressing it**: adding a product drops every shop of the
// category out of the comparison until its owner prices the new row, and deleting one takes whatever
// price the owner had typed, with no undo.
func (a *Admin) SyncTemplate(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	code := r.PathValue("category")
	if !catalog.IsValidCategory(code) {
		writeAPIError(w, http.StatusBadRequest, "invalid_category", "unknown shop category")
		return
	}

	items := catalog.Template(code)
	if len(items) == 0 {
		writeAPIError(w, http.StatusBadRequest, "empty_template", "that category's template is empty")
		return
	}

	keys := make([]string, 0, len(items))
	rows := make([]adminTemplateSyncRow, 0, len(items))
	for _, item := range items {
		keys = append(keys, item.Key)
		rows = append(rows, adminTemplateSyncRow{
			TemplateKey: item.Key,
			Name:        item.Name,
			Category:    string(item.Category),
			Unit:        item.Unit,
			ImagePath:   item.ImagePath,
		})
	}
	payload, err := json.Marshal(rows)
	if err != nil {
		log.Printf("CRITICAL: could not encode %s template for sync: %v", code, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not prepare the sync")
		return
	}

	// names are rewritten for a template of products and left alone for one of slots: an обои row's
	// name is the owner's own wallpaper, and writing the placeholder back would erase all of them
	syncNames := !catalog.IsOwnerNamedCategory(code)

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	tx, err := a.Pool.Begin(ctx)
	if err != nil {
		log.Printf("CRITICAL: admin %d could not begin a sync transaction: %v", adminID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not start the sync")
		return
	}
	defer tx.Rollback(ctx) // no-op once Commit succeeds

	q := db.New(tx)

	inserted, err := q.AdminSyncTemplateInsert(ctx, db.AdminSyncTemplateInsertParams{Category: code, Column2: payload})
	if err != nil {
		log.Printf("CRITICAL: sync insert for %s failed: %v", code, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not add the new rows")
		return
	}

	updated, err := q.AdminSyncTemplateUpdate(ctx, db.AdminSyncTemplateUpdateParams{
		Category: code, Column2: payload, Column3: syncNames,
	})
	if err != nil {
		log.Printf("CRITICAL: sync update for %s failed: %v", code, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not update the existing rows")
		return
	}

	deleted, err := q.AdminSyncTemplateDelete(ctx, db.AdminSyncTemplateDeleteParams{Category: code, Column2: keys})
	if err != nil {
		log.Printf("CRITICAL: sync delete for %s failed: %v", code, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not remove the stale rows")
		return
	}

	if err := tx.Commit(ctx); err != nil {
		log.Printf("CRITICAL: sync commit for %s failed: %v", code, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "the sync could not be saved")
		return
	}

	log.Printf("ADMIN %d synced the %s template: +%d rows, ~%d updated, -%d removed",
		adminID, code, inserted, updated, deleted)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"category": code,
		"inserted": inserted,
		"updated":  updated,
		"deleted":  deleted,
	})
}

// the shape jsonb_to_recordset expands back into rows. **the field names are the recordset's column
// names in db/queries/admin.sql** - renaming one here silently stops the sync matching anything.
type adminTemplateSyncRow struct {
	TemplateKey string `json:"template_key"`
	Name        string `json:"name"`
	Category    string `json:"category"`
	Unit        string `json:"unit"`
	ImagePath   string `json:"image_path"`
}

// ─────────────────────────── routing ───────────────────────────

// one path, two verbs - the method split lives here rather than in two mux patterns
func (a *Admin) RouteUser(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPut:
		a.UpdateUser(w, r)
	case http.MethodDelete:
		a.DeleteUser(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (a *Admin) RouteShop(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPut:
		a.UpdateShop(w, r)
	case http.MethodDelete:
		a.DeleteShop(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// parses the {id} wildcard, writing its own 400. `noun` only shapes the message.
func adminPathID(w http.ResponseWriter, r *http.Request, noun string) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeAPIError(w, http.StatusBadRequest, "invalid_id", noun+" id must be a positive integer")
		return 0, false
	}
	return id, true
}

// ─────────────────────────── editing the templates themselves ───────────────────────────

// reloadTemplates re-reads product_templates into internal/catalog's in-memory copy.
//
// **every handler that writes that table must call this before responding.** seeding,
// IsOwnerNamedSlot and the sync payload all read from memory, so a write that skips the reload
// leaves the process serving the old list until it restarts.
func (a *Admin) reloadTemplates(ctx context.Context) error {
	rows, err := a.Queries.ListProductTemplates(ctx)
	if err != nil {
		return err
	}
	loaded := make([]catalog.Row, 0, len(rows))
	for _, row := range rows {
		loaded = append(loaded, catalog.Row{
			ShopCategory: row.ShopCategory,
			Key:          row.TemplateKey,
			Name:         row.Name,
			Category:     row.Category,
			Unit:         row.Unit,
			ImagePath:    row.ImagePath.String,
		})
	}
	catalog.Load(loaded)
	return nil
}

type templateItemRequest struct {
	ShopCategory string `json:"shop_category"`
	TemplateKey  string `json:"template_key"`
	Name         string `json:"name"`
	Category     string `json:"category"`
	Unit         string `json:"unit"`
	ImagePath    string `json:"image_path"`
}

// the column widths of `products`, which these are copied into at seeding: a row that fits
// product_templates but not products would fail at shop creation
const (
	maxTemplateKeyLen  = 60
	maxTemplateNameLen = 150
	maxTemplateUnitLen = 20
)

func (req templateItemRequest) clean() (templateItemRequest, *accessError) {
	req.TemplateKey = strings.TrimSpace(req.TemplateKey)
	req.Name = strings.TrimSpace(req.Name)
	req.Category = strings.TrimSpace(req.Category)
	req.Unit = strings.TrimSpace(req.Unit)
	req.ImagePath = strings.TrimSpace(req.ImagePath)

	if req.Name == "" || req.Unit == "" {
		return req, &accessError{http.StatusBadRequest, "missing_fields", "name and unit are required"}
	}
	// runes, not bytes: postgres counts varchar limits in characters
	if utf8.RuneCountInString(req.Name) > maxTemplateNameLen || utf8.RuneCountInString(req.Unit) > maxTemplateUnitLen {
		return req, &accessError{http.StatusBadRequest, "field_too_long", "a field is longer than allowed"}
	}
	if !catalog.IsValidProductCategory(req.Category) {
		return req, &accessError{http.StatusBadRequest, "invalid_category", "unknown product category"}
	}
	return req, nil
}

// GET /api/admin/templates/{category}/items
func (a *Admin) ListTemplateItems(w http.ResponseWriter, r *http.Request) {
	code := r.PathValue("category")
	if !catalog.IsValidCategory(code) {
		writeAPIError(w, http.StatusBadRequest, "invalid_category", "unknown shop category")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := a.Queries.AdminListTemplateItems(ctx, code)
	if err != nil {
		log.Printf("CRITICAL: template items for %s failed: %v", code, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the template")
		return
	}

	items := make([]adminTemplateItem, 0, len(rows))
	for _, row := range rows {
		items = append(items, adminTemplateItem{
			ID: row.ID, Key: row.TemplateKey, Name: row.Name,
			Category: row.Category, Unit: row.Unit, ImagePath: row.ImagePath.String,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"items": items})
}

// POST /api/admin/templates/{category}/items - add a product to a category's template.
//
// **it touches no existing shop, and that separation is the design**: this decides what the *next*
// shop is created with, and the sync button is what pushes it into the ones that already exist.
func (a *Admin) CreateTemplateItem(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	code := r.PathValue("category")
	if !catalog.IsValidCategory(code) {
		writeAPIError(w, http.StatusBadRequest, "invalid_category", "unknown shop category")
		return
	}

	var req templateItemRequest
	if !decodeJSONBody(w, r, &req) {
		return
	}
	req, failure := req.clean()
	if failure != nil {
		failure.write(w)
		return
	}

	if req.TemplateKey == "" {
		writeAPIError(w, http.StatusBadRequest, "missing_key", "a template key is required")
		return
	}
	if utf8.RuneCountInString(req.TemplateKey) > maxTemplateKeyLen {
		writeAPIError(w, http.StatusBadRequest, "field_too_long", "the template key is longer than allowed")
		return
	}
	if !templateKeyPattern.MatchString(req.TemplateKey) {
		writeAPIError(w, http.StatusBadRequest, "invalid_key",
			"a template key may contain only latin letters, digits, dots and underscores")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// for a readable 409 rather than a unique-violation 500. the constraint is still the guarantee.
	taken, err := a.Queries.AdminTemplateKeyExists(ctx, req.TemplateKey)
	if err != nil {
		log.Printf("CRITICAL: template key check failed: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not add the product")
		return
	}
	if taken {
		writeAPIError(w, http.StatusConflict, "key_taken", "that template key is already used")
		return
	}

	row, err := a.Queries.AdminCreateTemplateItem(ctx, db.AdminCreateTemplateItemParams{
		ShopCategory: code,
		TemplateKey:  req.TemplateKey,
		Name:         req.Name,
		Category:     req.Category,
		Unit:         req.Unit,
		ImagePath:    pgtype.Text{String: req.ImagePath, Valid: req.ImagePath != ""},
	})
	if err != nil {
		log.Printf("CRITICAL: admin %d failed to add template item to %s: %v", adminID, code, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not add the product")
		return
	}

	if err := a.reloadTemplates(ctx); err != nil {
		log.Printf("CRITICAL: template reload after add failed: %v", err)
	}

	log.Printf("ADMIN %d added template item %q to %s", adminID, row.TemplateKey, code)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(adminTemplateItem{
		ID: row.ID, Key: row.TemplateKey, Name: row.Name,
		Category: row.Category, Unit: row.Unit, ImagePath: row.ImagePath.String,
	})
}

// latin only and no spaces: this is an identifier that ends up in urls and logs, not display text
var templateKeyPattern = regexp.MustCompile(`^[a-z0-9]+(?:[._][a-z0-9]+)*$`)

// PUT /api/admin/templates/items/{id} - name, category, unit and photo. **not the key**: changing
// it would silently destroy prices rather than rename anything (AdminUpdateTemplateItem).
func (a *Admin) UpdateTemplateItem(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	itemID, ok := adminPathID(w, r, "template item")
	if !ok {
		return
	}

	var req templateItemRequest
	if !decodeJSONBody(w, r, &req) {
		return
	}
	req, failure := req.clean()
	if failure != nil {
		failure.write(w)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	row, err := a.Queries.AdminUpdateTemplateItem(ctx, db.AdminUpdateTemplateItemParams{
		ID:        itemID,
		Name:      req.Name,
		Category:  req.Category,
		Unit:      req.Unit,
		ImagePath: pgtype.Text{String: req.ImagePath, Valid: req.ImagePath != ""},
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "item_not_found", "no template item with that id")
			return
		}
		log.Printf("CRITICAL: admin %d failed to update template item %d: %v", adminID, itemID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not save the product")
		return
	}

	if err := a.reloadTemplates(ctx); err != nil {
		log.Printf("CRITICAL: template reload after update failed: %v", err)
	}

	log.Printf("ADMIN %d edited template item %q", adminID, row.TemplateKey)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(adminTemplateItem{
		ID: row.ID, Key: row.TemplateKey, Name: row.Name,
		Category: row.Category, Unit: row.Unit, ImagePath: row.ImagePath.String,
	})
}

// DELETE /api/admin/templates/items/{id} - the template only. every existing shop keeps its copy,
// and its price, until somebody presses sync.
func (a *Admin) DeleteTemplateItem(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	itemID, ok := adminPathID(w, r, "template item")
	if !ok {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	row, err := a.Queries.AdminDeleteTemplateItem(ctx, itemID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "item_not_found", "no template item with that id")
			return
		}
		log.Printf("CRITICAL: admin %d failed to delete template item %d: %v", adminID, itemID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not remove the product")
		return
	}

	if err := a.reloadTemplates(ctx); err != nil {
		log.Printf("CRITICAL: template reload after delete failed: %v", err)
	}

	log.Printf("ADMIN %d removed template item %q from %s", adminID, row.TemplateKey, row.ShopCategory)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"deleted": true, "template_key": row.TemplateKey})
}

// dispatches /api/admin/templates/{category}/items by method.
func (a *Admin) RouteTemplateItems(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.ListTemplateItems(w, r)
	case http.MethodPost:
		a.CreateTemplateItem(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (a *Admin) RouteTemplateItem(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPut:
		a.UpdateTemplateItem(w, r)
	case http.MethodDelete:
		a.DeleteTemplateItem(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// ─────────────────────────── orphaned photo files ───────────────────────────

// Files with no product behind them, and the button that clears them. They come from a deleted shop
// - the schema cascades, the products go, and the uploaded files are not in Postgres to go with them.
//
// **Three rules, and each is a way this could eat a live photo:**
//
//  1. **files are listed first, the database second.** In that order a row committed between the two
//     reads is seen, so its file is protected. Reversed, the sweep would delete a live photo.
//  2. **nothing younger than [orphanMinAge] is touched**, because the window between "the file
//     exists" and "the row exists" is one upload request.
//  3. **a referenced master claims its thumbnail.** Only the master's path is in the database, so a
//     literal path match would find every `_thumb` unreferenced and delete the whole market's grid.
//
// And a property rather than a rule: imagestore only lists and deletes under uploads/, so the
// curated catalogue is unreachable from here even by a bug in this file.
const (
	orphanMinAge = time.Hour

	// **how long one press may spend deleting, and it is a deadline rather than a count.** each
	// deletion on R2 is a network round trip of unpredictable length, so a count alone cannot bound
	// the wall clock - and nginx cuts a proxied request off at 60s, which would leave the panel
	// showing a network error on a sweep that was working. a large backlog takes several presses
	// instead, and the response says how many are left so the panel can say so too.
	orphanSweepBudget = 30 * time.Second

	// a ceiling underneath the deadline, so a local disk store (where deletions are instant) does
	// not turn one press into an unbounded loop either.
	orphanSweepLimit = 2000
)

// one shape for both the scan ("what would happen") and the sweep ("what happened"), so a reader
// comparing them does not have to translate between two vocabularies.
type orphanReport struct {
	// unreferenced and old enough: what GET would remove, what DELETE did remove
	Files int64 `json:"files"`
	Bytes int64 `json:"bytes"`

	// everything under uploads/, so the number above reads as a proportion
	TotalFiles int64 `json:"total_files"`
	TotalBytes int64 `json:"total_bytes"`

	// held back by rule 2 - shown because otherwise "12 files, 0 deleted" looks like a broken button
	TooRecent int64 `json:"too_recent"`

	// left when the deadline or the cap stopped the sweep early, on a DELETE
	Remaining int64 `json:"remaining"`

	// deletions that failed, on a DELETE - logged in full, counted here
	Failed int64 `json:"failed"`
}

// GET  /api/admin/storage/orphans - count and measure, change nothing
// DELETE /api/admin/storage/orphans - do it
//
// **the DELETE re-runs the whole scan rather than taking a list of paths from the browser**: a
// client-supplied list would name files to delete with a live photo one typo away.
func (a *Admin) RouteOrphans(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.ScanOrphans(w, r)
	case http.MethodDelete:
		a.SweepOrphans(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (a *Admin) ScanOrphans(w http.ResponseWriter, r *http.Request) {
	_, report, ok := a.findOrphans(w, r)
	if !ok {
		return
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(report)
}

func (a *Admin) SweepOrphans(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	orphans, report, ok := a.findOrphans(w, r)
	if !ok {
		return
	}
	if int64(len(orphans)) > orphanSweepLimit {
		orphans = orphans[:orphanSweepLimit]
	}

	ctx, cancel := context.WithTimeout(r.Context(), orphanSweepBudget)
	defer cancel()

	var deleted, bytes int64
	for i, file := range orphans {
		// checked before each deletion rather than relied on inside it: a store that ignores the
		// context (the local disk one does) would otherwise run the whole list anyway
		if ctx.Err() != nil {
			report.Remaining = int64(len(orphans) - i)
			break
		}
		if err := a.Images.RemoveFile(ctx, file.Path); err != nil {
			// keep going: one unwritable file must not leave the other four hundred behind
			log.Printf("WARNING: could not sweep orphaned photo %q: %v", file.Path, err)
			report.Failed++
			continue
		}
		deleted++
		bytes += file.Size
	}
	report.Files, report.Bytes = deleted, bytes

	log.Printf("ADMIN %d swept %d orphaned photo files (%d bytes, %d failed, %d left)",
		adminID, deleted, bytes, report.Failed, report.Remaining)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(report)
}

// the scan both handlers run, enforcing the three rules at the top of this section
func (a *Admin) findOrphans(w http.ResponseWriter, r *http.Request) ([]imagestore.Object, orphanReport, bool) {
	var report orphanReport

	// ── RULE 1, first half: the files, before the database.
	files, err := a.Images.List(r.Context())
	if err != nil {
		log.Printf("CRITICAL: could not list stored photos: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not read the photo storage")
		return nil, report, false
	}

	// ── RULE 1, second half: the database, after the files. a row committed between these two reads
	// is visible to this query, so its file is protected.
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	paths, err := a.Queries.AdminUploadedImagePaths(ctx, imagestore.UploadDir+"/%")
	if err != nil {
		log.Printf("CRITICAL: could not read the referenced photo paths: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not read the product photos")
		return nil, report, false
	}

	// ── RULE 3: one row protects two files.
	claimed := make(map[string]struct{}, len(paths)*2)
	for _, rel := range paths {
		if !imagestore.IsUpload(rel) {
			continue // the LIKE already refused these; the cost of being wrong is somebody's photo
		}
		claimed[rel] = struct{}{}
		claimed[imagestore.ThumbPath(rel)] = struct{}{}
	}

	// ── RULE 2: old enough to be sure.
	cutoff := time.Now().Add(-orphanMinAge)

	orphans := make([]imagestore.Object, 0, 8)
	for _, file := range files {
		report.TotalFiles++
		report.TotalBytes += file.Size

		if _, referenced := claimed[file.Path]; referenced {
			continue
		}
		if !file.Modified.Before(cutoff) {
			report.TooRecent++
			continue
		}
		orphans = append(orphans, file)
		report.Files++
		report.Bytes += file.Size
	}
	return orphans, report, true
}
