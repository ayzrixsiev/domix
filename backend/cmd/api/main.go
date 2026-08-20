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

	// 2b. load the product templates into memory.
	//
	// they live in `product_templates` since migration 000014 so the admin panel can edit them, but
	// nothing reads that table per request: it is read once here and again whenever an admin saves,
	// which is what keeps catalog.Template() a map lookup inside the shop-creation transaction and
	// catalog.IsOwnerNamedSlot() a map lookup on every product in every response.
	//
	// **an empty result is fatal, not a warning.** an api serving requests with no templates would
	// create shops with empty catalogues, and an empty catalogue is indistinguishable from one whose
	// owner has not started - it corrupts data quietly instead of failing loudly. the usual cause is
	// migration 000014 not having been run.
	mustLoadTemplates(queries)







	// 3. initialize telegram bot api
	bot, err := tgbotapi.NewBotAPI(botToken)
	if err != nil {
		log.Fatalf("Failed to connect to the bot: %v", err)
	}
	log.Printf("Authorized successfully on account: %s", bot.Self.UserName)







	// 4. initialize session manager
	sessionMgr := auth.NewSessionManager()

	// 5. wire up http routes - this section's job is just plugging dependencies into each endpoint
	// the actual handler logic lives in api/endpoints
	//
	// two rate limiters, because the two halves of the api are abused differently.
	//
	// `loginLimiter` guards the unauthenticated handshake. /api/auth/status is polled by the app
	// every ~2s (0.5 req/s) for up to two minutes, so the sustained rate has to stay above that -
	// but a caller trying to guess session ids wants thousands per second, and 1/s ends that. the
	// burst of 30 covers an app that reconnects and catches up.
	//
	// `apiLimiter` is the general ceiling: generous enough that no honest screen ever meets it (the
	// busiest, the home screen, makes one request), low enough to stop a loop hammering the database.
	//
	// idle callers are forgotten after 10 minutes so the limiter's own map cannot grow without bound.
	//
	// `uploadLimiter` is per *account* rather than per address (see Products.allowUpload): one photo
	// costs a decode and a re-encode, which is a different unit of work from a read, and staff on
	// one office wifi share an IP while one phone changes IP between cells. 1/s with a burst of 20
	// is far above an owner photographing a catalogue by hand and far below a script.
	loginLimiter := ratelimit.New(1, 30, 10*time.Minute)
	apiLimiter := ratelimit.New(20, 60, 10*time.Minute)
	uploadLimiter := ratelimit.New(1, 20, 30*time.Minute)

	authEndpoints := &endpoints.Auth{Queries: queries, SessionMgr: sessionMgr, BotUsername: bot.Self.UserName}
	http.HandleFunc("/api/auth/init", endpoints.WithCORS("POST", loginLimiter.Wrap(authEndpoints.Init)))
	http.HandleFunc("/api/auth/status", endpoints.WithCORS("GET", loginLimiter.Wrap(authEndpoints.Status)))
	// the app's own account: GET is "is this session still real, and who am I now", checked on launch
	// and on every return to the foreground; DELETE destroys it, which Google Play requires every app
	// with accounts to offer from inside the app. both are the caller acting on their own row, so one
	// RequireAuth covers the pair and RouteMe splits them by method.
	//
	// on the general limiter, not the login one: a signed-in app calls GET routinely, where the login
	// endpoints are the ones a stranger hammers.
	http.HandleFunc("/api/me", endpoints.WithCORS("GET, DELETE", apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, authEndpoints.RouteMe))))

	// the /delete-account page's two calls. the same handshake as login - a random session id, a
	// t.me deep link, a contact shared in the chat - ending in DELETE rather than a token, which is
	// why they sit on the same limiter: /status is polled every couple of seconds by a browser
	// exactly as the app polls /api/auth/status, and both are unauthenticated by necessity.
	deletionEndpoints := &endpoints.AccountDeletion{SessionMgr: sessionMgr, BotUsername: bot.Self.UserName}
	http.HandleFunc("/api/account-deletion/init", endpoints.WithCORS("POST", loginLimiter.Wrap(deletionEndpoints.Init)))
	http.HandleFunc("/api/account-deletion/status", endpoints.WithCORS("GET", loginLimiter.Wrap(deletionEndpoints.Status)))

	shopsEndpoints := &endpoints.Shops{Pool: dbPool, Queries: queries, JWTSecret: jwtSecret}
	http.HandleFunc("/api/shops", endpoints.WithCORS("GET, POST", apiLimiter.Wrap(shopsEndpoints.Route)))
	http.HandleFunc("/api/shops/mine", endpoints.WithCORS("GET", apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, shopsEndpoints.ListMine))))
	http.HandleFunc("/api/shops/{id}", endpoints.WithCORS("PUT, DELETE", apiLimiter.Wrap(shopsEndpoints.RouteByID)))

	// the uploads directory is created here rather than on the first upload: a directory the process
	// cannot write is a misconfigured deployment, and the right time to find that out is at boot
	// rather than from the first shop owner who presses "добавить фото".
	productImages, err := imagestore.New(productImagesDir())
	if err != nil {
		log.Fatalf("Cannot prepare the product photo directory: %v", err)
	}
	log.Printf("Storing uploaded product photos in %s", productImages.Dir())

	productsEndpoints := &endpoints.Products{
		Queries:   queries,
		JWTSecret: jwtSecret,
		Images:    productImages,
		Uploads:   uploadLimiter,
	}
	http.HandleFunc("/api/shops/{id}/products", endpoints.WithCORS("GET, POST", apiLimiter.Wrap(productsEndpoints.RouteByShop)))
	http.HandleFunc("/api/products/{id}", endpoints.WithCORS("PUT, DELETE", apiLimiter.Wrap(productsEndpoints.RouteByID)))
	// registered as its own pattern rather than folded into RouteByID: go's mux matches the more
	// specific pattern, and the two carry different bodies (multipart here, json there) and
	// different limits.
	http.HandleFunc("/api/products/{id}/image", endpoints.WithCORS("POST, DELETE", apiLimiter.Wrap(productsEndpoints.RouteImage)))

	homeEndpoints := &endpoints.Home{Queries: queries}
	http.HandleFunc("/api/home", endpoints.WithCORS("GET", apiLimiter.Wrap(homeEndpoints.Get)))
	http.HandleFunc("/api/categories/{code}/products", endpoints.WithCORS("GET", apiLimiter.Wrap(homeEndpoints.ProductsByCategory)))
	// the home screen's search field. public like the rest of Home, and on the same limiter - a
	// leading-wildcard ILIKE is the most expensive read in the api, so the 20-per-minute bucket is
	// doing real work here rather than being a formality.
	http.HandleFunc("/api/products/search", endpoints.WithCORS("GET", apiLimiter.Wrap(homeEndpoints.SearchProducts)))

	// the support inbox, the app's half. one path for both verbs because both act on the same thing
	// - the caller's own conversation - and neither takes an id: the thread is whoever RequireAuth
	// says is calling, so there is no parameter that could name somebody else's messages.
	supportEndpoints := &endpoints.Support{Queries: queries}
	http.HandleFunc("/api/support/messages", endpoints.WithCORS("GET, POST",
		apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, supportEndpoints.Route))))

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
	adminEndpoints := &endpoints.Admin{Pool: dbPool, Queries: queries}
	adminRoute := func(methods string, handler http.HandlerFunc) http.HandlerFunc {
		return endpoints.WithCORS(methods, apiLimiter.Wrap(
			auth.RequireAuth(jwtSecret, queries, adminEndpoints.RequireAdmin(handler)),
		))
	}
	http.HandleFunc("/api/admin/stats", adminRoute("GET", adminEndpoints.Stats))
	http.HandleFunc("/api/admin/anomalies", adminRoute("GET", adminEndpoints.Anomalies))

	http.HandleFunc("/api/admin/users", adminRoute("GET", adminEndpoints.ListUsers))
	http.HandleFunc("/api/admin/users/{id}", adminRoute("PUT, DELETE", adminEndpoints.RouteUser))

	http.HandleFunc("/api/admin/shops", adminRoute("GET", adminEndpoints.ListShops))
	http.HandleFunc("/api/admin/shops/{id}", adminRoute("PUT, DELETE", adminEndpoints.RouteShop))
	http.HandleFunc("/api/admin/shops/{id}/vip", adminRoute("PUT", adminEndpoints.SetVIP))
	http.HandleFunc("/api/admin/shops/{id}/products", adminRoute("GET", adminEndpoints.ListShopProducts))
	http.HandleFunc("/api/admin/products/{id}", adminRoute("PUT", adminEndpoints.UpdateProduct))

	// the support inbox, the privileged half. `{id}` is a *user* id and not a thread id - a thread is
	// exactly one user's messages, so there is no separate row to address.
	http.HandleFunc("/api/admin/support/threads", adminRoute("GET", adminEndpoints.SupportThreads))
	http.HandleFunc("/api/admin/support/threads/{id}", adminRoute("GET, POST", adminEndpoints.RouteSupportThread))

	// the templates themselves, editable since migration 000014 moved them out of Go and into
	// product_templates. every write here reloads internal/catalog's in-memory copy before it
	// answers, or the process would keep seeding shops from the list it started with.
	http.HandleFunc("/api/admin/templates", adminRoute("GET", adminEndpoints.Templates))
	http.HandleFunc("/api/admin/templates/{category}/items", adminRoute("GET, POST", adminEndpoints.RouteTemplateItems))
	// a separate path rather than /api/admin/templates/items/{id}: go's mux refuses to register that
	// alongside /templates/{category}/items, because "/templates/items/items" matches both - and it
	// refuses at startup rather than at request time, which is the right moment to find out.
	http.HandleFunc("/api/admin/template-items/{id}", adminRoute("PUT, DELETE", adminEndpoints.RouteTemplateItem))
	// the sync is the second, louder half: editing a template above decides what the *next* shop is
	// created with, this pushes it into the shops that already exist.
	http.HandleFunc("/api/admin/templates/{category}/sync", adminRoute("POST", adminEndpoints.SyncTemplate))

	http.Handle("/static/products/", staticFiles("/static/products/", productImagesDir()))
	http.HandleFunc("/health", healthCheck(dbPool))

	// the two web pages. neither goes through WithCORS - that wrapper sets Content-Type to
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
	srv := &http.Server{Addr: ":" + port}
	go func() {
		log.Printf("HTTP Server booting up on port %s...", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Webserver failed to bind or handle connections: %v", err)
		}
	}()

	telegramHandler := &telegram.Handler{Bot: bot, SessionMgr: sessionMgr, Queries: queries, JWTSecret: jwtSecret}
	go telegramHandler.ProcessUpdates(updates)







	// 8. block here until the os asks us to stop (ctrl+c locally, or however this
	// gets stopped in production), then shut down cleanly instead of being killed mid-request
	waitForShutdown(srv, dbPool)







}

// reads product_templates into internal/catalog's in-memory copy, or dies trying.
func mustLoadTemplates(queries *db.Queries) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	rows, err := queries.ListProductTemplates(ctx)
	if err != nil {
		log.Fatalf("Cannot read product_templates: %v (has migration 000014 been run?)", err)
	}
	if len(rows) == 0 {
		log.Fatal("product_templates is empty - every new shop would be created with an empty catalogue. Run `migrate -database \"$DB_URL\" -path db/migrations up`.")
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
