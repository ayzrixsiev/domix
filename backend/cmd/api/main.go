package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/endpoints"
	"domix/backend/internal/ratelimit"
	"domix/backend/internal/telegram"

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





	// 3. initialize telegram bot api
	bot, err := tgbotapi.NewBotAPI(botToken)
	if err != nil {
		log.Fatalf("Failed to connect to the bot: %v", err)
	}
	// off unless asked for. Debug logs every update the bot receives in full, which in production is
	// a firehose containing users' phone numbers and names - the exact data that should not be
	// sitting in a log aggregator.
	bot.Debug = os.Getenv("TELEGRAM_DEBUG") == "true"
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
	loginLimiter := ratelimit.New(1, 30, 10*time.Minute)
	apiLimiter := ratelimit.New(20, 60, 10*time.Minute)

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

	shopsEndpoints := &endpoints.Shops{Pool: dbPool, Queries: queries, JWTSecret: jwtSecret}
	http.HandleFunc("/api/shops", endpoints.WithCORS("GET, POST", apiLimiter.Wrap(shopsEndpoints.Route)))
	http.HandleFunc("/api/shops/mine", endpoints.WithCORS("GET", apiLimiter.Wrap(auth.RequireAuth(jwtSecret, queries, shopsEndpoints.ListMine))))
	http.HandleFunc("/api/shops/{id}", endpoints.WithCORS("PUT, DELETE", apiLimiter.Wrap(shopsEndpoints.RouteByID)))

	productsEndpoints := &endpoints.Products{Queries: queries, JWTSecret: jwtSecret}
	http.HandleFunc("/api/shops/{id}/products", endpoints.WithCORS("GET, POST", apiLimiter.Wrap(productsEndpoints.RouteByShop)))
	http.HandleFunc("/api/products/{id}", endpoints.WithCORS("PUT, DELETE", apiLimiter.Wrap(productsEndpoints.RouteByID)))

	homeEndpoints := &endpoints.Home{Queries: queries}
	http.HandleFunc("/api/home", endpoints.WithCORS("GET", apiLimiter.Wrap(homeEndpoints.Get)))
	http.HandleFunc("/api/categories/{code}/products", endpoints.WithCORS("GET", apiLimiter.Wrap(homeEndpoints.ProductsByCategory)))
	// the home screen's search field. public like the rest of Home, and on the same limiter - a
	// leading-wildcard ILIKE is the most expensive read in the api, so the 20-per-minute bucket is
	// doing real work here rather than being a formality.
	http.HandleFunc("/api/products/search", endpoints.WithCORS("GET", apiLimiter.Wrap(homeEndpoints.SearchProducts)))

	// there is deliberately no admin route here. granting a VIP placement is done with SQL against
	// the database by whoever runs Domix - see §7 of CLAUDE.md for the statement. an admin *api*
	// would need an admin role, and a role that can be requested over the network is a role somebody
	// will eventually request; the founder is building a separate admin panel instead.

	http.Handle("/static/products/", staticFiles("/static/products/", productImagesDir()))
	http.HandleFunc("/health", healthCheck(dbPool))

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

	files := http.StripPrefix(prefix, http.FileServer(http.Dir(dir)))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		files.ServeHTTP(w, r)
	})
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
