package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
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
	"domix/backend/internal/telegram"
	"domix/backend/internal/webui"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {







	// 1. loading env attributes
	if err := godotenv.Load("../.env"); err != nil {
		log.Println("WARNING: No .env file found")
	}

	botToken := os.Getenv("TELEGRAM_BOT_TOKEN")
	webhookURL := os.Getenv("WEBHOOK_URL")
	port := os.Getenv("PORT")
	jwtSecret := os.Getenv("JWT_SECRET")
	dbURL := os.Getenv("DB_URL")

	if port == "" {
		port = "8080"
	}
	if botToken == "" || webhookURL == "" || dbURL == "" {
		log.Fatal("Critical Error: TELEGRAM_BOT_TOKEN, WEBHOOK_URL, and DB_URL must be configured")
	}
	if jwtSecret == "" {
		log.Fatal("Critical error: jwtSercet is not configured")
	}







	// 2. postgresql connection pool (configured) set up and handed over to the Queries struct
	dbPool := mustConnectDB(dbURL)
	// and returned an address to it
	queries := db.New(dbPool)
	// loading templates from the db into golang map for fast look ups
	mustLoadTemplates(queries)







	// 3. initialize telegram bot api
	bot, err := tgbotapi.NewBotAPI(botToken)
	if err != nil {
		log.Fatalf("Failed to connect to the bot: %v", err)
	}
	log.Printf("Authorized successfully on account: %s", bot.Self.UserName)







	// 4. initialize session manager
	sessionMgr := auth.NewSessionManager()
	// and rate limiters
	loginLimiter := ratelimit.New(1, 30, 10*time.Minute)
	apiLimiter := ratelimit.New(20, 60, 10*time.Minute)
	uploadLimiter := ratelimit.New(1, 20, 30*time.Minute)







	// 5. wire up http routes - this section's job is just plugging dependencies into each endpoint
	authEndpoints := &endpoints.Auth{Queries: queries, SessionMgr: sessionMgr, BotUsername: bot.Self.UserName}
	http.HandleFunc("/api/auth/init", endpoints.WithJSON(loginLimiter.Wrap(authEndpoints.Init)))
	http.HandleFunc("/api/auth/status", endpoints.WithJSON(loginLimiter.Wrap(authEndpoints.Status)))
	http.HandleFunc("/api/me", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, authEndpoints.RouteMe))))

	deletionEndpoints := &endpoints.AccountDeletion{SessionMgr: sessionMgr, BotUsername: bot.Self.UserName}
	http.HandleFunc("/api/account-deletion/init", endpoints.WithJSON(loginLimiter.Wrap(deletionEndpoints.Init)))
	http.HandleFunc("/api/account-deletion/status", endpoints.WithJSON(loginLimiter.Wrap(deletionEndpoints.Status)))

	shopsEndpoints := &endpoints.Shops{Pool: dbPool, Queries: queries, JWTSecret: jwtSecret}
	http.HandleFunc("/api/shops", endpoints.WithJSON(apiLimiter.Wrap(shopsEndpoints.Route)))
	http.HandleFunc("/api/shops/mine", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, shopsEndpoints.ListMine))))
	http.HandleFunc("/api/shops/{id}", endpoints.WithJSON(apiLimiter.Wrap(shopsEndpoints.RouteByID)))

	// where product photos are written, and where the app is told to fetch them from. two
	// independent settings, decided together because getting one without the other is a server that
	// looks healthy and serves blank tiles - see mustOpenPhotoStorage.
	productImages, imageURLs := mustOpenPhotoStorage()

	productsEndpoints := &endpoints.Products{
		Queries:   queries,
		JWTSecret: jwtSecret,
		Images:    productImages,
		URLs:      imageURLs,
		Uploads:   uploadLimiter,
	}
	http.HandleFunc("/api/shops/{id}/products", endpoints.WithJSON(apiLimiter.Wrap(productsEndpoints.RouteByShop)))
	http.HandleFunc("/api/products/{id}", endpoints.WithJSON(apiLimiter.Wrap(productsEndpoints.RouteByID)))
	// registered as its own pattern rather than folded into RouteByID: go's mux matches the more
	// specific pattern, and the two carry different bodies (multipart here, json there) and
	// different limits.
	http.HandleFunc("/api/products/{id}/image", endpoints.WithJSON(apiLimiter.Wrap(productsEndpoints.RouteImage)))

	homeEndpoints := &endpoints.Home{Queries: queries, URLs: imageURLs}
	http.HandleFunc("/api/home", endpoints.WithJSON(apiLimiter.Wrap(homeEndpoints.Get)))
	http.HandleFunc("/api/categories/{code}/products", endpoints.WithJSON(apiLimiter.Wrap(homeEndpoints.ProductsByCategory)))
	// the home screen's search field. public like the rest of Home, and on the same limiter - a
	// leading-wildcard ILIKE is the most expensive read in the api, so the 20-per-minute bucket is
	// doing real work here rather than being a formality.
	http.HandleFunc("/api/products/search", endpoints.WithJSON(apiLimiter.Wrap(homeEndpoints.SearchProducts)))

	// the support inbox, the app's half. one path for both verbs because both act on the same thing
	// - the caller's own conversation - and neither takes an id: the thread is whoever RequireAuth
	// says is calling, so there is no parameter that could name somebody else's messages.
	supportEndpoints := &endpoints.Support{Queries: queries}
	http.HandleFunc("/api/support/messages", endpoints.WithJSON(apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, supportEndpoints.Route))))

	// the admin panel's api. every route here is the same three-layer chain, so it is built once
	// rather than typed five times - and building it once is also what stops the fourth route from
	// being the one that quietly forgets RequireAdmin.
	//
	// the order of the layers is load-bearing. RequireAuth proves who the caller is and puts their
	// id on the context; RequireAdmin reads that id and asks the database what role it holds *now*.
	// swapping them would have RequireAdmin looking for a user id nothing has put there yet, which
	// fails closed with a 401 rather than opening a hole - but only by luck, so keep the order.
	//
	// granting a VIP placement is still not an endpoint. that decision (§7 of CLAUDE.md) was about
	// the shape of the thing being granted, not about admin apis in general: a placement is sold,
	// and an api that can grant it is an api somebody will eventually ask to have pointed at their
	// own shop. deleting a user and deleting a shop are moderation, which is what a panel is for.
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
	http.HandleFunc("/api/admin/shops/{id}/products", adminRoute(adminEndpoints.ListShopProducts))
	http.HandleFunc("/api/admin/products/{id}", adminRoute(adminEndpoints.UpdateProduct))

	// the support inbox, the privileged half. `{id}` is a *user* id and not a thread id - a thread is
	// exactly one user's messages, so there is no separate row to address.
	http.HandleFunc("/api/admin/support/threads", adminRoute(adminEndpoints.SupportThreads))
	// DELETE erases the conversation from both sides at once - see Admin.DeleteSupportThread.
	http.HandleFunc("/api/admin/support/threads/{id}", adminRoute(adminEndpoints.RouteSupportThread))

	// the templates themselves, editable since migration 000014 moved them out of Go and into
	// product_templates. every write here reloads internal/catalog's in-memory copy before it
	// answers, or the process would keep seeding shops from the list it started with.
	http.HandleFunc("/api/admin/templates", adminRoute(adminEndpoints.Templates))
	http.HandleFunc("/api/admin/templates/{category}/items", adminRoute(adminEndpoints.RouteTemplateItems))
	// a separate path rather than /api/admin/templates/items/{id}: go's mux refuses to register that
	// alongside /templates/{category}/items, because "/templates/items/items" matches both - and it
	// refuses at startup rather than at request time, which is the right moment to find out.
	http.HandleFunc("/api/admin/template-items/{id}", adminRoute(adminEndpoints.RouteTemplateItem))
	// the sync is the second, louder half: editing a template above decides what the *next* shop is
	// created with, this pushes it into the shops that already exist.
	http.HandleFunc("/api/admin/templates/{category}/sync", adminRoute(adminEndpoints.SyncTemplate))

	// uploaded photos whose products row went away with a deleted shop. GET counts and measures,
	// DELETE sweeps - two verbs on one path because they are one question asked twice, and the
	// DELETE re-runs the whole scan rather than trusting a list the browser sent back.
	http.HandleFunc("/api/admin/storage/orphans", adminRoute(adminEndpoints.RouteOrphans))

	http.Handle("/static/products/", staticFiles("/static/products/", productImagesDir()))
	http.HandleFunc("/health", healthCheck(dbPool))

	// the two web pages. neither goes through WithJSON - that wrapper sets Content-Type to
	// application/json on everything it touches, which would make a browser download these instead
	// of rendering them.
	//
	// /delete-account is a Google Play requirement rather than a feature: an app that creates
	// accounts must publish a page describing deletion that works *without installing the app*, and
	// a listing without one is rejected at review. its url goes into the Play Console and into
	// support replies, so the aliases exist because those copies cannot be corrected later.
	//
	// the page *performs* the deletion rather than describing where to ask for one - see
	// endpoints.AccountDeletion. the address below is now only the way to reach a person when that
	// flow itself fails, which is the one thing a self-service page cannot cover.
	supportEmail := os.Getenv("SUPPORT_EMAIL")
	if supportEmail == "" {
		supportEmail = "support@domix.uz"
		log.Printf("WARNING: SUPPORT_EMAIL is not set - the account deletion page will show %q, which must be a mailbox that actually receives mail before submitting to Google Play", supportEmail)
	}
	deletionPage := webui.Page("delete-account.html", map[string]string{"SUPPORT_EMAIL": supportEmail})
	http.HandleFunc("/delete-account", deletionPage)
	http.HandleFunc("/delete-account/", webui.Redirect("/delete-account"))
	http.HandleFunc("/account-deletion", webui.Redirect("/delete-account"))

	http.HandleFunc("/admin", webui.Page("admin.html", nil))
	http.HandleFunc("/admin/", webui.Redirect("/admin"))







	// 6. webhook setup for telegram to talk
	wh, err := tgbotapi.NewWebhook(webhookURL)
	if err != nil {
		log.Fatalf("Failed to parse Webhook URL structure: %v", err)
	}

	if _, err = bot.Request(wh); err != nil {
		log.Fatalf("Telegram rejected setting this webhook endpoint: %v", err)
	}

	info, err := bot.GetWebhookInfo()
	if err != nil {
		log.Fatalf("Failed to pull webhook diagnostic info: %v", err)
	}
	if info.LastErrorDate != 0 {
		log.Printf("Warning: Telegram reported a previous webhook delivery failure: %s", info.LastErrorMessage)
	}

	// store here whatever we got from telegram webhook
	updates := bot.ListenForWebhook("/webhook")







	// 7. run the http server and the telegram update loop concurrently, each in its own
	// goroutine, so main() itself is free to just wait for a shutdown signal (step 8)
	//
	// every timeout field on http.Server defaults to zero, and zero means wait forever. exactly two
	// of the four are set here, and which two is the whole point:
	//
	// ReadHeaderTimeout is the slowloris guard. a connection that opens and then dribbles its headers
	// one byte at a time holds a goroutine and a file descriptor for as long as it likes; a few
	// thousand of them from one laptop take the server down at a few bytes per second, and the log
	// stays empty throughout because no request ever finished. a real client's headers are 200-400
	// bytes - a fraction of a second even on 2G - so ten seconds is twenty times the room an honest
	// phone needs and there is no grey area in between. ngrok happens to absorb this today, which
	// only means the mine goes off on the day we move to domix-api.uz (see the shipping-to-play skill).
	//
	// ReadTimeout and WriteTimeout are deliberately absent, and this comment matters more than the
	// code: both budget the *whole* request, body included. POST /api/products/{id}/image accepts up
	// to 6 MiB, which is over five minutes on 3G, so a whole-request limit would cut off photo upload
	// for precisely the owners with the worst connection and would never reproduce on a good one.
	// don't add them "for completeness" - that breaks photo upload.
	//
	// IdleTimeout only counts silence on an already-open keep-alive connection, so by definition it
	// cannot interrupt a request in flight. it does mean the server now closes idle sockets itself,
	// i.e. more of the "the phone's pool holds a dead socket" case - already handled on the client
	// side, where core/network/api_get.dart retries a GET once on a fresh connection.
	srv := &http.Server{
		Addr:              ":" + port,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	go func() {
		log.Printf("HTTP Server booting up on port %s...", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Webserver failed to bind or handle connections: %v", err)
		}
	}()

	telegramHandler := &telegram.Handler{Bot: bot, SessionMgr: sessionMgr, Queries: queries, JWTSecret: jwtSecret}
	go telegramHandler.ProcessUpdates(updates)

	// the third goroutine: one row per market per day, so the admin panel can draw what a basket
	// cost last week. see startBasketHistory.
	go startBasketHistory(queries)







	// 8. block here until the os asks us to stop (ctrl+c locally, or however this
	// gets stopped in production), then shut down cleanly instead of being killed mid-request
	waitForShutdown(srv, dbPool)







}

// startBasketHistory keeps `basket_history` current: one row per shop category per day.
//
// **It exists because the basket price is the one number in this product that cannot be recomputed.**
// `shop_basket_index` is a view over `products.price`, so it always answers about *now* - the moment
// an owner retypes a price, what their basket cost yesterday is gone and nothing anywhere remembers
// it. Every other figure on the admin dashboard is derived from current rows; "средний чек по
// категории за месяц" needs something to have been written down at the time.
//
// **Hourly, not nightly.** A daily job is one `time.Ticker` firing at whatever moment the process
// happened to start, so a server restarted around that time skips whole days and a laptop that is
// only on during the afternoon records nothing at all. The statement is an idempotent upsert keyed
// by (day, category), so running it twenty-four times a day writes the same rows the last of those
// runs would have written on its own - and today's point stays current to within the hour instead of
// being yesterday's until midnight.
//
// **The whole aggregate runs in the database** (RecordBasketHistory) - one statement over a view,
// nothing travelling through Go - which is what makes it cheap enough to put on a timer at all.
//
// A failure is logged and the loop continues: this is a chart, and a missing hour costs nothing that
// the next hour does not fix. It also deliberately does *not* take the shutdown path - there is no
// state to flush, and `dbPool.Close()` ending an in-flight upsert loses at most one hour of a
// number that is rewritten every hour anyway.
func startBasketHistory(queries *db.Queries) {
	record := func() {
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

	// create an empty ctx - context.Background(), use it as parent for the WithTimeout function
	// so the whole line means: "make a new context, based on the empty root context, that will automatically mark itself cancelled 5 seconds from now
	// and hand me both that context, and a way to cancel it myself early if I want to."
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel() // cancel the ctx if pool was created successfully

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

// it called twice in mustConnetcDB func, and provided twice with a key (string) and value (def int32)
// we check whether we have these two keys foncifgured inside env, if no we use the ones inside mustConnectDB
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
	if dir := os.Getenv("PRODUCT_IMAGES_DIR"); dir != "" {
		return dir
	}
	return filepath.Join("..", "photos")
}

// where product photos are stored, and what address the api tells the app to fetch them from.
//
// **Two settings, and they have to be decided together.** Storage is chosen by whether the R2 keys
// are in the environment; the address comes from IMAGE_BASE_URL. Neither can see the other's
// mistake, and the combination that is always wrong - photos written to a bucket while the api
// hands out urls pointing at its own disk - produces a server whose /health is green, whose uploads
// return 200, and whose every product tile is blank. That is a log line nobody reads at 2am, so it
// is a refusal to boot instead.
//
// The disk is not a fallback for a missing deployment: it is what runs on the founder's laptop and
// in every test, which is the whole argument for imagestore.Storage being an interface.
func mustOpenPhotoStorage() (imagestore.Storage, imagestore.URLs) {
	urls := imagestore.NewURLs(os.Getenv("IMAGE_BASE_URL"))

	r2cfg, wanted, err := imagestore.R2ConfigFromEnv()
	if err != nil {
		// a partly-filled .env. answering it by quietly writing photos onto the machine's disk gives
		// a server that works perfectly until it is redeployed, at which point every photo uploaded
		// since is gone - so this is fatal too.
		log.Fatalf("Cannot configure photo storage: %v", err)
	}

	if !wanted {
		// the uploads directory is created here rather than on the first upload: a directory the
		// process cannot write is a misconfigured deployment, and the right time to find that out is
		// at boot rather than from the first shop owner who presses "добавить фото".
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
			"bucket %q and served from this api's own /static/products/, which does not have them. "+
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
		// **load-bearing, not a nicety.** without it a 100-tile grid re-downloads roughly 4 MB every
		// time it is scrolled back to. safe because a photo's url is never reused: a replaced upload
		// gets a new random name (see imagestore.Save).
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		files.ServeHTTP(w, r)
	})
}

// noListing is http.Dir with directories hidden.
//
// http.FileServer renders an index page for any directory it can open, which was harmless while
// this served only catalogue photos and is not once owner uploads live under the same root: it would
// hand anybody who guessed the path a browsable index of every photo in the market. Returning
// "does not exist" for a directory is what turns that into a 404 - the file handling itself is
// untouched, including http.Dir's own refusal to serve a path that climbs out of the root.
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

// when main func runs it creates a channel and starts listening to an interrupt/terminate signal,
// and stops there, see: <-stop. it means no further code (http server and db pool shutdown), once it receives a signal
// it shuts the http server down cleanly (finishing in-flight requests instead of dropping them) and closes the db pool. without
// this, ctrl+c (or however this gets stopped in production) just kills everything mid-request.
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
