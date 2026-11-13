package endpoints

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"path"
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
	"domix/backend/internal/geo"
	"domix/backend/internal/imagestore"
	"domix/backend/internal/sysstat"
	"domix/backend/internal/waybill"
)

// the admin panel's api: the dashboard's statistics, moderation, the template editor and the
// orphaned-photo sweep.
//
// **the whole privileged surface is deliberately in one file, middleware included**: it is the only
// place in the api where one caller acts on another user's data.
type Admin struct {
	// the pool, not just Queries, because the template sync is three statements that must land
	// together - see SyncTemplate
	Pool    *pgxpool.Pool
	Queries *db.Queries

	// shared with the app-facing endpoints, so the panel shows the same urls the phone does
	URLs imagestore.URLs

	// where uploaded photos live, for the orphan sweep at the bottom of this file
	Images *imagestore.Disk

	// «Система»: the readings sampled in memory, and the one figure that lives in postgres
	Sampler  *sysstat.Sampler
	GeoQuota *geo.DailyQuota
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

// what an owner's own photo looks like to SQL. the sync leaves such a path alone and the drift count
// agrees with it; built from imagestore.UploadDir so there is still one declaration of the prefix.
const uploadPathPattern = imagestore.UploadDir + "/%"

// RequireAdmin refuses anyone whose role is not `admin`. it must be composed *inside* auth.RequireAuth,
// which is what puts the caller's id on the context.
//
// **the role is read from the database on every request and never from the token**: a demoted admin
// stops administering immediately rather than when their four-month token expires.
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

// ─────────────────────────────── system ───────────────────────────────

type adminSystemResponse struct {
	SampledAt       string `json:"sampled_at"`
	StartedAt       string `json:"started_at"`
	IntervalSeconds int    `json:"interval_seconds"`
	HistorySeconds  int    `json:"history_seconds"`

	// null where the host cannot be read; cpu is also null for the first interval after a boot
	CPU    *adminSystemCPU    `json:"cpu"`
	Memory *adminSystemMemory `json:"memory"`
	Disk   *adminSystemDisk   `json:"disk"`
	Load   *adminSystemLoad   `json:"load"`
	Cores  int                `json:"cores"`

	Pool   adminSystemPool   `json:"pool"`
	Search adminSystemSearch `json:"search"`
	// null when postgres could not count it, so the rest of the screen still answers
	Geo     []adminSystemGeo   `json:"geo"`
	Runtime adminSystemRuntime `json:"runtime"`
}

type adminSystemCPU struct {
	Percent      float64   `json:"percent"`
	StealPercent float64   `json:"steal_percent"`
	History      []float64 `json:"history"`
}

type adminSystemMemory struct {
	Total     uint64 `json:"total"`
	Used      uint64 `json:"used"`
	SwapTotal uint64 `json:"swap_total"`
	SwapUsed  uint64 `json:"swap_used"`
}

type adminSystemDisk struct {
	Total uint64 `json:"total"`
	Free  uint64 `json:"free"`
}

type adminSystemLoad struct {
	One     float64 `json:"one"`
	Five    float64 `json:"five"`
	Fifteen float64 `json:"fifteen"`
}

type adminSystemPool struct {
	Acquired      int32   `json:"acquired"`
	Max           int32   `json:"max"`
	BusyWaits     int64   `json:"busy_waits"`
	FirstBusyWait *string `json:"first_busy_wait"`
	LastBusyWait  *string `json:"last_busy_wait"`
	EmptyAcquires int64   `json:"empty_acquires"`
}

type adminSystemSearch struct {
	InUse    int `json:"in_use"`
	Capacity int `json:"capacity"`
}

type adminSystemGeo struct {
	Product  string `json:"product"`
	ThisHour int32  `json:"this_hour"`
	LastDay  int32  `json:"last_day"`
	DailyCap int32  `json:"daily_cap"`
}

type adminSystemRuntime struct {
	Goroutines   int    `json:"goroutines"`
	HeapBytes    uint64 `json:"heap_bytes"`
	RuntimeBytes uint64 `json:"runtime_bytes"`
}

// System answers «Система»: how close this server is to its limits, polled every few seconds.
//
// **the geo count is the only database work here, and it must stay so**: everything else is the
// sampler's last reading out of memory, so the screen costs nothing to leave open.
func (a *Admin) System(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		writeAPIError(w, http.StatusMethodNotAllowed, "method_not_allowed", "use GET")
		return
	}

	snap := a.Sampler.Snapshot()
	response := adminSystemResponse{
		SampledAt:       snap.At.UTC().Format(time.RFC3339),
		StartedAt:       snap.StartedAt.UTC().Format(time.RFC3339),
		IntervalSeconds: int(sysstat.Interval / time.Second),
		HistorySeconds:  int(sysstat.History / time.Second),
		Cores:           snap.Cores,
		Pool: adminSystemPool{
			Acquired: snap.Pool.Acquired, Max: snap.Pool.Max, BusyWaits: snap.Pool.BusyWaits,
			FirstBusyWait: optionalTime(snap.Pool.FirstBusyWait), LastBusyWait: optionalTime(snap.Pool.LastBusyWait),
			EmptyAcquires: snap.Pool.EmptyAcquires,
		},
		Search: adminSystemSearch{InUse: snap.SearchInUse, Capacity: snap.SearchCapacity},
		Runtime: adminSystemRuntime{
			Goroutines: snap.Goroutines, HeapBytes: snap.HeapBytes, RuntimeBytes: snap.RuntimeBytes,
		},
	}
	if snap.CPU != nil {
		response.CPU = &adminSystemCPU{Percent: snap.CPU.Percent, StealPercent: snap.CPU.StealPercent, History: snap.CPUHistory}
	}
	if m := snap.Memory; m != nil {
		response.Memory = &adminSystemMemory{
			Total: m.Total, Used: m.Total - m.Available, SwapTotal: m.SwapTotal, SwapUsed: m.SwapTotal - m.SwapFree,
		}
	}
	if d := snap.Disk; d != nil {
		response.Disk = &adminSystemDisk{Total: d.Total, Free: d.Free}
	}
	if l := snap.Load; l != nil {
		response.Load = &adminSystemLoad{One: l.One, Five: l.Five, Fifteen: l.Fifteen}
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()
	if usage, err := a.GeoQuota.Usage(ctx); err != nil {
		log.Printf("WARNING: admin system: could not count geo calls: %v", err)
	} else {
		response.Geo = make([]adminSystemGeo, 0, len(usage))
		for _, u := range usage {
			response.Geo = append(response.Geo, adminSystemGeo{
				Product: u.Product, ThisHour: u.ThisHour, LastDay: u.LastDay, DailyCap: u.DailyCap,
			})
		}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// a moment that has not happened yet is null, not 0001-01-01
func optionalTime(t time.Time) *string {
	if t.IsZero() {
		return nil
	}
	s := t.UTC().Format(time.RFC3339)
	return &s
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

// DELETE /api/admin/users/{id} - the same cascade DELETE /api/me runs: the shops go, and each takes its
// products. a hard delete, because a row nobody can reach is still a phone number somebody asked to have
// erased. the only account it refuses is the last admin, the one state with no way back.
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

	// read before the cascade takes the rows that name them - see eraseAccount
	uploads, err := a.Queries.ListUploadedImagesOfUser(ctx, targetID)
	if err != nil {
		log.Printf("CRITICAL: admin %d could not list the photos of user %d: %v", adminID, targetID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the user")
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
	removeUploads(ctx, a.Images, targetID, uploads)

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

	// **the editor sends these back on every save**, so the panel must be given the shop's own
	// point. Without them the map in the editor had nothing to draw and `UpdateShop` was handed
	// whatever the form had defaulted to.
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`

	IsVIP    bool   `json:"is_vip"`
	VipUntil string `json:"vip_until,omitempty"`
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

	// the storefront a VIP card draws. empty is the whole of "no photo yet", which is what the
	// placement row nags about - the panel never builds a thumbnail url of its own.
	ImageURL      string `json:"image_url,omitempty"`
	ImageThumbURL string `json:"image_thumb_url,omitempty"`

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
			Latitude:          row.Latitude,
			Longitude:         row.Longitude,
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
		if row.ImagePath.Valid && row.ImagePath.String != "" {
			shop.ImageURL = a.URLs.Master(row.ImagePath.String)
			shop.ImageThumbURL = a.URLs.Thumb(row.ImagePath.String)
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
// **`admin` is in this set, so a stolen admin token is a permanent compromise** rather than one that ends
// when the token expires - the known cost of the power. **nothing unauthenticated can assign it, and that
// must not change**: the login maps anything that is not shop_owner to customer.
var assignableRoles = map[string]bool{"customer": true, "shop_owner": true, "admin": true}

// anotherAdminRemains is what stops the panel destroying its own access. **409 rather than 403**: the
// panel signs itself out on a 403, and this is a request that was understood, allowed and impossible
// right now. the count and the write are not one transaction, which at one machine is no race worth a lock.
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

// PUT /api/admin/shops/{id}/vip - grant or revoke a paid placement. logged like a deletion, because it is
// a commercial decision somebody will ask the date of. `days` rather than an absolute date, since the
// panel's realistic input is "sold them a month"; zero or missing revokes.
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
		// **the grant is not refused for a missing photo, it reports one.** a placement is sold
		// before anybody has the picture to hand, and a card with an empty frame is a worse thing to
		// discover on the home screen than a nag in the panel - so the panel asks for it here.
		"needs_photo": updated.IsVip && strings.TrimSpace(updated.ImagePath.String) == "",
	})
}

// ─────────────────────────── the storefront photograph ───────────────────────────

// POST /api/admin/shops/{id}/photo stores the picture a VIP card shows; DELETE takes it off.
//
// **the panel uploads it, never the owner**: this section of the home screen is the one that is sold. the
// bytes take the same decode as every other upload and land under shops/uploads/, which is what puts a
// storefront behind the same deletion door and the same orphan sweep as a product photo.
func (a *Admin) RouteShopPhoto(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		a.UploadShopPhoto(w, r)
	case http.MethodDelete:
		a.RemoveShopPhoto(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// **the ordering is the project's**: write the new file, point the row at it, unlink the old one.
// any other order can leave a shop naming a file that is gone.
func (a *Admin) UploadShopPhoto(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	shopID, ok := adminPathID(w, r, "shop")
	if !ok {
		return
	}

	existing, ok := a.readShopPhoto(w, r, shopID)
	if !ok {
		return
	}

	raw, ok := readUploadedImage(w, r)
	if !ok {
		return
	}

	normalized, err := imagestore.Normalize(raw)
	if err != nil {
		writeImageError(w, err)
		return
	}

	stored, err := a.Images.Save(r.Context(), normalized)
	if err != nil {
		log.Printf("CRITICAL: admin %d could not store the photo of shop %d: %v", adminID, shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to save the photo")
		return
	}

	updated, ok := a.pointShopAt(w, r, shopID, pgtype.Text{String: stored, Valid: true})
	if !ok {
		// the row still names the old photo, so this one is referenced by nothing
		if err := a.Images.Remove(r.Context(), stored); err != nil {
			log.Printf("WARNING: orphaned shop photo %q could not be removed: %v", stored, err)
		}
		return
	}

	a.forgetShopPhoto(r, existing.ImagePath)
	log.Printf("ADMIN %d set the photo of shop %d to %q", adminID, shopID, stored)
	a.writeShopPhotoResponse(w, updated)
}

func (a *Admin) RemoveShopPhoto(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	shopID, ok := adminPathID(w, r, "shop")
	if !ok {
		return
	}

	existing, ok := a.readShopPhoto(w, r, shopID)
	if !ok {
		return
	}

	updated, ok := a.pointShopAt(w, r, shopID, pgtype.Text{})
	if !ok {
		return
	}

	a.forgetShopPhoto(r, existing.ImagePath)
	log.Printf("ADMIN %d removed the photo of shop %d", adminID, shopID)
	a.writeShopPhotoResponse(w, updated)
}

// the row as it stands, which is both the 404 and the path to unlink afterwards
func (a *Admin) readShopPhoto(w http.ResponseWriter, r *http.Request, shopID int64) (db.GetShopPhotoRow, bool) {
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	existing, err := a.Queries.GetShopPhoto(ctx, shopID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "shop_not_found", "no shop with that id")
			return db.GetShopPhotoRow{}, false
		}
		log.Printf("CRITICAL: could not read shop %d before a photo change: %v", shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the shop")
		return db.GetShopPhotoRow{}, false
	}
	return existing, true
}

func (a *Admin) pointShopAt(w http.ResponseWriter, r *http.Request, shopID int64, rel pgtype.Text) (db.SetShopImageRow, bool) {
	// a fresh timeout: readShopPhoto's cancel() already fired when it returned
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	updated, err := a.Queries.SetShopImage(ctx, db.SetShopImageParams{ID: shopID, ImagePath: rel})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "shop_not_found", "no shop with that id")
			return db.SetShopImageRow{}, false
		}
		log.Printf("CRITICAL: could not set the photo of shop %d: %v", shopID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to save the photo")
		return db.SetShopImageRow{}, false
	}
	return updated, true
}

// unlink what the row used to name. IsUpload is the guard every deletion here goes through, even
// though only this endpoint ever writes the column: a curated path put there by hand must not take
// a file every shop of its category draws.
func (a *Admin) forgetShopPhoto(r *http.Request, previous pgtype.Text) {
	if !previous.Valid || !imagestore.IsUpload(previous.String) {
		return
	}
	if err := a.Images.Remove(r.Context(), previous.String); err != nil {
		log.Printf("WARNING: could not remove the replaced shop photo %q: %v", previous.String, err)
	}
}

func (a *Admin) writeShopPhotoResponse(w http.ResponseWriter, row db.SetShopImageRow) {
	out := ShopResponse{ID: row.ID, Name: row.Name}
	out.setPhoto(a.URLs, row.ImagePath)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"id":              out.ID,
		"image_path":      row.ImagePath.String,
		"image_url":       out.ImageURL,
		"image_thumb_url": out.ImageThumbURL,
	})
}

// PUT /api/admin/shops/{id}/exclude - pull a shop out of its market's comparison, or put it back.
//
// separate from catalogue completeness on purpose: shop_basket_index answers "is every product priced",
// where this is an admin's own decision and has to win even when every price is filled in.
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
		products = append(products, productResponse(a.URLs, db.GetProductRow(row)))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"products": products})
}

// PUT /api/admin/products/{id}
//
// **an admin gets the same three-way rule the owner gets, not a bypass of it.** the rule is data
// integrity rather than permissions: a renamed template row stops being the same product as its
// counterpart down the road. what an admin needs here is the price, editable on every row.
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

	// every statement in products.sql returns the same columns, so each row type converts to this one
	// and the response is built once at the bottom
	var updated db.GetProductRow

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
		updated = db.GetProductRow(row)

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
		updated = db.GetProductRow(row)

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
		updated = db.GetProductRow(row)
	}

	if err != nil {
		log.Printf("CRITICAL: admin %d failed to update product %d: %v", adminID, productID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not update the product")
		return
	}

	log.Printf("ADMIN %d updated product %d (shop %d)", adminID, productID, updated.ShopID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(productResponse(a.URLs, updated))
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

	// the 400px copy, so the panel can show the photo instead of a path - which is how a founder
	// checks that five sizes really do share the right picture. built here because only the server
	// knows whether photos come from this api or from whatever host IMAGE_BASE_URL names.
	ImageThumbURL string `json:"image_thumb_url,omitempty"`

	// whether the price comparison totals this row. a product added to a template starts outside the
	// basket, so extending the catalogue never drops a live market out of the comparison.
	InBasket bool `json:"in_basket"`

	Specs   string `json:"specs"`
	Section string `json:"section"`

	// how many shops of this market hold this row, and how many have typed a price for it. **this is
	// the number the in_basket decision is made from**: voting a row in before most shops have priced
	// it takes the rest out of the comparison.
	Shops  int64 `json:"shops"`
	Priced int64 `json:"priced"`
}

// one row as the database returns it, plus the coverage counted separately
func (a *Admin) templateItemFrom(row db.AdminListTemplateItemsRow, priced, present int64) adminTemplateItem {
	item := adminTemplateItem{
		ID: row.ID, Key: row.TemplateKey, Name: row.Name,
		Category: row.Category, Unit: row.Unit, ImagePath: row.ImagePath.String,
		InBasket: row.InBasket, Specs: row.Specs, Section: row.Section,
		Shops: present, Priced: priced,
	}
	if item.ImagePath != "" {
		item.ImageThumbURL = a.URLs.Thumb(item.ImagePath)
	}
	return item
}

type adminTemplateCategory struct {
	Category    string              `json:"category"`
	Size        int                 `json:"size"`
	BasketSize  int                 `json:"basket_size"`
	OwnerNamed  bool                `json:"owner_named"`
	Items       []adminTemplateItem `json:"items"`
	Shops       int64               `json:"shops"`
	MissingRows int64               `json:"missing_rows"`
	StaleRows   int64               `json:"stale_rows"`
	// shop rows whose copy differs from the template - what the sync's update would rewrite
	ChangedRows int64 `json:"changed_rows"`
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

		// one query per category rather than one per row: the panel draws 100 rows and this is the
		// number each of them needs
		coverage, err := a.Queries.AdminTemplateCoverage(ctx, code)
		if err != nil {
			log.Printf("CRITICAL: template coverage for %s failed: %v", code, err)
			writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load templates")
			return
		}
		priced := make(map[string]int64, len(coverage))
		present := make(map[string]int64, len(coverage))
		for _, row := range coverage {
			priced[row.TemplateKey.String] = row.Priced
			present[row.TemplateKey.String] = row.Present
		}

		keys := make([]string, 0, len(stored))
		wire := make([]adminTemplateItem, 0, len(stored))
		basketSize := 0
		for _, item := range stored {
			keys = append(keys, item.TemplateKey)
			if item.InBasket {
				basketSize++
			}
			wire = append(wire, a.templateItemFrom(item, priced[item.TemplateKey], present[item.TemplateKey]))
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

		changed, err := a.Queries.AdminTemplateChangedRows(ctx, db.AdminTemplateChangedRowsParams{
			Category: code,
			// the same switch SyncTemplate passes: an обои name is the owner's, so it never counts
			Column2: !catalog.IsOwnerNamedCategory(code),
			// and the same guard: a shop drawing its own upload is not behind the template
			Column3: uploadPathPattern,
		})
		if err != nil {
			log.Printf("CRITICAL: template drift for %s failed: %v", code, err)
			writeAPIError(w, http.StatusInternalServerError, "server_error", "could not read template status")
			return
		}

		out = append(out, adminTemplateCategory{
			Category:    code,
			ChangedRows: changed,
			Size:        len(stored),
			BasketSize:  basketSize,
			OwnerNamed:  catalog.IsOwnerNamedCategory(code),
			Items:       wire,
			Shops:       status.Shops,
			// what every shop of this category should hold minus what they do: a shop created before a
			// product was added to the template is missing that row and nothing tells it
			MissingRows: status.Shops*int64(len(stored)) - status.PresentRows,
			StaleRows:   status.StaleRows,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"templates": out})
}

// POST /api/admin/templates/{category}/sync - push the current template into every existing shop of that
// category. seeding happens once at creation, so without this a template edit reaches nobody.
//
//	insert  - rows the template has and the shop does not, unpriced
//	update  - names/units/categories/photos for rows both have, prices untouched
//	delete  - rows the shop has and the template no longer does
//
// **a shop's own uploaded photo survives the update** - the half of the обои rule that lives in SQL.
//
// **the transaction is not decoration**: a shop left with the new rows inserted but the stale ones still
// there holds two versions of its own basket, and the index would total both.
//
// **it drops every shop of the category out of the comparison** until each owner prices the new row, and
// deleting a row takes whatever price the owner had typed, with no undo.
func (a *Admin) SyncTemplate(w http.ResponseWriter, r *http.Request) {
	// both write, so a GET must not reach them - a prefetching browser would otherwise run a sync
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
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
			InBasket:    item.InBasket,
			Specs:       item.Specs,
			Section:     item.Section,
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
		Category: code, Column2: payload, Column3: syncNames, Column4: uploadPathPattern,
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
// the field names are what jsonb_to_recordset reads in AdminSyncTemplateInsert/Update - **one jsonb
// array rather than parallel text[]s, which could get out of step**
type adminTemplateSyncRow struct {
	TemplateKey string `json:"template_key"`
	Name        string `json:"name"`
	Category    string `json:"category"`
	Unit        string `json:"unit"`
	ImagePath   string `json:"image_path"`
	InBasket    bool   `json:"in_basket"`
	Specs       string `json:"specs"`
	Section     string `json:"section"`
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
			InBasket:     row.InBasket,
			Specs:        row.Specs,
			Section:      row.Section,
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
	InBasket     bool   `json:"in_basket"`
	Specs        string `json:"specs"`
	Section      string `json:"section"`
}

// the column widths of `products`, which these are copied into at seeding: a row that fits
// product_templates but not products would fail at shop creation
const (
	maxTemplateKeyLen  = 60
	maxTemplateNameLen = 150
	maxTemplateUnitLen = 20
	maxSpecsLen        = 80
)

// `shopCategory` is which template the row belongs to, which is what makes a photo path judgeable:
// a path is only valid inside that category's own catalogue folder.
func (req templateItemRequest) clean(shopCategory string) (templateItemRequest, *accessError) {
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

	req.Specs = strings.TrimSpace(req.Specs)
	req.Section = strings.TrimSpace(req.Section)
	if utf8.RuneCountInString(req.Specs) > maxSpecsLen {
		return req, &accessError{http.StatusBadRequest, "field_too_long", "a field is longer than allowed"}
	}
	if req.Section != "" && !catalog.IsValidSection(req.Section) {
		return req, &accessError{http.StatusBadRequest, "invalid_section", "unknown section"}
	}
	if failure := checkTemplatePhoto(shopCategory, req.ImagePath); failure != nil {
		return req, failure
	}
	return req, nil
}

// reloadTemplates re-reads product_templates into internal/catalog's in-memory copy.
//
// **every handler that writes that table must call this before responding**: seeding, IsOwnerNamedSlot
// and the sync payload all read from memory, so a write that skips it leaves the process serving the old
// list until it restarts.
func checkTemplatePhoto(shopCategory, imagePath string) *accessError {
	if imagePath == "" {
		return nil
	}
	if catalog.IsOwnerNamedCategory(shopCategory) {
		return &accessError{http.StatusBadRequest, "owner_named_photo",
			"the photo of a slot belongs to the shop owner, so its template row cannot carry one"}
	}
	if !imagestore.IsCatalogue(imagePath) {
		return &accessError{http.StatusBadRequest, "invalid_image_path",
			"a photo must be a file of the shared catalogue"}
	}
	if path.Base(path.Dir(imagePath)) != shopCategory {
		return &accessError{http.StatusBadRequest, "invalid_image_path",
			"that photo belongs to another category's catalogue"}
	}
	return nil
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
		items = append(items, a.templateItemFrom(row, 0, 0))
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
	req, failure := req.clean(code)
	if failure != nil {
		failure.write(w)
		return
	}

	if failure := checkTemplateKey(req.TemplateKey); failure != nil {
		failure.write(w)
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
		InBasket:     req.InBasket,
		Specs:        req.Specs,
		Section:      req.Section,
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
	json.NewEncoder(w).Encode(a.templateItemFrom(db.AdminListTemplateItemsRow(row), 0, 0))
}

// latin only and no spaces: this is an identifier that ends up in urls and logs, not display text
var templateKeyPattern = regexp.MustCompile(`^[a-z0-9]+(?:[._][a-z0-9]+)*$`)

// a new key's three rules, shared by the one-row form and the import
func checkTemplateKey(key string) *accessError {
	switch {
	case key == "":
		return &accessError{http.StatusBadRequest, "missing_key", "a template key is required"}
	case utf8.RuneCountInString(key) > maxTemplateKeyLen:
		return &accessError{http.StatusBadRequest, "field_too_long", "the template key is longer than allowed"}
	case !templateKeyPattern.MatchString(key):
		return &accessError{http.StatusBadRequest, "invalid_key",
			"a template key may contain only latin letters, digits, dots and underscores"}
	}
	return nil
}

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

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// read before clean: which category the row belongs to is what decides whether its photo path
	// is a valid one, and the url carries only the id
	stored, err := a.Queries.AdminGetTemplateItem(ctx, itemID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "item_not_found", "no template item with that id")
			return
		}
		log.Printf("CRITICAL: could not read template item %d: %v", itemID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not save the product")
		return
	}

	req, failure := req.clean(stored.ShopCategory)
	if failure != nil {
		failure.write(w)
		return
	}

	row, err := a.Queries.AdminUpdateTemplateItem(ctx, db.AdminUpdateTemplateItemParams{
		ID:        itemID,
		Name:      req.Name,
		Category:  req.Category,
		Unit:      req.Unit,
		ImagePath: pgtype.Text{String: req.ImagePath, Valid: req.ImagePath != ""},
		InBasket:  req.InBasket,
		Specs:     req.Specs,
		Section:   req.Section,
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
	json.NewEncoder(w).Encode(a.templateItemFrom(db.AdminListTemplateItemsRow(row), 0, 0))
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

// a category template is ~100 rows; this is a ceiling against a paste of the wrong sheet, not a page
const maxTemplateImportRows = 500

type templateImportRequest struct {
	Rows  []templateItemRequest `json:"rows"`
	Apply bool                  `json:"apply"`
}

// one line of the difference. Fields names what an update changes, so "изменится 3" can be checked
// against the sheet before anything is written.
type templateImportChange struct {
	Key    string   `json:"key"`
	Name   string   `json:"name"`
	Fields []string `json:"fields,omitempty"`
}

type templateImportResult struct {
	Create  []templateImportChange `json:"create"`
	Update  []templateImportChange `json:"update"`
	Delete  []templateImportChange `json:"delete"`
	Applied bool                   `json:"applied"`
}

// **a photo path is a file of this category's own catalogue folder, or it is refused**: a path that names
// nothing is a blank tile in every shop of a market, with nothing anywhere saying why.
//
// **a category whose names the owner writes carries no photo at all.** the right to photograph a row is
// granted by the template not having one (templateFlags), so a picture put on an обои slot from here
// takes that right from every обои shop and the next sync overwrites each of their own photographs.
func (a *Admin) ImportTemplate(w http.ResponseWriter, r *http.Request) {
	// both write, so a GET must not reach them - a prefetching browser would otherwise run a sync
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	adminID, _ := auth.UserIDFromContext(r.Context())

	code := r.PathValue("category")
	if !catalog.IsValidCategory(code) {
		writeAPIError(w, http.StatusBadRequest, "invalid_category", "unknown shop category")
		return
	}

	var req templateImportRequest
	if !decodeJSONBody(w, r, &req) {
		return
	}
	if len(req.Rows) == 0 || len(req.Rows) > maxTemplateImportRows {
		writeAPIError(w, http.StatusBadRequest, "invalid_import",
			fmt.Sprintf("an import holds between 1 and %d rows", maxTemplateImportRows))
		return
	}

	rows := make([]templateItemRequest, 0, len(req.Rows))
	seen := make(map[string]bool, len(req.Rows))
	for i, raw := range req.Rows {
		row, failure := raw.clean(code)
		if failure == nil {
			failure = checkTemplateKey(row.TemplateKey)
		}
		if failure != nil {
			// the row number is the sheet's, so the founder can find the line that is wrong
			failure.message = fmt.Sprintf("row %d: %s", i+1, failure.message)
			failure.write(w)
			return
		}
		if seen[row.TemplateKey] {
			writeAPIError(w, http.StatusBadRequest, "duplicate_key",
				fmt.Sprintf("row %d: the key %q appears twice", i+1, row.TemplateKey))
			return
		}
		seen[row.TemplateKey] = true
		rows = append(rows, row)
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	tx, err := a.Pool.Begin(ctx)
	if err != nil {
		log.Printf("CRITICAL: admin %d could not begin a template import: %v", adminID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not start the import")
		return
	}
	defer tx.Rollback(ctx) // the dry run never commits, so it can share the code path exactly

	q := db.New(tx)
	result, existing, failure := diffTemplate(ctx, q, code, rows)
	if failure != nil {
		failure.write(w)
		return
	}

	if req.Apply {
		if failure := applyTemplateImport(ctx, q, code, rows, existing); failure != nil {
			failure.write(w)
			return
		}
		if err := tx.Commit(ctx); err != nil {
			log.Printf("CRITICAL: template import commit for %s failed: %v", code, err)
			writeAPIError(w, http.StatusInternalServerError, "server_error", "could not save the import")
			return
		}
		if err := a.reloadTemplates(ctx); err != nil {
			log.Printf("CRITICAL: template reload after import failed: %v", err)
		}
		result.Applied = true
		log.Printf("ADMIN %d imported the %s template: %d added, %d changed, %d removed",
			adminID, code, len(result.Create), len(result.Update), len(result.Delete))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(result)
}

// what the paste would do to the stored template, plus the stored rows by key for the writer
func diffTemplate(ctx context.Context, q *db.Queries, code string, rows []templateItemRequest) (templateImportResult, map[string]db.AdminListTemplateItemsRow, *accessError) {
	result := templateImportResult{
		Create: []templateImportChange{}, Update: []templateImportChange{}, Delete: []templateImportChange{},
	}

	stored, err := q.AdminListTemplateItems(ctx, code)
	if err != nil {
		log.Printf("CRITICAL: template items for %s failed during import: %v", code, err)
		return result, nil, &accessError{http.StatusInternalServerError, "server_error", "could not read the template"}
	}
	existing := make(map[string]db.AdminListTemplateItemsRow, len(stored))
	for _, row := range stored {
		existing[row.TemplateKey] = row
	}

	pasted := make(map[string]bool, len(rows))
	for _, row := range rows {
		pasted[row.TemplateKey] = true
		old, ok := existing[row.TemplateKey]
		if !ok {
			// keys are unique across every category, so a "new" key may still belong to another one -
			// refused, or the insert would fail on the constraint halfway through the transaction
			taken, err := q.AdminTemplateKeyExists(ctx, row.TemplateKey)
			if err != nil {
				log.Printf("CRITICAL: template key check failed during import: %v", err)
				return result, nil, &accessError{http.StatusInternalServerError, "server_error", "could not check the keys"}
			}
			if taken {
				return result, nil, &accessError{http.StatusConflict, "key_taken",
					fmt.Sprintf("the key %q already belongs to another category", row.TemplateKey)}
			}
			result.Create = append(result.Create, templateImportChange{Key: row.TemplateKey, Name: row.Name})
			continue
		}
		if fields := changedTemplateFields(old, row); len(fields) > 0 {
			result.Update = append(result.Update, templateImportChange{Key: row.TemplateKey, Name: row.Name, Fields: fields})
		}
	}

	// in stored order, so the list reads the way the template does
	for _, row := range stored {
		if !pasted[row.TemplateKey] {
			result.Delete = append(result.Delete, templateImportChange{Key: row.TemplateKey, Name: row.Name})
		}
	}
	return result, existing, nil
}

// the column names that differ, in the panel's own vocabulary
func changedTemplateFields(old db.AdminListTemplateItemsRow, row templateItemRequest) []string {
	var fields []string
	if old.Name != row.Name {
		fields = append(fields, "name")
	}
	if old.Category != row.Category {
		fields = append(fields, "category")
	}
	if old.Unit != row.Unit {
		fields = append(fields, "unit")
	}
	if old.ImagePath.String != row.ImagePath {
		fields = append(fields, "image_path")
	}
	if old.InBasket != row.InBasket {
		fields = append(fields, "in_basket")
	}
	if old.Specs != row.Specs {
		fields = append(fields, "specs")
	}
	if old.Section != row.Section {
		fields = append(fields, "section")
	}
	return fields
}

// writes the difference diffTemplate found, inside the caller's transaction
func applyTemplateImport(ctx context.Context, q *db.Queries, code string, rows []templateItemRequest, existing map[string]db.AdminListTemplateItemsRow) *accessError {
	pasted := make(map[string]bool, len(rows))
	for _, row := range rows {
		pasted[row.TemplateKey] = true
		old, ok := existing[row.TemplateKey]
		var err error
		switch {
		case !ok:
			_, err = q.AdminCreateTemplateItem(ctx, db.AdminCreateTemplateItemParams{
				ShopCategory: code,
				TemplateKey:  row.TemplateKey,
				Name:         row.Name,
				Category:     row.Category,
				Unit:         row.Unit,
				ImagePath:    pgtype.Text{String: row.ImagePath, Valid: row.ImagePath != ""},
				InBasket:     row.InBasket,
				Specs:        row.Specs,
				Section:      row.Section,
			})
		case len(changedTemplateFields(old, row)) > 0:
			_, err = q.AdminUpdateTemplateItem(ctx, db.AdminUpdateTemplateItemParams{
				ID:        old.ID,
				Name:      row.Name,
				Category:  row.Category,
				Unit:      row.Unit,
				ImagePath: pgtype.Text{String: row.ImagePath, Valid: row.ImagePath != ""},
				InBasket:  row.InBasket,
				Specs:     row.Specs,
				Section:   row.Section,
			})
		}
		if err != nil {
			log.Printf("CRITICAL: template import write for %q failed: %v", row.TemplateKey, err)
			return &accessError{http.StatusInternalServerError, "server_error", "could not save the import"}
		}
	}

	for key, old := range existing {
		if pasted[key] {
			continue
		}
		if _, err := q.AdminDeleteTemplateItem(ctx, old.ID); err != nil {
			log.Printf("CRITICAL: template import delete of %q failed: %v", key, err)
			return &accessError{http.StatusInternalServerError, "server_error", "could not save the import"}
		}
	}
	return nil
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

// ─────────────────────────── adding a photo to the catalogue ───────────────────────────

// POST /api/admin/templates/{category}/import - a category's whole template, pasted from a sheet.
// `apply: false` answers with the difference and writes nothing.
//
// **the list is the whole template, so a row missing from it is a row to delete** - which is why the
// panel always shows the difference first. like every template edit it touches no shop; the sync stays
// the second, louder step. new rows join at the end, existing rows keep their place.
func (a *Admin) UploadCataloguePhoto(w http.ResponseWriter, r *http.Request) {
	// a prefetching browser must not write a file
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	adminID, _ := auth.UserIDFromContext(r.Context())

	code := r.PathValue("category")
	if !catalog.IsValidCategory(code) {
		writeAPIError(w, http.StatusBadRequest, "invalid_category", "unknown shop category")
		return
	}
	// refused before a byte is read rather than only by checkTemplatePhoto afterwards: there is no
	// row that could ever name this file, so writing it would only feed the sweep
	if catalog.IsOwnerNamedCategory(code) {
		writeAPIError(w, http.StatusBadRequest, "owner_named_photo",
			"photos in this category belong to the shop owners")
		return
	}

	raw, ok := readUploadedImage(w, r)
	if !ok {
		return
	}

	normalized, err := imagestore.Normalize(raw)
	if err != nil {
		writeImageError(w, err)
		return
	}

	stored, err := a.Images.SaveCatalogue(r.Context(), code, normalized)
	if err != nil {
		log.Printf("CRITICAL: admin %d could not store a %s catalogue photo: %v", adminID, code, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to save the photo")
		return
	}

	log.Printf("ADMIN %d added the catalogue photo %q", adminID, stored)

	w.WriteHeader(http.StatusOK)
	// the path is what a row stores; the urls are what the editor shows, built here because only the
	// server knows whether photos come from this api or from whatever host IMAGE_BASE_URL names
	json.NewEncoder(w).Encode(catalogueFile{
		Path: stored, ThumbURL: a.URLs.Thumb(stored), Used: false,
		Size: int64(len(normalized.Master)),
	})
}

// ─────────────────────────── orphaned photo files ───────────────────────────

// Files with no product behind them, and the button that clears them. They come from a deleted shop: the
// schema cascades, the products go, and the uploaded files are not in Postgres to go with them.
//
// **Three rules, and each is a way this could eat a live photo:**
//
//  1. **files are listed first, the database second**, so a row committed between the two reads is seen
//     and its file protected. Reversed, the sweep deletes a photo a product points at.
//  2. **nothing younger than [orphanMinAge] is touched**: the window between "the file exists" and "the
//     row exists" is one upload request.
//  3. **a referenced master claims its thumbnail.** Only the master's path is in the database, so a
//     literal path match would find every `_thumb` unreferenced and delete the whole market's grid.
//
// imagestore only lists and deletes under uploads/, so the curated catalogue is unreachable from here.
const (
	orphanMinAge = time.Hour

	// **how long one press may spend deleting, and it is a deadline rather than a count**: nginx cuts a
	// proxied request off at 60s, and the scan before this is a walk of the whole store. a large backlog
	// takes several presses, and the response says how many are left.
	orphanSweepBudget = 30 * time.Second

	// a ceiling underneath the deadline: deletions on disk are instant, so without it one press would
	// last as long as the backlog.
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

	// what a GET found, so the panel can show the names before anything is pressed. absent on a
	// DELETE, whose answer is a count of what went.
	Paths []string `json:"paths,omitempty"`

	// every catalogue master and whether a row points at it - the photo picker's whole source
	Catalogue []catalogueFile `json:"catalogue,omitempty"`
}

// one curated photo as the picker sees it, and the answer UploadCataloguePhoto gives - the same
// shape, so a freshly uploaded file joins the picker's list without being translated. thumbnails are
// left out: they are not paths any row stores.
type catalogueFile struct {
	Path     string `json:"path"`
	ThumbURL string `json:"thumb_url"`
	Used     bool   `json:"used"`
	Size     int64  `json:"size"`
}

// "shops/universal/001_thumb.jpg" -> "shops/universal/001.jpg". a thumbnail is not a path any row
// stores, so a scope test has to be applied to the master it belongs to.
func masterPath(rel string) string {
	ext := path.Ext(rel)
	stem := strings.TrimSuffix(rel, ext)
	if !strings.HasSuffix(stem, "_thumb") {
		return rel
	}
	return strings.TrimSuffix(stem, "_thumb") + ext
}

// **two sweeps, one scan.** they differ in which prefix is listed, which rows protect a file and
// which of the storage's two deletion doors is used - and in nothing else, so the three rules above
// are written once and both sweeps obey them by construction.
type sweepScope struct {
	// for the log line
	name string

	// what to enumerate, and which paths this sweep may touch at all. `owns` is a second copy of the
	// guard inside the storage door: this one keeps a file out of the *report*, so nothing is ever
	// offered for deletion that would then be refused.
	prefix string
	owns   func(rel string) bool

	// the storage door. a catalogue file and an owner upload are deleted by different methods, so a
	// bug in one sweep cannot reach the other's files.
	remove func(images *imagestore.Disk, ctx context.Context, rel string) error

	// which stored paths protect a file
	referenced func(ctx context.Context, q *db.Queries) ([]string, error)

	// whether a GET also lists every file it saw, used or not. **only the catalogue scan does**: that
	// list is what the panel's photo picker offers instead of a text field where a mistyped path
	// blanks one tile in every shop of a market. the uploads sweep has no picker and no reason to
	// send four thousand names.
	listsEveryFile bool
}

// owner uploads whose products row went with a deleted shop
var uploadSweep = sweepScope{
	name:   "uploaded",
	prefix: imagestore.UploadDir,
	owns:   imagestore.IsUpload,
	remove: func(images *imagestore.Disk, ctx context.Context, rel string) error {
		return images.RemoveFile(ctx, rel)
	},
	referenced: func(ctx context.Context, q *db.Queries) ([]string, error) {
		return q.AdminUploadedImagePaths(ctx, imagestore.UploadDir+"/%")
	},
}

// curated catalogue shots nothing points at any more. **the case that creates them**: several sizes
// of one product now share one photo, so the files the others used to name are referenced by nothing
// - and a template row edited to a different photo leaves its old one behind the same way.
var catalogueSweep = sweepScope{
	name:   "catalogue",
	prefix: imagestore.CatalogueRoot,
	owns:   imagestore.IsCatalogue,
	remove: func(images *imagestore.Disk, ctx context.Context, rel string) error {
		return images.RemoveCatalogueFile(ctx, rel)
	},
	// **every referenced path, not only the templates'**: a shop seeded before a template's photo
	// changed still points at the old file, and deleting it would blank that shop's tile.
	listsEveryFile: true,
	referenced: func(ctx context.Context, q *db.Queries) ([]string, error) {
		rows, err := q.AdminReferencedImagePaths(ctx)
		if err != nil {
			return nil, err
		}
		// the union's column is nullable to sqlc even though the query filters nulls out
		paths := make([]string, 0, len(rows))
		for _, rel := range rows {
			if rel.Valid && rel.String != "" {
				paths = append(paths, rel.String)
			}
		}
		return paths, nil
	},
}

// GET  /api/admin/storage/orphans - count and measure, change nothing
// DELETE /api/admin/storage/orphans - do it
//
// **the DELETE re-runs the whole scan rather than taking a list of paths from the browser**: a
// client-supplied list would name files to delete with a live photo one typo away.
func (a *Admin) RouteOrphans(w http.ResponseWriter, r *http.Request) {
	a.routeSweep(w, r, uploadSweep)
}

// the same two verbs over the curated catalogue
func (a *Admin) RouteCatalogueFiles(w http.ResponseWriter, r *http.Request) {
	a.routeSweep(w, r, catalogueSweep)
}

func (a *Admin) routeSweep(w http.ResponseWriter, r *http.Request, scope sweepScope) {
	switch r.Method {
	case http.MethodGet:
		a.ScanOrphans(w, r, scope)
	case http.MethodDelete:
		a.SweepOrphans(w, r, scope)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (a *Admin) ScanOrphans(w http.ResponseWriter, r *http.Request, scope sweepScope) {
	orphans, report, ok := a.findOrphans(w, r, scope)
	if !ok {
		return
	}
	// **the paths travel on a GET and are ignored on the DELETE.** the panel lists what would go, so
	// a founder can check a name before pressing; the sweep re-derives its own list.
	report.Paths = make([]string, 0, len(orphans))
	for _, file := range orphans {
		report.Paths = append(report.Paths, file.Path)
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(report)
}

func (a *Admin) SweepOrphans(w http.ResponseWriter, r *http.Request, scope sweepScope) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	orphans, report, ok := a.findOrphans(w, r, scope)
	if !ok {
		return
	}
	report.Catalogue = nil // describes the store before this sweep, so it would be stale the moment it lands
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
		if err := scope.remove(a.Images, ctx, file.Path); err != nil {
			// keep going: one unwritable file must not leave the other four hundred behind
			log.Printf("WARNING: could not sweep orphaned photo %q: %v", file.Path, err)
			report.Failed++
			continue
		}
		deleted++
		bytes += file.Size
	}
	report.Files, report.Bytes = deleted, bytes

	log.Printf("ADMIN %d swept %d orphaned %s photo files (%d bytes, %d failed, %d left)",
		adminID, deleted, scope.name, bytes, report.Failed, report.Remaining)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(report)
}

// the scan every handler above runs, enforcing the three rules at the top of this section
func (a *Admin) findOrphans(w http.ResponseWriter, r *http.Request, scope sweepScope) ([]imagestore.Object, orphanReport, bool) {
	var report orphanReport

	// ── RULE 1, first half: the files, before the database.
	files, err := a.Images.List(r.Context(), scope.prefix)
	if err != nil {
		log.Printf("CRITICAL: could not list stored photos: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not read the photo storage")
		return nil, report, false
	}

	// ── RULE 1, second half: the database, after the files. a row committed between these two reads
	// is visible to this query, so its file is protected.
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	paths, err := scope.referenced(ctx, a.Queries)
	if err != nil {
		log.Printf("CRITICAL: could not read the referenced photo paths: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not read the product photos")
		return nil, report, false
	}

	// ── RULE 3: one row protects two files.
	claimed := make(map[string]struct{}, len(paths)*2)
	for _, rel := range paths {
		if !scope.owns(rel) {
			continue // a path of the other kind protects nothing here, and cannot be deleted here
		}
		claimed[rel] = struct{}{}
		claimed[imagestore.ThumbPath(rel)] = struct{}{}
	}

	// ── RULE 2: old enough to be sure.
	cutoff := time.Now().Add(-orphanMinAge)

	orphans := make([]imagestore.Object, 0, 8)
	for _, file := range files {
		// listing "shops" also returns the uploads directory underneath it, and the other way round a
		// stray file at the root belongs to neither sweep
		if !scope.owns(file.Path) && !scope.owns(masterPath(file.Path)) {
			continue
		}

		report.TotalFiles++
		report.TotalBytes += file.Size

		_, referenced := claimed[file.Path]
		// the picker's list rides on the same walk, so it obeys rule 1 for free. masters only:
		// a thumbnail is not a path any row stores. both stores list in key order already.
		if scope.listsEveryFile && masterPath(file.Path) == file.Path {
			report.Catalogue = append(report.Catalogue, catalogueFile{
				Path: file.Path, ThumbURL: a.URLs.Thumb(file.Path), Used: referenced, Size: file.Size,
			})
		}
		if referenced {
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

// ─────────────────────────── накладные ───────────────────────────

// the lists sent from the Корзина tab, and the one place outside the sender's own phone that can read
// them. the role is the sender's today, not at sending: a customer who opened a shop since reads as an owner.
type adminWaybillResponse struct {
	ID           int64           `json:"id"`
	ShopCategory string          `json:"shop_category"`
	ItemCount    int32           `json:"item_count"`
	HasPhoto     bool            `json:"has_photo"`
	CreatedAt    string          `json:"created_at"`
	SenderName   string          `json:"sender_name"`
	SenderPhone  string          `json:"sender_phone"`
	SenderRole   string          `json:"sender_role"`
	Items        json.RawMessage `json:"items,omitempty"`
}

func (a *Admin) ListWaybills(w http.ResponseWriter, r *http.Request) {
	limit, offset := adminPaging(r)

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := a.Queries.AdminListWaybills(ctx, db.AdminListWaybillsParams{Limit: limit, Offset: offset})
	if err != nil {
		log.Printf("CRITICAL: admin waybill list failed: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the lists")
		return
	}

	waybills := make([]adminWaybillResponse, 0, len(rows))
	for _, row := range rows {
		waybills = append(waybills, adminWaybillResponse{
			ID:           row.ID,
			ShopCategory: row.ShopCategory,
			ItemCount:    row.ItemCount,
			HasPhoto:     row.HasPhoto,
			CreatedAt:    timestampString(row.CreatedAt),
			SenderName:   row.SenderName.String,
			SenderPhone:  row.SenderPhone,
			SenderRole:   row.SenderRole,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"waybills": waybills, "limit": limit, "offset": offset})
}

func (a *Admin) RouteWaybill(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.GetWaybill(w, r)
	case http.MethodDelete:
		a.DeleteWaybill(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (a *Admin) GetWaybill(w http.ResponseWriter, r *http.Request) {
	row, ok := a.readWaybill(w, r)
	if !ok {
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(adminWaybillResponse{
		ID:           row.ID,
		ShopCategory: row.ShopCategory,
		HasPhoto:     row.HasPhoto,
		CreatedAt:    timestampString(row.CreatedAt),
		SenderName:   row.SenderName.String,
		SenderPhone:  row.SenderPhone,
		SenderRole:   row.SenderRole,
		Items:        row.Items,
	})
}

func (a *Admin) DeleteWaybill(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	id, ok := waybillIDFromPath(w, r)
	if !ok {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	deleted, err := a.Queries.AdminDeleteWaybill(ctx, id)
	if err != nil {
		log.Printf("CRITICAL: admin %d failed to delete waybill %d: %v", adminID, id, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the list")
		return
	}
	if deleted == 0 {
		writeAPIError(w, http.StatusNotFound, "waybill_not_found", "no list with that number")
		return
	}

	log.Printf("ADMIN %d deleted waybill %d", adminID, id)
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"deleted": true})
}

func (a *Admin) WaybillPhoto(w http.ResponseWriter, r *http.Request) {
	id, ok := waybillIDFromPath(w, r)
	if !ok {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	photo, err := a.Queries.AdminGetWaybillPhoto(ctx, id)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		log.Printf("CRITICAL: could not read the photo of waybill %d: %v", id, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the photo")
		return
	}
	writeWaybillPhoto(w, photo)
}

// WaybillPDF answers with the filled paper form. drawn on request rather than stored: the row is the
// document, so a form redrawn tomorrow cannot disagree with what was sent.
func (a *Admin) WaybillPDF(w http.ResponseWriter, r *http.Request) {
	row, ok := a.readWaybill(w, r)
	if !ok {
		return
	}

	doc := waybill.Document{
		Number: row.ID,
		Date:   row.CreatedAt.Time,
		To:     "Domix, магазины «" + catalog.ShopCategoryName(row.ShopCategory) + "»",
		From:   waybillSender(row.SenderName.String, row.SenderPhone),
	}

	if row.HasPhoto {
		ctx, cancel := dbctx.WithTimeout(r.Context())
		defer cancel()

		photo, err := a.Queries.AdminGetWaybillPhoto(ctx, row.ID)
		if err != nil {
			log.Printf("CRITICAL: could not read the photo of waybill %d: %v", row.ID, err)
			writeAPIError(w, http.StatusInternalServerError, "server_error", "could not build the pdf")
			return
		}
		doc.Photo = photo
	} else if err := json.Unmarshal(row.Items, &doc.Items); err != nil {
		log.Printf("CRITICAL: waybill %d holds rows that do not decode: %v", row.ID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not build the pdf")
		return
	}

	pdf, err := waybill.Render(doc)
	if err != nil {
		log.Printf("CRITICAL: could not render waybill %d: %v", row.ID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not build the pdf")
		return
	}

	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Length", strconv.Itoa(len(pdf)))
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="nakladnaya-%d.pdf"`, row.ID))
	w.Header().Set("Cache-Control", "no-store")
	w.Write(pdf)
}

func (a *Admin) readWaybill(w http.ResponseWriter, r *http.Request) (db.AdminGetWaybillRow, bool) {
	id, ok := waybillIDFromPath(w, r)
	if !ok {
		return db.AdminGetWaybillRow{}, false
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	row, err := a.Queries.AdminGetWaybill(ctx, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "waybill_not_found", "no list with that number")
			return db.AdminGetWaybillRow{}, false
		}
		log.Printf("CRITICAL: could not read waybill %d: %v", id, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the list")
		return db.AdminGetWaybillRow{}, false
	}
	return row, true
}

func waybillIDFromPath(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeAPIError(w, http.StatusBadRequest, "invalid_id", "waybill id must be a positive integer")
		return 0, false
	}
	return id, true
}

// «От кого» on the form: a name is optional on an account, the number never is.
func waybillSender(name, phone string) string {
	// 998901234567 as +998 90 123 45 67, the spelling somebody reads aloud off a printed sheet
	if len(phone) == 12 {
		phone = "+" + phone[:3] + " " + phone[3:5] + " " + phone[5:8] + " " + phone[8:10] + " " + phone[10:]
	}
	if name == "" {
		return phone
	}
	return name + ", " + phone
}
