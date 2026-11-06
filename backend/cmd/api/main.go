package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime/debug"
	"strconv"
	"strings"
	"syscall"
	"time"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/endpoints"
	"domix/backend/internal/geo"
	"domix/backend/internal/imagestore"
	"domix/backend/internal/ratelimit"
	"domix/backend/internal/verify"
	"domix/backend/internal/webui"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {

	if err := godotenv.Load("../.env"); err != nil {
		log.Println("WARNING: No .env file found")
	}

	port := os.Getenv("PORT")
	jwtSecret := os.Getenv("JWT_SECRET")
	dbURL := os.Getenv("DB_URL")

	if port == "" {
		port = "8080"
	}
	if dbURL == "" {
		log.Fatal("Critical error: DB_URL must be configured")
	}
	if jwtSecret == "" {
		log.Fatal("Critical error: JWT_SECRET must be configured")
	}

	dbPool := mustConnectDB(dbURL)
	queries := db.New(dbPool)
	mustLoadTemplates(queries)

	// the sender is opened first: it decides whether the send budgets are armed - console is free
	codeSender, paidDelivery := mustOpenCodeSender()
	reviewPhone, reviewCode := mustReadReviewAccount()
	codeMgr := auth.NewCodeManager(paidDelivery).WithReviewAccount(reviewPhone, reviewCode)

	// opened here because deleting an account deletes its photos, not only its rows
	productImages, imageURLs := mustOpenPhotoStorage()

	addressSearch := mustOpenAddressSearch(queries)

	// **signed-in callers by account, others by address**: one carrier IP fronts thousands of users.
	// none of these guards the code-sending bill - the per-phone and daily budgets in auth.CodeManager do.
	byCaller := func(r *http.Request) string {
		if id, ok := auth.UserIDFromRequest(r, jwtSecret); ok {
			return "user:" + strconv.FormatInt(id, 10)
		}
		return "ip:" + ratelimit.ClientIP(r)
	}

	apiLimiter := ratelimit.New(20, 60, 10*time.Minute).Keyed(byCaller)
	uploadLimiter := ratelimit.New(1, 20, 30*time.Minute) // keyed by account inside Products.allowUpload

	// **public buckets are floors against a flood, not fine control**: a whole carrier sits behind one
	// address. the real bound is publicCache, Home.SearchSlots and the code budgets.
	publicLimiter := ratelimit.New(50, 200, 10*time.Minute)
	loginLimiter := ratelimit.New(5, 60, 10*time.Minute)
	searchLimiter := ratelimit.New(3, 30, 10*time.Minute)

	// **far wider than searchLimiter on purpose**: a suggestion is read out of memory, so the cost of
	// one is a few hundred string comparisons, while the shape of the traffic is a request every few
	// keystrokes from everybody typing at once - behind one carrier address.
	suggestLimiter := ratelimit.New(20, 60, 10*time.Minute)

	// **every miss here spends a call from a budget the whole app shares**, so this only stops one caller
	// taking the day's share in a minute. the ceiling is geo.DailyCap, and repeats answer from geo's cache.
	geoLimiter := ratelimit.New(0.25, 20, 30*time.Minute).Keyed(byCaller)

	// held in memory for a minute, which is what makes publicLimiter affordable at those numbers
	publicReads := endpoints.NewPublicCache(time.Minute)

	// tighter, because every call here can spend money
	codeLimiter := ratelimit.New(0.5, 10, 30*time.Minute)

	// request-code spends money so it sits behind codeLimiter; verify only reads ram
	phoneAuth := &endpoints.PhoneAuth{Queries: queries, Codes: codeMgr, Sender: codeSender, JWTSecret: jwtSecret}
	http.HandleFunc("/api/auth/request-code", endpoints.WithJSON(codeLimiter.Wrap(phoneAuth.RequestCode)))
	http.HandleFunc("/api/auth/verify", endpoints.WithJSON(loginLimiter.Wrap(phoneAuth.Verify)))

	// the same two steps and buckets, with RequireAuth on top: this edits an account rather than opening one
	http.HandleFunc("/api/me/phone/request-code", endpoints.WithJSON(codeLimiter.Wrap(
		auth.RequireAuth(jwtSecret, queries, phoneAuth.RequestPhoneChangeCode))))
	http.HandleFunc("/api/me/phone/verify", endpoints.WithJSON(loginLimiter.Wrap(
		auth.RequireAuth(jwtSecret, queries, phoneAuth.VerifyPhoneChange))))

	authEndpoints := &endpoints.Auth{Queries: queries, Images: productImages}
	http.HandleFunc("/api/me", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, authEndpoints.RouteMe))))

	// the /delete-account page Google Play requires: public, so request-code takes the money bucket too
	deletionEndpoints := &endpoints.AccountDeletion{Queries: queries, Codes: codeMgr, Sender: codeSender, Images: productImages}
	http.HandleFunc("/api/account-deletion/request-code", endpoints.WithJSON(codeLimiter.Wrap(deletionEndpoints.RequestCode)))
	http.HandleFunc("/api/account-deletion/confirm", endpoints.WithJSON(loginLimiter.Wrap(deletionEndpoints.Confirm)))

	// **a public GET and an authenticated write on one path need two buckets**: browsing must survive a
	// carrier's worth of strangers, while creating a shop seeds a hundred rows and is metered per account.
	browse := func(handler http.HandlerFunc) http.HandlerFunc {
		read, write := publicLimiter.Wrap(handler), apiLimiter.Wrap(handler)
		return func(w http.ResponseWriter, r *http.Request) {
			if r.Method == http.MethodGet {
				read(w, r)
				return
			}
			write(w, r)
		}
	}

	shopsEndpoints := &endpoints.Shops{Pool: dbPool, Queries: queries, JWTSecret: jwtSecret, Cache: publicReads}
	http.HandleFunc("/api/shops", endpoints.WithJSON(browse(shopsEndpoints.Route)))
	http.HandleFunc("/api/shops/mine", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, shopsEndpoints.ListMine))))
	http.HandleFunc("/api/shops/{id}", endpoints.WithJSON(browse(shopsEndpoints.RouteByID)))

	productsEndpoints := &endpoints.Products{
		Queries:   queries,
		JWTSecret: jwtSecret,
		Images:    productImages,
		URLs:      imageURLs,
		Uploads:   uploadLimiter,
	}
	http.HandleFunc("/api/shops/{id}/products", endpoints.WithJSON(browse(productsEndpoints.RouteByShop)))
	http.HandleFunc("/api/products/{id}", endpoints.WithJSON(apiLimiter.Wrap(productsEndpoints.RouteByID)))
	// its own pattern: a multipart body and a different limit
	http.HandleFunc("/api/products/{id}/image", endpoints.WithJSON(apiLimiter.Wrap(productsEndpoints.RouteImage)))

	homeEndpoints := &endpoints.Home{
		Queries: queries,
		URLs:    imageURLs,
		Cache:   publicReads,
		// four in ten pool connections may be searching at once - see Home.SearchSlots
		SearchSlots: make(chan struct{}, max(1, int(dbPool.Config().MaxConns)*2/5)),
	}
	http.HandleFunc("/api/home", endpoints.WithJSON(publicLimiter.Wrap(homeEndpoints.Get)))
	http.HandleFunc("/api/categories/{code}/products", endpoints.WithJSON(publicLimiter.Wrap(homeEndpoints.ProductsByCategory)))
	// the one public read whose cost the caller chooses, so the one that is not cached
	http.HandleFunc("/api/products/search", endpoints.WithJSON(publicLimiter.Wrap(searchLimiter.Wrap(homeEndpoints.SearchProducts))))
	// the as-you-type panel over that field. not behind publicLimiter: it shares no budget with the
	// reads that cost a connection, and the limiter it does have is only a floor against a flood.
	http.HandleFunc("/api/products/suggest", endpoints.WithJSON(suggestLimiter.Wrap(homeEndpoints.SuggestProducts)))

	geoEndpoints := &endpoints.Geo{Service: addressSearch}
	http.HandleFunc("/api/geo/search", endpoints.WithJSON(geoLimiter.Wrap(geoEndpoints.Search)))
	http.HandleFunc("/api/geo/suggest", endpoints.WithJSON(geoLimiter.Wrap(geoEndpoints.Suggest)))
	http.HandleFunc("/api/geo/place", endpoints.WithJSON(geoLimiter.Wrap(geoEndpoints.Place)))
	http.HandleFunc("/api/geo/reverse", endpoints.WithJSON(geoLimiter.Wrap(geoEndpoints.Reverse)))

	favoritesEndpoints := &endpoints.Favorites{Queries: queries, URLs: imageURLs}
	http.HandleFunc("/api/favorites", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, favoritesEndpoints.Route))))
	http.HandleFunc("/api/favorites/{id}", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, favoritesEndpoints.RouteByID))))

	// a person sends a few lists a day, and a photo costs a decode and half a megabyte of database: ten
	// at once, then one every ten minutes. forgotten after a day idle, or waiting would refill it early.
	waybillEndpoints := &endpoints.Waybills{Queries: queries, Sends: ratelimit.New(1.0/600, 10, 24*time.Hour)}
	// **one chain built once, like adminRoute below**: a route left off it answers any shop owner
	customerRoute := func(handler http.HandlerFunc) http.HandlerFunc {
		return endpoints.WithJSON(apiLimiter.Wrap(
			auth.RequireAuth(jwtSecret, queries, waybillEndpoints.RequireCustomer(handler)),
		))
	}
	http.HandleFunc("/api/waybills", customerRoute(waybillEndpoints.Route))
	http.HandleFunc("/api/waybills/photo", customerRoute(waybillEndpoints.CreateFromPhoto))
	http.HandleFunc("/api/waybills/{id}/photo", customerRoute(waybillEndpoints.Photo))

	// **one chain built once, so no route can quietly forget RequireAdmin.** the order is load-bearing:
	// RequireAuth puts the caller's id on the context, RequireAdmin reads it.
	adminEndpoints := &endpoints.Admin{Pool: dbPool, Queries: queries, URLs: imageURLs, Images: productImages}
	adminRoute := func(handler http.HandlerFunc) http.HandlerFunc {
		return endpoints.WithJSON(apiLimiter.Wrap(
			auth.RequireAuth(jwtSecret, queries, adminEndpoints.RequireAdmin(handler)),
		))
	}
	http.HandleFunc("/api/admin/stats", adminRoute(adminEndpoints.Stats))
	http.HandleFunc("/api/admin/anomalies", adminRoute(adminEndpoints.Anomalies))

	http.HandleFunc("/api/admin/users", adminRoute(adminEndpoints.ListUsers))
	http.HandleFunc("/api/admin/users/{id}", adminRoute(adminEndpoints.RouteUser))

	http.HandleFunc("/api/admin/shops", adminRoute(adminEndpoints.ListShops))
	http.HandleFunc("/api/admin/shops/{id}", adminRoute(adminEndpoints.RouteShop))
	http.HandleFunc("/api/admin/shops/{id}/vip", adminRoute(adminEndpoints.SetVIP))
	http.HandleFunc("/api/admin/shops/{id}/photo", adminRoute(adminEndpoints.RouteShopPhoto))
	http.HandleFunc("/api/admin/shops/{id}/exclude", adminRoute(adminEndpoints.SetExcluded))
	http.HandleFunc("/api/admin/shops/{id}/products", adminRoute(adminEndpoints.ListShopProducts))
	http.HandleFunc("/api/admin/products/{id}", adminRoute(adminEndpoints.UpdateProduct))

	// every write reloads internal/catalog, or the process keeps seeding shops from the list it booted with
	http.HandleFunc("/api/admin/templates", adminRoute(adminEndpoints.Templates))
	http.HandleFunc("/api/admin/templates/{category}/items", adminRoute(adminEndpoints.RouteTemplateItems))
	// a separate path: go's mux refuses /templates/items/{id} beside /templates/{category}/items
	http.HandleFunc("/api/admin/template-items/{id}", adminRoute(adminEndpoints.RouteTemplateItem))
	// editing a template decides what the next shop gets; the sync pushes it into existing shops
	http.HandleFunc("/api/admin/templates/{category}/sync", adminRoute(adminEndpoints.SyncTemplate))
	// a whole template pasted from a sheet: the difference first, the write only on apply
	http.HandleFunc("/api/admin/templates/{category}/import", adminRoute(adminEndpoints.ImportTemplate))
	// the only way a photo enters images/shops/<category>/
	http.HandleFunc("/api/admin/catalogue/{category}/photo", adminRoute(adminEndpoints.UploadCataloguePhoto))

	http.HandleFunc("/api/admin/waybills", adminRoute(adminEndpoints.ListWaybills))
	http.HandleFunc("/api/admin/waybills/{id}", adminRoute(adminEndpoints.RouteWaybill))
	http.HandleFunc("/api/admin/waybills/{id}/photo", adminRoute(adminEndpoints.WaybillPhoto))
	http.HandleFunc("/api/admin/waybills/{id}/pdf", adminRoute(adminEndpoints.WaybillPDF))

	// photos no row points at. uploads and the curated catalogue go through two doors, see sweepScope
	http.HandleFunc("/api/admin/storage/orphans", adminRoute(adminEndpoints.RouteOrphans))
	http.HandleFunc("/api/admin/storage/catalogue", adminRoute(adminEndpoints.RouteCatalogueFiles))

	http.Handle(imagestore.DefaultURLPrefix, staticFiles(imagestore.DefaultURLPrefix, productImagesDir()))
	http.HandleFunc("/health", healthCheck(dbPool))

	// deliberately not behind WithJSON: a json content type makes a browser download a page instead of
	// rendering it
	site, err := webui.NewSite(webui.SiteConfig{
		SupportEmail:  supportEmail,
		PolicyVersion: policyVersion,
		TermsVersion:  termsVersion,
	})
	if err != nil {
		log.Fatalf("Cannot render the public site: %v", err)
	}
	// "/{$}" is the root and only the root: a bare "/" would answer every unknown path with the home page
	http.HandleFunc("/{$}", site.Page("home"))
	http.HandleFunc("/privacy", site.Page("privacy"))
	http.HandleFunc("/terms", site.Page("terms"))
	http.HandleFunc("/delete-account", site.Page("delete-account"))
	for alias, to := range map[string]string{
		"/privacy/": "/privacy", "/privacy-policy": "/privacy",
		"/terms/": "/terms", "/terms-of-use": "/terms",
		"/delete-account/": "/delete-account", "/account-deletion": "/delete-account",
	} {
		http.HandleFunc(alias, webui.Redirect(to))
	}

	http.HandleFunc("/admin", webui.Page("admin.html"))
	http.HandleFunc("/admin/", webui.Redirect("/admin"))

	// ReadHeaderTimeout is the slowloris guard. **ReadTimeout and WriteTimeout are deliberately absent -
	// do not add them**: both budget the whole request, and a 6 MiB photo is over five minutes on 3G.
	// nginx bounds the body instead (client_body_timeout).
	//
	// behind a proxy the api listens on loopback only, or a caller could skip the proxy and write
	// X-Forwarded-For themselves.
	addr := ":" + port
	if ratelimit.TrustProxy() {
		addr = "127.0.0.1:" + port
	}
	srv := &http.Server{
		Addr:              addr,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	go func() {
		log.Printf("HTTP Server booting up on %s...", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Webserver failed to bind or handle connections: %v", err)
		}
	}()

	// one row per market per day, so the panel can draw what a basket cost last week
	go startBasketHistory(queries)

	waitForShutdown(srv, dbPool)

}

// startBasketHistory keeps `basket_history` current: one row per shop category per day.
//
// **the basket price is the one number here that cannot be recomputed** - shop_basket_index always
// answers about *now*. hourly rather than nightly, because the upsert is idempotent per (day,
// category) and a server restarted at the wrong moment would otherwise skip whole days.
func startBasketHistory(queries *db.Queries) {
	record := func() {
		// an unrecovered panic in a goroutine takes the whole process with it, api included
		defer func() {
			if problem := recover(); problem != nil {
				log.Printf("CRITICAL: panic recording basket history: %v\n%s", problem, debug.Stack())
			}
		}()

		ctx, cancel := dbctx.WithTimeout(context.Background())
		defer cancel()
		if err := queries.RecordBasketHistory(ctx); err != nil {
			log.Printf("WARNING: could not record today's basket history: %v", err)
		}
	}

	// once at boot, so a fresh deploy has today's row without waiting an hour for it
	record()

	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for range ticker.C {
		record()
	}
}

// mustOpenCodeSender picks who delivers login codes. the console default keeps a laptop with an empty
// .env working; a *half-filled* provider is fatal (verify.New), because printing everybody's codes
// into a production log is the worst outcome available. the second return is whether a send costs
// money, which is what arms the per-phone budget.
func mustOpenCodeSender() (verify.Sender, bool) {
	sender, kind, err := verify.New(verify.SettingsFromEnv())
	if err != nil {
		log.Fatalf("Cannot configure the login code sender: %v", err)
	}

	switch kind {
	case verify.KindConsole:
		log.Printf("WARNING: login codes are NOT being delivered - they are printed into this log. "+
			"Set %s before anyone outside this machine tries to sign in.", verify.EnvTelegramToken)
		return sender, false
	default:
		log.Printf("Login codes: %s", kind)
		return sender, true
	}
}

// **the policy's date and the support address have to match the app's copy** (privacy_policy.dart):
// two copies of one document that disagree read as two different policies.
const (
	policyVersion = "2026-11-06"
	termsVersion  = "2026-10-08"
	supportEmail  = "domix.support@gmail.com"
)

// the one account Google's reviewer signs in with: without it the review stops on the login screen,
// because the code goes to a Telegram account the reviewer does not have, and an app that cannot be
// opened is refused as broken.
//
// **a half-filled configuration is fatal rather than ignored**: one variable set reads as armed in the
// deployment and behaves as unarmed on the phone. **unset both once the review is over.**
func mustReadReviewAccount() (phone, code string) {
	phone = strings.TrimSpace(os.Getenv("PLAY_REVIEW_PHONE"))
	code = strings.TrimSpace(os.Getenv("PLAY_REVIEW_CODE"))
	if phone == "" && code == "" {
		return "", ""
	}
	if phone == "" || code == "" {
		log.Fatalf("PLAY_REVIEW_PHONE and PLAY_REVIEW_CODE have to be set together, or neither")
	}

	// canonical, because that is what pending codes are keyed by: any other spelling arms an account
	// nobody can reach
	canonical, ok := auth.CanonicalPhone(phone)
	if !ok {
		log.Fatalf("PLAY_REVIEW_PHONE is not an uzbek phone number")
	}
	// the app's keypad accepts exactly this shape, so anything else is a code that cannot be typed
	if len(code) != auth.CodeLength || strings.ContainsFunc(code, func(r rune) bool { return r < '0' || r > '9' }) {
		log.Fatalf("PLAY_REVIEW_CODE has to be exactly %d digits", auth.CodeLength)
	}

	log.Printf("Play review account is ARMED for %s - its code is fixed and never delivered. "+
		"Unset PLAY_REVIEW_PHONE and PLAY_REVIEW_CODE once the review is over.", auth.MaskPhone(canonical))
	return canonical, code
}

// both yandex keys or no boot: without them every shop created gets an error for an address.
func mustOpenAddressSearch(queries *db.Queries) *geo.Service {
	service, err := geo.New(geo.SettingsFromEnv(), geo.NewDailyQuota(queries))
	if err != nil {
		log.Fatalf("Cannot configure address search: %v - set %s and %s", err, geo.EnvGeocoderKey, geo.EnvSuggestKey)
	}
	log.Printf("Address search: yandex geocoder and geosuggest, %d calls a day each", geo.DailyCap)
	return service
}

// reads product_templates into internal/catalog's in-memory copy, or dies trying.
func mustLoadTemplates(queries *db.Queries) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	rows, err := queries.ListProductTemplates(ctx)
	if err != nil {
		log.Fatalf("Cannot read product_templates: %v", err)
	}
	if len(rows) == 0 {
		log.Fatal("product_templates is empty - every new shop would be created with an empty catalogue.")
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

	sizes := make([]string, 0, len(catalog.AllShopCategories))
	for _, category := range catalog.AllShopCategories {
		sizes = append(sizes, fmt.Sprintf("%s=%d", category, catalog.Size(string(category))))
	}
	log.Printf("Loaded %d product template rows (%s)", len(rows), strings.Join(sizes, ", "))
}

func mustConnectDB(dbURL string) *pgxpool.Pool {
	config, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		log.Fatalf("Invalid DB_URL: %v", err)
	}

	config.MaxConns = envInt("DB_MAX_CONNS", 10)
	config.MinConns = envInt("DB_MIN_CONNS", 2)
	config.MaxConnLifetime = time.Hour
	config.MaxConnIdleTime = 30 * time.Minute
	config.HealthCheckPeriod = time.Minute

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		log.Fatalf("Unable to create database connection pool: %v", err)
	}

	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("Database connection check failed (Ping): %v", err)
	}
	log.Printf("Successfully established secure connection pool with PostgreSQL! (max_conns=%d, min_conns=%d)", config.MaxConns, config.MinConns)

	return pool
}

func envInt(key string, def int32) int32 {
	raw := os.Getenv(key)
	if raw == "" {
		return def
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return def
	}
	return int32(n)
}

func productImagesDir() string {
	if dir := os.Getenv("IMAGES_DIR"); dir != "" {
		return dir
	}
	return filepath.Join("..", "images")
}

// **storage and urls are two settings that have to agree**: photos in a bucket with urls pointing at
// local disk is a server whose /health is green and whose every product tile is blank. so it refuses
// to boot.
func mustOpenPhotoStorage() (imagestore.Storage, imagestore.URLs) {
	urls := imagestore.NewURLs(os.Getenv("IMAGE_BASE_URL"))

	r2cfg, wanted, err := imagestore.R2ConfigFromEnv()
	if err != nil {
		// a partly-filled .env: falling back to disk would lose every photo on the next redeploy
		log.Fatalf("Cannot configure photo storage: %v", err)
	}

	if !wanted {
		// created at boot, not on the first upload: a directory the process cannot write is a
		// misconfigured deployment, and this is the right moment to find out
		disk, err := imagestore.NewDisk(productImagesDir())
		if err != nil {
			log.Fatalf("Cannot prepare the product photo directory: %v", err)
		}
		log.Printf("Product photos: %s", disk.Describe())
		if urls.Configured() {
			// legitimate: nginx or a CDN serving the same directory under its own hostname
			log.Printf("Product photo urls: %s", urls.Master("<path>"))
		}
		return disk, urls
	}

	if !urls.Configured() {
		log.Fatalf("R2 is configured but IMAGE_BASE_URL is not - photos would be written to the "+
			"bucket %q and served from this api's own /images/, which does not have them. "+
			"Set IMAGE_BASE_URL to the bucket's public hostname (https://img.domix-api.uz).", r2cfg.Bucket)
	}

	bucket, err := imagestore.NewR2(r2cfg)
	if err != nil {
		log.Fatalf("Cannot configure R2: %v", err)
	}
	log.Printf("Product photos: %s", bucket.Describe())
	log.Printf("Product photo urls: %s", urls.Master("<path>"))
	return bucket, urls
}

func staticFiles(prefix, dir string) http.Handler {
	if _, err := os.Stat(dir); err != nil {
		log.Printf("WARNING: product images directory %q is unreadable (%v) - photos will 404", dir, err)
	} else {
		log.Printf("Serving product images from %s at %s", dir, prefix)
	}

	files := http.StripPrefix(prefix, http.FileServer(noListing{http.Dir(dir)}))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// load-bearing: without it a 100-tile grid re-downloads ~4 MB every time it is scrolled back
		// to. safe because a replaced upload gets a new random name (imagestore.Save).
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		files.ServeHTTP(w, r)
	})
}

// noListing is http.Dir with directories hidden: http.FileServer renders an index for any directory it
// can open, handing anybody who guessed the path a list of every uploaded photo in the market.
type noListing struct{ dir http.Dir }

func (n noListing) Open(name string) (http.File, error) {
	file, err := n.dir.Open(name)
	if err != nil {
		return nil, err
	}
	info, err := file.Stat()
	if err != nil {
		file.Close()
		return nil, err
	}
	if info.IsDir() {
		file.Close()
		return nil, os.ErrNotExist
	}
	return file, nil
}

// a load balancer hits /health to decide whether this instance can serve traffic
func healthCheck(dbPool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		if err := dbPool.Ping(ctx); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte("database unreachable"))
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	}
}

// finishes the in-flight requests and closes the pool instead of everything being killed mid-request
func waitForShutdown(srv *http.Server, dbPool *pgxpool.Pool) {
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("Shutdown signal received, finishing in-flight requests...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("HTTP server did not shut down cleanly: %v", err)
	}

	dbPool.Close()
	log.Println("Shutdown complete.")
}
