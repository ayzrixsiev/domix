package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/endpoints"
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
	bot.Debug = true
	log.Printf("Authorized successfully on account: %s", bot.Self.UserName)




	// 4. initialize session manager
	sessionMgr := auth.NewSessionManager()

	


	// 5. wire up http routes - this section's job is just plugging dependencies into each endpoint
	// the actual handler logic lives in api/endpoints
	authEndpoints := &endpoints.Auth{SessionMgr: sessionMgr, BotUsername: bot.Self.UserName}
	http.HandleFunc("/api/auth/init", endpoints.WithCORS("POST", authEndpoints.Init))
	http.HandleFunc("/api/auth/status", endpoints.WithCORS("GET", authEndpoints.Status))

	shopsEndpoints := &endpoints.Shops{Queries: queries, JWTSecret: jwtSecret}
	http.HandleFunc("/api/shops", endpoints.WithCORS("GET, POST", shopsEndpoints.Route))
	http.HandleFunc("/api/shops/mine", endpoints.WithCORS("GET", auth.RequireAuth(jwtSecret, shopsEndpoints.ListMine)))

	productsEndpoints := &endpoints.Products{Pool: dbPool, Queries: queries, JWTSecret: jwtSecret}
	http.HandleFunc("/api/products/upload", endpoints.WithCORS("POST", auth.RequireAuth(jwtSecret, productsEndpoints.Upload)))

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
	config.MaxConnLifetime = time.Hour           // every connection that ahs been used longer than 1 hour should be cleaned
	config.MaxConnIdleTime = 30 * time.Minute    // every connection that was not used at all gets cleaned
	config.HealthCheckPeriod = time.Minute		 // every minute check on the connections and remove "bad" ones

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
