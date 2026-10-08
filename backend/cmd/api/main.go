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
	"domix/backend/internal/imagestore"
	"domix/backend/internal/ratelimit"
	"domix/backend/internal/verify"
	"domix/backend/internal/webui"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {

	// 1. loading env attributes
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

	// 2. postgresql connection pool (configured) set up and handed over to the Queries struct
	dbPool := mustConnectDB(dbURL)
	// and returned an address to it
	queries := db.New(dbPool)
	// loading templates from the db into golang map for fast look ups
	mustLoadTemplates(queries)

	// 3. login codes live in ram, never in the database (internal/auth/code.go). the sender is opened
	// first: it decides whether the send budgets are armed - the console sender is free.
	codeSender, paidDelivery := mustOpenCodeSender()
	reviewPhone, reviewCode := mustReadReviewAccount()
	codeMgr := auth.NewCodeManager(paidDelivery).WithReviewAccount(reviewPhone, reviewCode)

	// 4. rate limiters.
	//
	// **a signed-in caller is bucketed by account, everybody else by address** - see byCaller. every
	// number below is per bucket, and none of them is the thing protecting the code-sending bill:
	// that is the per-phone and daily budgets in auth.CodeManager, which no caller can spread around.
	byCaller := func(r *http.Request) string {
		if id, ok := auth.UserIDFromRequest(r, jwtSecret); ok {
			return "user:" + strconv.FormatInt(id, 10)
		}
		return "ip:" + ratelimit.ClientIP(r)
	}

	apiLimiter := ratelimit.New(20, 60, 10*time.Minute).Keyed(byCaller)
	uploadLimiter := ratelimit.New(1, 20, 30*time.Minute) // keyed by account inside Products.allowUpload

	// **the buckets below are by address, and an address is not a person here**: a whole mobile
	// carrier sits behind one, so anything public has to be loose enough that a crowd of honest
	// strangers never reaches it. they are floors against a flood, and the real bound on each of
	// these lives elsewhere - publicCache for the browsing reads, Home.SearchSlots for search, and
	// the per-phone and daily budgets for codes.
	publicLimiter := ratelimit.New(50, 200, 10*time.Minute)
	loginLimiter := ratelimit.New(5, 60, 10*time.Minute)
	searchLimiter := ratelimit.New(3, 30, 10*time.Minute)

	// the browsing reads - the home screen, the map, a category listing - held in memory for a few
	// seconds, which is what makes publicLimiter affordable at those numbers. see
	// endpoints.publicCache for what is in it and what deliberately is not.
	publicReads := endpoints.NewPublicCache(20 * time.Second)

	// tighter, because every call here can spend money: one address cannot walk through numbers
	// faster than this however many it has.
	codeLimiter := ratelimit.New(0.5, 10, 30*time.Minute)

	// 5. wire up http routes - this section's job is just plugging dependencies into each endpoint

	// the login: a code to the number, typed back, mints the jwt. request-code spends money so it
	// sits behind codeLimiter; verify only reads ram.
	phoneAuth := &endpoints.PhoneAuth{Queries: queries, Codes: codeMgr, Sender: codeSender, JWTSecret: jwtSecret}
	http.HandleFunc("/api/auth/request-code", endpoints.WithJSON(codeLimiter.Wrap(phoneAuth.RequestCode)))
	http.HandleFunc("/api/auth/verify", endpoints.WithJSON(loginLimiter.Wrap(phoneAuth.Verify)))

	// changing the number on an account that already exists: the same two steps and the same two
	// buckets, with RequireAuth on top because this edits an account rather than opening one.
	http.HandleFunc("/api/me/phone/request-code", endpoints.WithJSON(codeLimiter.Wrap(
		auth.RequireAuth(jwtSecret, queries, phoneAuth.RequestPhoneChangeCode))))
	http.HandleFunc("/api/me/phone/verify", endpoints.WithJSON(loginLimiter.Wrap(
		auth.RequireAuth(jwtSecret, queries, phoneAuth.VerifyPhoneChange))))

	authEndpoints := &endpoints.Auth{Queries: queries}
	http.HandleFunc("/api/me", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, authEndpoints.RouteMe))))

	// the /delete-account page Google Play requires: the same code, typed on a web page. public, so
	// request-code sits behind the money bucket exactly as the login's does.
	deletionEndpoints := &endpoints.AccountDeletion{Queries: queries, Codes: codeMgr, Sender: codeSender}
	http.HandleFunc("/api/account-deletion/request-code", endpoints.WithJSON(codeLimiter.Wrap(deletionEndpoints.RequestCode)))
	http.HandleFunc("/api/account-deletion/confirm", endpoints.WithJSON(loginLimiter.Wrap(deletionEndpoints.Confirm)))

	// **a path that answers a public GET and an authenticated write needs two buckets, not one.**
	// browsing has to survive a carrier's worth of strangers; creating a shop seeds a hundred rows in
	// a transaction and is metered per account. one limit for both would either throttle the crowd
	// or hand an account a hundred shops a second.
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

	// where photos are written and where the app fetches them from - two settings that have to
	// agree, see mustOpenPhotoStorage
	productImages, imageURLs := mustOpenPhotoStorage()

	productsEndpoints := &endpoints.Products{
		Queries:   queries,
		JWTSecret: jwtSecret,
		Images:    productImages,
		URLs:      imageURLs,
		Uploads:   uploadLimiter,
	}
	http.HandleFunc("/api/shops/{id}/products", endpoints.WithJSON(browse(productsEndpoints.RouteByShop)))
	http.HandleFunc("/api/products/{id}", endpoints.WithJSON(apiLimiter.Wrap(productsEndpoints.RouteByID)))
	// its own pattern rather than folded into RouteByID: a different body (multipart) and a
	// different limit
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
	// the one public read whose cost the caller chooses, so it is the one that is not cached: its own
	// bucket on top of the public one, and Home.SearchSlots underneath both.
	http.HandleFunc("/api/products/search", endpoints.WithJSON(publicLimiter.Wrap(searchLimiter.Wrap(homeEndpoints.SearchProducts))))

	// the heart on a product tile. authenticated throughout - a favourite belongs to an account.
	favoritesEndpoints := &endpoints.Favorites{Queries: queries, URLs: imageURLs}
	http.HandleFunc("/api/favorites", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, favoritesEndpoints.Route))))
	http.HandleFunc("/api/favorites/{id}", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, favoritesEndpoints.RouteByID))))

	// the admin api. one chain built once, so no route can quietly forget RequireAdmin. the order is
	// load-bearing: RequireAuth puts the caller's id on the context, RequireAdmin reads it.
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
	http.HandleFunc("/api/admin/shops/{id}/exclude", adminRoute(adminEndpoints.SetExcluded))
	http.HandleFunc("/api/admin/shops/{id}/products", adminRoute(adminEndpoints.ListShopProducts))
	http.HandleFunc("/api/admin/products/{id}", adminRoute(adminEndpoints.UpdateProduct))

	// the templates themselves, in product_templates. every write reloads internal/catalog's
	// in-memory copy, or the process keeps seeding shops from the list it booted with.
	http.HandleFunc("/api/admin/templates", adminRoute(adminEndpoints.Templates))
	http.HandleFunc("/api/admin/templates/{category}/items", adminRoute(adminEndpoints.RouteTemplateItems))
	// a separate path: go's mux refuses /templates/items/{id} alongside /templates/{category}/items
	http.HandleFunc("/api/admin/template-items/{id}", adminRoute(adminEndpoints.RouteTemplateItem))
	// editing a template decides what the next shop gets; the sync pushes it into existing shops
	http.HandleFunc("/api/admin/templates/{category}/sync", adminRoute(adminEndpoints.SyncTemplate))
	// a whole template pasted from a sheet: the difference first, the write only on apply
	http.HandleFunc("/api/admin/templates/{category}/import", adminRoute(adminEndpoints.ImportTemplate))
	// a curated photo, straight from the editor - the only way one enters images/shops/<category>/
	http.HandleFunc("/api/admin/catalogue/{category}/photo", adminRoute(adminEndpoints.UploadCataloguePhoto))

	// photos no row points at. GET measures, DELETE sweeps - owner uploads and the curated catalogue
	// through two separate doors, see sweepScope
	http.HandleFunc("/api/admin/storage/orphans", adminRoute(adminEndpoints.RouteOrphans))
	http.HandleFunc("/api/admin/storage/catalogue", adminRoute(adminEndpoints.RouteCatalogueFiles))

	http.Handle(imagestore.DefaultURLPrefix, staticFiles(imagestore.DefaultURLPrefix, productImagesDir()))
	http.HandleFunc("/health", healthCheck(dbPool))

	// the two web pages, deliberately not behind WithJSON - a json content type would make a browser
	// download them instead of rendering them. /delete-account is a Google Play requirement: its url
	// goes into the Play Console and into support replies, which is why the aliases exist.
	supportEmail := os.Getenv("SUPPORT_EMAIL")
	if supportEmail == "" {
		supportEmail = "domix.support@gmail.com"
		log.Printf("WARNING: SUPPORT_EMAIL is not set - the account deletion page will show %q, which must be a mailbox that actually receives mail before submitting to Google Play", supportEmail)
	}
	deletionPage := webui.Page("delete-account.html", map[string]string{"SUPPORT_EMAIL": supportEmail})
	http.HandleFunc("/delete-account", deletionPage)
	http.HandleFunc("/delete-account/", webui.Redirect("/delete-account"))
	http.HandleFunc("/account-deletion", webui.Redirect("/delete-account"))

	// the privacy policy, and it is a Play requirement for the same reason: the console wants a url
	// that opens without installing anything. **the same text lives in the app** - see
	// privacy_policy.dart - because it has to be readable and acceptable before an account exists.
	policyPage := webui.Page("privacy.html", map[string]string{
		"SUPPORT_EMAIL":  supportEmail,
		"POLICY_VERSION": policyVersion,
	})
	http.HandleFunc("/privacy", policyPage)
	http.HandleFunc("/privacy/", webui.Redirect("/privacy"))
	http.HandleFunc("/privacy-policy", webui.Redirect("/privacy"))

	http.HandleFunc("/admin", webui.Page("admin.html", nil))
	http.HandleFunc("/admin/", webui.Redirect("/admin"))

	// 6. run the http server in its own goroutine, so main() is free to wait for a shutdown signal
	//
	// ReadHeaderTimeout is the slowloris guard: a connection that dribbles its headers one byte at a
	// time holds a goroutine forever, and the log stays empty because no request ever finishes.
	//
	// **ReadTimeout and WriteTimeout are deliberately absent - do not add them.** both budget the
	// whole request, body included, and a 6 MiB photo is over five minutes on 3G: a whole-request
	// limit would break upload for exactly the owners with the worst connection. nginx bounds the
	// body instead (client_body_timeout, deploy/nginx.conf).
	//
	// behind a proxy the api listens on loopback only, or anybody could skip the proxy, write
	// X-Forwarded-For themselves and hand the rate limiter any address they liked.
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

	// the second goroutine: one row per market per day, so the admin panel can draw what a basket
	// cost last week. see startBasketHistory.
	go startBasketHistory(queries)

	// 7. block here until the os asks us to stop (ctrl+c locally, or however this
	// gets stopped in production), then shut down cleanly instead of being killed mid-request
	waitForShutdown(srv, dbPool)

}

// startBasketHistory keeps `basket_history` current: one row per shop category per day.
//
// **the basket price is the one number here that cannot be recomputed.** shop_basket_index always
// answers about *now*, so yesterday's total is gone the moment an owner retypes a price.
//
// hourly rather than nightly, because the upsert is idempotent per (day, category) and a server
// restarted at the wrong moment would otherwise skip whole days. a failure is logged and ignored.
func startBasketHistory(queries *db.Queries) {
	record := func() {
		// an unrecovered panic in a goroutine takes the *whole process* with it, api included. a
		// chart is not worth that, so this one dies alone and the next hour tries again.
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

// mustOpenCodeSender picks who delivers login codes, from the environment.
//
// the default is the console - a laptop with an empty .env still has a working login, printed into
// this log. a *half-filled* provider is fatal (verify.New), because quietly printing everybody's
// codes into a production log is the worst outcome available here.
//
// the second return is whether a send costs money, which is what arms the per-phone budget.
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

// the policy's own revision date. **it has to match privacy_policy.dart's policyVersion**: the two
// copies of this text are one document, and a page dated differently from the one in the app is the
// kind of detail a reviewer reads as two different policies.
const policyVersion = "2026-10-07"

// the one account Google's reviewer signs in with, read from the environment. Without it the review
// stops on the login screen: the code goes to Telegram, which a reviewer has no account on for the
// number they type, and an app that cannot be opened is refused as broken.
//
// **A half-filled configuration is the dangerous state**, so it is fatal rather than ignored: one
// variable set reads as armed in the deployment and behaves as unarmed on the phone, which is
// discovered by a rejection weeks later. The code is never logged; the number is masked.
//
// **Unset both once the review is over** - see auth.CodeManager.WithReviewAccount.
func mustReadReviewAccount() (phone, code string) {
	phone = strings.TrimSpace(os.Getenv("PLAY_REVIEW_PHONE"))
	code = strings.TrimSpace(os.Getenv("PLAY_REVIEW_CODE"))
	if phone == "" && code == "" {
		return "", ""
	}
	if phone == "" || code == "" {
		log.Fatalf("PLAY_REVIEW_PHONE and PLAY_REVIEW_CODE have to be set together, or neither")
	}

	// canonical, because that is what the pending codes are keyed by: a number stored in any other
	// spelling would arm an account nobody can reach
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

// connection pool configuration
func mustConnectDB(dbURL string) *pgxpool.Pool {
	config, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		log.Fatalf("Invalid DB_URL: %v", err)
	}

	config.MaxConns = envInt("DB_MAX_CONNS", 10) // max connections pool holds
	config.MinConns = envInt("DB_MIN_CONNS", 2)  // minimum ready to use connetion, avoid cold-start latency
	config.MaxConnLifetime = time.Hour           // every connection that has been used longer than 1 hour should be cleaned
	config.MaxConnIdleTime = 30 * time.Minute    // every connection that was not used at all gets cleaned
	config.HealthCheckPeriod = time.Minute       // every minute check on the connections and remove "bad" ones

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

// an int32 setting read from the environment, or the default when it is missing or unparseable
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

// where product photos are stored, and what address the api tells the app to fetch them from.
//
// **two settings that have to agree.** storage follows the R2 keys, the address follows
// IMAGE_BASE_URL, and the wrong pairing - photos in a bucket, urls pointing at local disk - is a
// server whose /health is green and whose every product tile is blank. so it refuses to boot.
func mustOpenPhotoStorage() (imagestore.Storage, imagestore.URLs) {
	urls := imagestore.NewURLs(os.Getenv("IMAGE_BASE_URL"))

	r2cfg, wanted, err := imagestore.R2ConfigFromEnv()
	if err != nil {
		// a partly-filled .env: falling back to local disk would lose every photo on the next redeploy
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

// check whether images folder available
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

// noListing is http.Dir with directories hidden: http.FileServer renders an index page for any
// directory it can open, which would hand anybody who guessed the path a browsable index of every
// uploaded photo in the market.
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

// load balaner will hit /health http enpoint to see whether this server's db connection is fine
// to decide whether it can route traffic here
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

// blocks until the os asks us to stop, then finishes the in-flight requests and closes the pool
// instead of everything being killed mid-request.
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
