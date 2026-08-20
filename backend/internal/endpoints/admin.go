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
)

// the admin panel's api - statistics for the dashboard, and the two destructive operations the
// founder runs by hand today: deleting a user and deleting a shop.
//
// **there used to be an admin.go here and it was deleted on purpose.** it held
// PUT /api/admin/shops/{id}/vip, and the argument for removing it was not that admin endpoints are
// bad - it was that the api had no way to tell an admin from anybody else. /api/auth/init accepted
// {"role":"admin"} and passed it straight to CreateUser, so the "admin-only" endpoint was open to
// whoever asked. that hole is closed (auth.go maps everything that is not shop_owner to customer,
// and the telegram handler only ever upgrades customer -> shop_owner), which is what makes this
// file safe to write now where it was not before.
//
// the whole admin surface is deliberately in one file, middleware included. it is the only place in
// the api where one caller acts on another user's data, so "read this file and you have read the
// entire privileged path" is worth more here than tidy layering.
//
// granting VIP is still not here. it was not asked for, and it is a different kind of decision from
// the two below - see §7 of CLAUDE.md for the SQL that does it.
type Admin struct {
	// the pool, not just Queries, because the template sync is three statements that must land
	// together: a shop left with rows inserted but the stale ones not yet deleted is a shop holding
	// two versions of its own basket, and the index would read it as neither.
	Pool    *pgxpool.Pool
	Queries *db.Queries
}

// the ceiling on how many rows one list request may return, and the default when the caller does
// not ask. an admin screen must not be the one endpoint in the api that can pull the whole database
// into memory, and a client that asks for a million rows is more likely a mistake than a need.
//
// 500 is chosen against the launch cohort of 50-70 shops with room to spare. the panel filters and
// sorts client-side, so it wants the whole set in one request; the day that stops being reasonable,
// offset is already wired through and the panel grows a pager.
const (
	adminListDefaultLimit = 200
	adminListMaxLimit     = 500
)

// RequireAdmin refuses anyone whose role is not `admin`, and it is the only thing standing between
// a logged-in shop owner and everybody else's account.
//
// it must be composed *inside* auth.RequireAuth, which is what proves the caller is who they say
// and puts their user id on the context. this layer answers the second question, and asking it
// separately is the same split authorizeShopAccess makes: "who are you" and "what may you do" are
// different questions with different failure modes.
//
// **the role is read from the database on every request and never from the token.** jwt.go carries
// no role claim by design - a token lives four months and a role can change inside that window, so
// a claim would let a demoted admin keep administering until their token expired. the extra query
// is a primary-key lookup, and auth.RequireAuth has just done the same one; merging them would save
// a round trip and cost the ability to read this file and see the check.
func (a *Admin) RequireAdmin(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := auth.UserIDFromContext(r.Context())
		if !ok {
			// unreachable unless this was wired without RequireAuth above it. failing closed with a
			// 401 is the only safe answer to "the middleware chain is not what I think it is".
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
			// the database is unreachable, which is not the caller's fault. 503 rather than 403 for
			// the same reason RequireAuth answers 503 rather than 401: a minute of database trouble
			// must not read as "you are not allowed", which is a message that sends someone
			// hunting for a permissions problem that does not exist.
			log.Printf("CRITICAL: cannot verify admin role for user %d: %v", userID, err)
			writeAPIError(w, http.StatusServiceUnavailable, "service_unavailable", "could not verify permissions")
			return
		}

		if role != "admin" {
			// deliberately the same response for a customer and for a shop owner. the panel's login
			// screen turns this into "этот аккаунт не администратор", and there is nothing to be
			// gained by telling a caller which non-admin role they hold.
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
	Support        adminSupportCounts  `json:"support"`
	Signups        []adminSignupDay    `json:"signups"`
	ShopCategories []adminShopCategory `json:"shop_categories"`

	// where every shop sits on the way from "created" to "publishing prices". the one thing on this
	// dashboard that says where the product is losing people rather than how much of it exists.
	Funnel adminFunnel `json:"funnel"`

	// the shops worth phoning, nearest to finishing first
	Attention []adminAttentionShop `json:"attention"`

	// what a basket costs in each market, and how far apart its shops are
	Baskets []adminBasket `json:"baskets"`

	// did anybody price anything this week
	Activity adminActivity `json:"activity"`

	// live paid placements, soonest to lapse first
	VIP []adminVipPlacement `json:"vip"`

	GeneratedAt string `json:"generated_at"`
}

type adminFunnel struct {
	Shops    int64 `json:"shops"`
	Empty    int64 `json:"empty"`
	Started  int64 `json:"started"`
	Halfway  int64 `json:"halfway"`
	Nearly   int64 `json:"nearly"`
	Complete int64 `json:"complete"`
	Stalled  int64 `json:"stalled"`
}

type adminAttentionShop struct {
	ID           int64  `json:"id"`
	Name         string `json:"name"`
	Category     string `json:"category"`
	OwnerName    string `json:"owner_name"`
	OwnerPhone   string `json:"owner_phone"`
	TemplateRows int64  `json:"template_rows"`
	PricedRows   int64  `json:"priced_rows"`
	Remaining    int64  `json:"remaining"`
}

type adminBasket struct {
	Category     string `json:"category"`
	Shops        int64  `json:"shops"`
	MeanBasket   int64  `json:"mean_basket"`
	MedianBasket int64  `json:"median_basket"`
	MinBasket    int64  `json:"min_basket"`
	MaxBasket    int64  `json:"max_basket"`
}

type adminActivity struct {
	Priced7d      int64 `json:"priced_7d"`
	Priced30d     int64 `json:"priced_30d"`
	ShopsActive7d int64 `json:"shops_active_7d"`
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
	// how many shops have priced their entire template and therefore appear in the price
	// comparison at all. after migration 000013 this is the number that decides whether the home
	// screen has anything on it.
	Ranked int64 `json:"ranked"`
}

type adminProductCounts struct {
	Total  int64 `json:"total"`
	Priced int64 `json:"priced"`
	Custom int64 `json:"custom"`
}

// the support inbox, carried on the dashboard request rather than fetched by the inbox screen, so
// the sidebar can say how many people are waiting before anybody opens it.
type adminSupportCounts struct {
	Threads int64 `json:"threads"`
	// conversations whose newest message came from the user - the count of people waiting for an
	// answer, not the count of unanswered messages
	Awaiting int64 `json:"awaiting"`
	// conversations holding something *this admin* has not opened yet. the badge's loud state, and
	// the only one of the three counts that reading clears - see migration 000002.
	//
	// both are sent because the panel shows both: unread is the alarm, awaiting is the queue behind
	// it, and a sidebar that only knew about unread would go quiet on a founder who had read five
	// questions and answered none.
	Unread int64 `json:"unread"`
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
// eight queries run sequentially on one context, the same shape Home.Get uses and for the same
// reason: fanning them into goroutines would take eight connections out of a pool of ten to serve
// one screen, which starves the pool faster than the serial version is slow. the whole handler
// shares one deadline rather than giving each query its own, because the caller's question is "draw
// the dashboard" and half a dashboard is not a useful answer.
//
// what is deliberately *not* here any more: the product-category breakdown, which was a picture of
// the catalogue rather than a fact about the business, and the anomaly teaser, which was a worse
// version of a page one click away.
func (a *Admin) Stats(w http.ResponseWriter, r *http.Request) {
	// the unread count is per-admin, so it cannot ride along inside AdminOverview - that query takes
	// no parameters and answers questions about the whole database, where this one is about a person.
	adminID, _ := auth.UserIDFromContext(r.Context())

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
	attention, err := a.Queries.AdminShopsNeedingAttention(ctx, 8)
	if err != nil {
		fail("attention", err)
		return
	}
	baskets, err := a.Queries.AdminBasketByCategory(ctx)
	if err != nil {
		fail("baskets", err)
		return
	}
	activity, err := a.Queries.AdminPricingActivity(ctx)
	if err != nil {
		fail("activity", err)
		return
	}
	placements, err := a.Queries.AdminVipPlacements(ctx, 8)
	if err != nil {
		fail("vip", err)
		return
	}
	unreadThreads, err := a.Queries.AdminUnreadSupportThreads(ctx, adminID)
	if err != nil {
		fail("support unread", err)
		return
	}

	// every slice is built with make(..., 0, n) rather than left nil: a nil slice encodes as `null`
	// and the panel iterates what it is given, so `[]` is the honest answer to "no rows".
	response := adminStatsResponse{
		Users: adminUserCounts{
			Total: overview.UsersTotal, Customers: overview.UsersCustomers,
			ShopOwners: overview.UsersShopOwners, Admins: overview.UsersAdmins,
			New7d: overview.UsersNew7d, New30d: overview.UsersNew30d,
		},
		Shops: adminShopCounts{
			Total: overview.ShopsTotal, New7d: overview.ShopsNew7d,
			VIP: overview.ShopsVip, Ranked: overview.ShopsRanked,
		},
		Products: adminProductCounts{
			Total: overview.ProductsTotal, Priced: overview.ProductsPriced, Custom: overview.ProductsCustom,
		},
		Support: adminSupportCounts{
			Threads: overview.SupportThreads, Awaiting: overview.SupportAwaiting,
			Unread: unreadThreads,
		},
		Funnel: adminFunnel{
			Shops: funnel.Shops, Empty: funnel.Empty, Started: funnel.Started,
			Halfway: funnel.Halfway, Nearly: funnel.Nearly, Complete: funnel.Complete,
			Stalled: funnel.Stalled,
		},
		Activity: adminActivity{
			Priced7d: activity.Priced7d, Priced30d: activity.Priced30d, ShopsActive7d: activity.ShopsActive7d,
		},
		Signups:        make([]adminSignupDay, 0, len(signups)),
		ShopCategories: make([]adminShopCategory, 0, len(shopCats)),
		Attention:      make([]adminAttentionShop, 0, len(attention)),
		Baskets:        make([]adminBasket, 0, len(baskets)),
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
			OwnerName: row.OwnerName.String, OwnerPhone: row.OwnerPhone,
			TemplateRows: row.TemplateRows, PricedRows: row.PricedRows, Remaining: row.Remaining,
		})
	}
	for _, row := range baskets {
		response.Baskets = append(response.Baskets, adminBasket{
			Category: row.Category, Shops: row.Shops, MeanBasket: row.MeanBasket,
			MedianBasket: row.MedianBasket, MinBasket: row.MinBasket, MaxBasket: row.MaxBasket,
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
// the same cascade DELETE /api/me runs: the user's shops go, and each shop takes its products. it is
// a hard delete for the same reason that one is - keeping a row nobody can reach is keeping the
// phone number somebody asked to have erased.
//
// **it refuses to delete an account whose role is admin, including the caller's own.** two reasons,
// and the second is the one that matters. the small one is that a panel whose delete button can
// remove the last administrator is a tool that can destroy itself, and recovering means SQL against
// production. the real one is that an admin account is the only kind whose deletion cannot be
// undone by the person it happened to: everyone else can register again with the same phone number
// and be back where they started, where an admin cannot re-grant themselves a role only SQL can
// set. deleting an administrator therefore stays a deliberate act at the database, which is where
// the role was granted in the first place.
func (a *Admin) DeleteUser(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	targetID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || targetID <= 0 {
		writeAPIError(w, http.StatusBadRequest, "invalid_id", "user id must be a positive integer")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// read the role before deleting rather than after, because after there is nothing left to read.
	// this is also what turns "no such user" into a 404 instead of a silent success.
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

	if role == "admin" {
		writeAPIError(w, http.StatusForbidden, "cannot_delete_admin",
			"administrator accounts cannot be deleted through the panel")
		return
	}

	deleted, err := a.Queries.AdminDeleteUser(ctx, targetID)
	if err != nil {
		log.Printf("CRITICAL: admin %d failed to delete user %d: %v", adminID, targetID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not delete the user")
		return
	}
	if deleted == 0 {
		// the row existed a moment ago when we read its role, so it was deleted between the two
		// statements. the admin is looking at a stale list either way.
		writeAPIError(w, http.StatusNotFound, "user_not_found", "no user with that id")
		return
	}

	// ids and a role, and nothing else. this is an audit line - it has to say who did what to whom -
	// and the name and phone number of the account just erased are exactly the data that must not be
	// copied into a log file on the way out.
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

	OwnerID    int64  `json:"owner_id"`
	OwnerName  string `json:"owner_name"`
	OwnerPhone string `json:"owner_phone"`

	ProductsTotal int64 `json:"products_total"`
	// the catalogue progress bar, counted over template rows only - the same rule
	// ShopProductsScreen's card uses, because the owner's own products are not in the shared basket.
	TemplateTotal  int64 `json:"template_total"`
	TemplatePriced int64 `json:"template_priced"`

	// null together or present together: the basket index view has no partial state, so a panel
	// branching on one having checked the other is handling something the backend cannot send.
	PriceIndex  *int64 `json:"price_index"`
	BasketPrice *int64 `json:"basket_price"`

	CreatedAt string `json:"created_at"`
}

// GET /api/admin/shops
//
// this is the one place in the api where the raw price index leaves the server. everywhere else it
// is deliberately withheld - ShopResponse carries a tier and a percentage instead, because "96" is
// a comparison the reader has to be taught to perform. an administrator is the reader who has been
// taught it, and the panel's job is to show what the system actually computed rather than a
// rendering of it.
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
			ID:             row.ID,
			Name:           row.Name,
			Category:       row.Category,
			Address:        row.Address,
			ContactPhone:   row.ContactPhone,
			IsVIP:          row.IsVip,
			VipUntil:       timestampString(row.VipUntil),
			OwnerID:        row.OwnerID,
			OwnerName:      row.OwnerName.String,
			OwnerPhone:     row.OwnerPhone,
			ProductsTotal:  row.ProductsTotal,
			TemplateTotal:  row.TemplateTotal,
			TemplatePriced: row.TemplatePriced,
			CreatedAt:      timestampString(row.CreatedAt),
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

// DELETE /api/admin/shops/{id} - the shop and its products, leaving the owner's account alone.
//
// there is no role or ownership check beyond RequireAdmin, which is the whole point of the endpoint:
// authorizeShopAccess would refuse an admin acting on a shop they do not own, and an administrator
// acting on other people's shops is what this panel is for.
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

// adminPaging reads ?limit= and ?offset=, clamping both into a sane range rather than rejecting a
// bad one. a list endpoint answering 400 because someone typed limit=0 in a url bar is a worse
// experience than one that quietly gives them the default, and there is no ambiguity about intent
// to preserve here.
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

// timestampString renders a nullable postgres timestamp as RFC3339, or "" when it is null.
//
// the empty string rather than a zero time, because every field using this is `omitempty` on the
// wire and the panel checks for absence. a zero time would arrive as "0001-01-01T00:00:00Z" and
// render as a date in the year one.
func timestampString(ts pgtype.Timestamptz) string {
	if !ts.Valid {
		return ""
	}
	return ts.Time.UTC().Format(time.RFC3339)
}

// ─────────────────────────── editing ───────────────────────────

// the roles an admin may assign through the panel.
//
// **`admin` is deliberately absent, and this is the same invariant §7 states: no path reachable over
// the network may grant it.** the original hole was an unauthenticated one - /api/auth/init accepted
// {"role":"admin"} - and this endpoint is not that: it is behind RequireAdmin, so only an
// administrator could use it. it stays closed anyway, because the property worth keeping is not "an
// attacker cannot reach it" but "there is no code path at all", which survives a mistake in the
// middleware wiring, a stolen admin token, and an XSS bug in the panel. granting admin is one line
// of SQL by whoever runs Domix, which is a deliberate act at the machine that holds the data.
var assignableRoles = map[string]bool{"customer": true, "shop_owner": true}

// PUT /api/admin/users/{id} - name and role.
//
// phone is not editable and that is not an oversight: it is the identity key the telegram handshake
// looks users up by, so retyping it would silently orphan the account from its own login.
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
		writeAPIError(w, http.StatusBadRequest, "invalid_role", "role must be customer or shop_owner")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// the mirror of the rule above: an existing administrator cannot be demoted here either, or the
	// panel would have a one-click path to locking every administrator out of itself - including,
	// most likely, whoever is clicking.
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
	if current == "admin" {
		writeAPIError(w, http.StatusForbidden, "cannot_edit_admin",
			"administrator accounts cannot be edited through the panel")
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

// PUT /api/admin/shops/{id} - the same four fields the owner's own edit form submits.
//
// it reuses UpdateShop rather than getting its own statement, which is what keeps `category` and
// `vip_until` out of reach by construction. category decided which template seeded this shop's
// catalogue, so changing it would leave the shop stocked from the wrong list with no way back;
// vip_until is a paid placement and has its own endpoint below, where it can be logged as the
// commercial decision it is.
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
// **§7 said adding this back needed a conversation, and this is that conversation's outcome** - the
// founder asked for it directly. What the old objection was about is worth keeping straight: the
// endpoint was deleted because the api could not tell an admin from anybody else, not because the
// operation is wrong. That hole is closed, and this route sits behind RequireAdmin.
//
// The narrower objection - a placement is *sold*, so an endpoint that grants it is one somebody will
// ask to have pointed at their own shop - is answered by who can reach it rather than by the
// endpoint not existing. It is logged like a deletion, for the same reason: it is a commercial
// decision with money behind it, and "when did this shop become VIP" is a question somebody will ask.
//
// `days` rather than an absolute date, because the panel's realistic input is "sold them a month".
// Zero or a missing value revokes - one statement for both, since they are the same fact with
// different values (see SetShopVIP).
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
	// two years, because the input is a number in a box and a slipped keypress should not sell
	// somebody a placement until 2at190. revoking is days <= 0.
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

// ─────────────────────────── products ───────────────────────────

// GET /api/admin/shops/{id}/products - one shop's whole catalogue, unfiltered.
//
// deliberately unlike the customer-facing grid, which shows only priced rows: an admin's reason for
// opening this is usually the unpriced ones, or a price that looks wrong.
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
		imageURL, ownImage := productImage(row.ImagePath)
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
			OwnImage:      ownImage,
			PhotoEditable: photoEditable,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"products": products})
}

// PUT /api/admin/products/{id}
//
// **an admin gets the same three-way rule the owner gets, not a bypass of it**, and that is the whole
// design decision in this handler. the rule exists for data integrity rather than for permissions: a
// renamed template row silently stops being the same product as its counterpart down the road, and
// the Basket Price Index is built entirely on those rows meaning the same thing everywhere. an admin
// renaming one breaks the comparison exactly as thoroughly as an owner would, so the statements they
// go through are the same statements - UpdateProductPricing has no SET for name at all.
//
// what an admin actually needs here is the price, which is the field the anomaly report sends them
// to fix. that is available on every row.
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

	// read the row first so the branch is decided by the database's own template_key, never by
	// anything the client sent - the same reason Products.authorizeProductAccess reads it first.
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

	// a local shape rather than db.Product: the three UPDATE statements each generate their own row
	// type (sqlc emits one per query by design) and none of them is convertible to another, since
	// they omit created_at/updated_at that the table struct has. one struct assigned in three places
	// is what lets the response be built once below.
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
	imageURL, ownImage := productImage(updated.ImagePath)
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(ProductResponse{
		ID: updated.ID, ShopID: updated.ShopID, Name: updated.Name,
		Category: updated.Category, Unit: updated.Unit,
		Price: nullableInt64(updated.Price), Availability: updated.Availability,
		IsTemplate: isTemplate, NameEditable: nameEditable,
		ImageURL: imageURL, OwnImage: ownImage, PhotoEditable: photoEditable,
	})
}

// ─────────────────────────── anomalies ───────────────────────────

// how far off the market a price has to be before the report mentions it, and how many shops must
// have priced a line before "the market" means anything.
//
// both are query parameters with these as defaults, because the right numbers are unknown until
// there is real data - the same reason internal/pricing's ±2 band is documented as a guess. 50% is
// deliberately loose: at launch a genuinely cheap shop and a typo look similar, and a report nobody
// can get through is a report nobody reads.
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
//
// **the template is read-only here, and that is a real limitation rather than an oversight.** the
// lists live in Go (internal/catalog/templates.go) and are compiled into the binary; making them
// editable from this page means moving them into a table, which changes how every shop is seeded and
// what templates_test.go can still guarantee. that is a migration to do deliberately, not a checkbox
// to add to a styling pass. what this endpoint plus Sync below gives today is the half that was
// actually blocking: edit the Go file, restart, then press one button instead of deleting shops.
func (a *Admin) Templates(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	out := make([]adminTemplateCategory, 0, len(catalog.AllShopCategories))
	for _, category := range catalog.AllShopCategories {
		code := string(category)

		// read from the table rather than from the in-memory copy, because the editor needs each
		// row's id to edit or delete it and internal/catalog deliberately does not carry one - it
		// holds what seeding needs, which is the product, not the record.
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
			// what every shop of this category *should* hold, minus what they do hold. a shop created
			// before a product was added to the template is missing that row and nothing tells it.
			MissingRows: status.Shops*int64(len(stored)) - status.PresentRows,
			StaleRows:   status.StaleRows,
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"templates": out})
}

// POST /api/admin/templates/{category}/sync - push the current template into every existing shop of
// that category.
//
// **this is the button that replaces "delete the shop and make it again".** seeding happens once, at
// creation, so until now a template edited afterwards reached nobody: every existing shop kept the
// list it was born with. Three statements, in one transaction, in this order:
//
//	insert  - rows the template has and the shop does not, unpriced
//	update  - names/units/categories/photos for rows both have, prices untouched
//	delete  - rows the shop has and the template no longer does
//
// the transaction is not decoration. a shop left with the new rows inserted but the stale ones not
// yet deleted holds two versions of its own basket, and shop_basket_index would count both - so it
// would publish a total for goods it does not sell, under a badge claiming that is what it costs.
//
// **two things it will do that are worth knowing before pressing it.** Adding a product to a
// template drops every shop of that category out of the price comparison until its owner prices the
// new row - one unpriced template row is enough (migration 000013), and that is the rule working.
// And deleting one takes whatever price the owner had typed for it, with no undo.
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

	// names are rewritten for a template of products and left alone for a template of slots. an обои
	// row's name is the owner's own wallpaper; the template's is a placeholder saying what belongs
	// there, and writing it back would replace every обои shop's catalogue with ten placeholders.
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

// the json shape jsonb_to_recordset expands back into rows. the field names are the recordset's
// column names in db/queries/admin.sql, so renaming one here silently stops the sync from matching
// anything - they are a contract, not a serialization detail.
type adminTemplateSyncRow struct {
	TemplateKey string `json:"template_key"`
	Name        string `json:"name"`
	Category    string `json:"category"`
	Unit        string `json:"unit"`
	ImagePath   string `json:"image_path"`
}

// ─────────────────────────── support inbox ───────────────────────────
//
// the privileged half of internal/endpoints/support.go. it is here rather than there for the reason
// this whole file exists: every route below reads or writes a conversation belonging to somebody
// else, and "read admin.go and you have read the entire privileged path" is worth more than keeping
// a feature's two halves adjacent.
//
// **a thread is addressed by user id, not by a thread id**, because a thread is exactly one user's
// messages - there is no row to point at. that also means the id in the url is the id of a `users`
// row, which is why the handlers below check that the user exists rather than trusting a lookup to
// fail: replying into a thread whose owner was deleted a second ago would otherwise insert a message
// nobody can ever read, or fail on a foreign key with a 500.

type adminSupportThreadSummary struct {
	UserID int64  `json:"user_id"`
	Name   string `json:"name"`
	Phone  string `json:"phone"`
	Role   string `json:"role"`
	Total  int64  `json:"total"`

	// **two counts, two questions, and the panel shows both.**
	//
	// `unanswered` is the queue: messages from this user newer than the last thing support said. it
	// is derived in SQL and reading a thread does not move it, which is deliberate - a conversation
	// opened and not replied to is still work, and the alternative loses it the moment the founder
	// gets distracted between reading and typing.
	//
	// `unread` is the notification: messages newer than the last time this admin opened the thread.
	// this is the one that clears on read, and it is what the sidebar badge counts.
	Unanswered int64 `json:"unanswered"`
	Unread     int64 `json:"unread"`

	// enough of the last message to recognise the conversation in a list. sent whole rather than
	// truncated here: the panel decides how much of it fits, and a server that pre-truncates makes
	// that decision permanently for every future layout.
	LastBody        string `json:"last_body"`
	LastFromSupport bool   `json:"last_from_support"`
	LastAt          string `json:"last_at"`
}

// GET /api/admin/support/threads - the inbox.
//
// **this is a read and only a read.** the panel polls it every few seconds while the section is open,
// so anything with a side effect here would fire on a timer; marking a thread read belongs to the
// request that actually opens one (SupportThread below).
func (a *Admin) SupportThreads(w http.ResponseWriter, r *http.Request) {
	// whose "read" marks to compare against. RequireAdmin has already proved this id is an admin, so
	// the only way the lookup fails is a middleware chain that is not what this file assumes - and
	// the zero value would then silently mean "has read nothing", which is the safe direction.
	adminID, _ := auth.UserIDFromContext(r.Context())

	limit, offset := adminPaging(r)

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := a.Queries.AdminSupportThreads(ctx, db.AdminSupportThreadsParams{
		AdminID: adminID, Limit: limit, Offset: offset,
	})
	if err != nil {
		log.Printf("CRITICAL: admin support inbox failed to load: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the inbox")
		return
	}

	threads := make([]adminSupportThreadSummary, 0, len(rows))
	for _, row := range rows {
		threads = append(threads, adminSupportThreadSummary{
			UserID: row.UserID, Name: row.Name.String, Phone: row.Phone, Role: row.Role,
			Total: row.Total, Unanswered: row.Unanswered, Unread: row.Unread,
			LastBody: row.LastBody, LastFromSupport: row.LastFromSupport,
			LastAt: timestampString(row.LastAt),
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"threads": threads, "limit": limit, "offset": offset})
}

// GET /api/admin/support/threads/{id} - one conversation in full, with whoever it belongs to.
//
// the user is returned alongside the messages rather than being looked up from the already-loaded
// inbox, so the page works when it is opened directly and so a thread with no messages in it still
// names somebody.
//
// **this GET writes, and that is a considered trade rather than an oversight.** it advances the
// caller's read watermark, because in this panel opening a conversation *is* this request - there is
// no other way to have read one. the honest alternative is POST /api/admin/support/threads/{id}/read
// as a second round trip, and a second round trip is a second thing that can fail on its own: a
// thread would then be read on screen and unread in the database, and the badge would keep pointing
// at a message the founder is looking at.
//
// what makes it safe to put on a GET is that the write is a *watermark* and idempotent - running it
// twice, or on every poll while the thread sits open, lands on the same row with the same value. it
// is also why the inbox listing above deliberately does not do it: that one is polled on a timer,
// where this one is a person opening something.
func (a *Admin) SupportThread(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	userID, ok := adminPathID(w, r, "user")
	if !ok {
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	user, err := a.Queries.GetUserByID(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "user_not_found", "no user with that id")
			return
		}
		log.Printf("CRITICAL: admin could not read user %d for their support thread: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the conversation")
		return
	}

	rows, err := a.Queries.ListSupportThread(ctx, userID)
	if err != nil {
		log.Printf("CRITICAL: admin could not load the support thread of user %d: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the conversation")
		return
	}

	messages := make([]supportMessageResponse, 0, len(rows))
	for _, row := range rows {
		messages = append(messages, supportMessageDTO(row))
	}

	// after the read succeeded, and a failure here is logged rather than returned: the founder asked
	// to see a conversation, and refusing to show it because a bookkeeping row would not save would
	// be answering the wrong question. the cost of the failure is a badge that stays lit.
	if err := a.Queries.AdminMarkSupportThreadRead(ctx, db.AdminMarkSupportThreadReadParams{
		AdminID: adminID, ThreadUserID: userID,
	}); err != nil {
		log.Printf("WARNING: admin %d read user %d's thread but the read marker did not save: %v",
			adminID, userID, err)
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{
		"user": map[string]any{
			"id": user.ID, "name": user.Name.String, "phone": user.Phone, "role": user.Role,
		},
		"messages": messages,
	})
}

// POST /api/admin/support/threads/{id} - the answer.
//
// `from_support: true` is set here and nowhere else, exactly as the app's endpoint hardcodes false.
// neither side reads that flag off a request body, which is what stops a message from claiming to
// have come from the other end of the conversation.
//
// there is deliberately no notification. the reply waits in the app's Сообщения tab until the user
// opens it - the app has no push notifications of any kind, and the obvious fix (the bot already
// knows every user's chat id) is a separate piece of work.
func (a *Admin) SupportReply(w http.ResponseWriter, r *http.Request) {
	adminID, _ := auth.UserIDFromContext(r.Context())

	userID, ok := adminPathID(w, r, "user")
	if !ok {
		return
	}

	var req supportSendRequest
	if !decodeJSONBody(w, r, &req) {
		return
	}

	body, fail := cleanSupportBody(req.Body)
	if fail != nil {
		fail.write(w)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	// checked before the insert rather than left to the foreign key, so "this person deleted their
	// account while you were typing" reads as a 404 the panel can explain instead of a 500.
	if _, err := a.Queries.GetUserByID(ctx, userID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeAPIError(w, http.StatusNotFound, "user_not_found", "no user with that id")
			return
		}
		log.Printf("CRITICAL: admin %d could not verify user %d before replying: %v", adminID, userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not send the reply")
		return
	}

	message, err := a.Queries.CreateSupportMessage(ctx, db.CreateSupportMessageParams{
		UserID:      userID,
		FromSupport: true,
		Body:        body,
	})
	if err != nil {
		log.Printf("CRITICAL: admin %d could not reply to user %d: %v", adminID, userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not send the reply")
		return
	}

	// **answering something is a stronger claim than having read it**, so the reply advances the read
	// watermark too. without this the badge stays lit on a conversation the founder has just replied
	// to - which is the exact complaint the read marker exists to fix, reappearing one step later.
	//
	// the case it actually covers: a message that arrived *while* the reply was being typed. the GET
	// that opened the thread marked it read up to that moment, and anything after it would otherwise
	// still be counted. answering the conversation settles all of it.
	if err := a.Queries.AdminMarkSupportThreadRead(ctx, db.AdminMarkSupportThreadReadParams{
		AdminID: adminID, ThreadUserID: userID,
	}); err != nil {
		log.Printf("WARNING: admin %d replied to user %d but the read marker did not save: %v",
			adminID, userID, err)
	}

	// ids only, like every other line in this file: the message body is the user's own words about
	// their own problem, and a log file is not where it belongs.
	log.Printf("ADMIN %d replied to user %d (message %d)", adminID, userID, message.ID)

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(supportMessageDTO(message))
}

// ─────────────────────────── routing ───────────────────────────

// one path carries two verbs in both cases, so the method split lives here rather than as two mux
// patterns - the same shape Auth.RouteMe and Shops.RouteByID use.
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

func (a *Admin) RouteSupportThread(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.SupportThread(w, r)
	case http.MethodPost:
		a.SupportReply(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// adminPathID parses the {id} wildcard, writing its own 400 on failure. `noun` only shapes the
// message - "user id must be…" reads better in a panel toast than a generic one.
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
// **every handler that writes to that table must call this before responding.** the whole api reads
// templates out of memory - seeding, IsOwnerNamedSlot, the sync payload - so a write that skips the
// reload leaves the process serving the old list until it restarts. the founder would edit a
// template, press sync, and watch nothing change.
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

// the column widths of `products`, which every one of these values is copied into at seeding. a
// template row that fits product_templates but not products would fail at shop creation, which is
// the worst possible moment to discover it.
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
	// rune counts, not len(): every cyrillic character is two bytes and postgres counts varchar
	// limits in characters, so a byte check would reject names that fit and accept ones that do not
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
// **it does not touch a single existing shop, and that separation is the design.** adding a row here
// decides what the *next* shop is created with; pushing it into shops that already exist is the sync
// button, which is louder because it has consequences - every shop of the category drops out of the
// price comparison until its owner prices the new line (migration 000013).
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

	// checked before inserting so the answer is a readable 409 rather than a unique-violation 500.
	// the constraint is still what actually guarantees it - this is the message, not the guard.
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

// the shape a key may take. latin only, because it is an identifier rather than display text and it
// ends up in urls, logs and this file's own prose; and no spaces, because a key with one is a key
// somebody will eventually mistype.
var templateKeyPattern = regexp.MustCompile(`^[a-z0-9]+(?:[._][a-z0-9]+)*$`)

// PUT /api/admin/templates/items/{id} - edit a template product.
//
// name, product category, unit and photo. **not the key** - see AdminUpdateTemplateItem for why
// changing it would silently destroy prices rather than rename anything.
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

// DELETE /api/admin/templates/items/{id}
//
// removes the product from the template only. every existing shop keeps its copy - and its price -
// until somebody presses sync, which is where the destructive half lives and where the warning is.
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
