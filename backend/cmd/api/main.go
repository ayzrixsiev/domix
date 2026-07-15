package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"

	"domix/internal/auth"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
	"github.com/joho/godotenv"
)

func main() {

	// load .env data
	if err := godotenv.Load("../.env"); err != nil {
		log.Println("Note: No .env file found, relying on system environment variables")
	}

	// fetch values from environment configuration
	botToken := os.Getenv("TELEGRAM_BOT_TOKEN")
	webhookURL := os.Getenv("WEBHOOK_URL")
	port := os.Getenv("PORT")
	jwtSecret := os.Getenv("JWT_SECRET")

	// verification
	if port == "" {
		port = "8080"
	}

	if botToken == "" || webhookURL == "" {
		log.Fatal("Critical Error: TELEGRAM_BOT_TOKEN and WEBHOOK_URL environment variables must be configured")
	}

	// initialize our SessionManager in ram
	sessionMgr := auth.NewSessionManager()

	// setup HTTP endpoint for flutter polling
	// this endpoint is registered on the default mux, sharing the same port as our webhook
	// flutter will call: GET /api/auth/status?session_id=session_89123
	http.HandleFunc("/api/auth/status", func(w http.ResponseWriter, r *http.Request) {
		// allow CORS so your Flutter mobile, desktop, or web client doesn't get blocked during testing
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Content-Type", "application/json")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		sessionID := r.URL.Query().Get("session_id")
		if sessionID == "" {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{"error": "missing session_id"})
			return
		}

		// ask our RAM engine how the login status is going
		statusData := sessionMgr.GetStatus(sessionID)
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(statusData)
	})

	// initializing bot api connection
	bot, err := tgbotapi.NewBotAPI(botToken)
	if err != nil {
		log.Fatalf("Failed to connect to the bot: %v", err)
	}

	// turning on logs in the terminal
	bot.Debug = true
	log.Printf("Authorized successfully on account: %s", bot.Self.UserName)

	// parse and register our endpoint URL directly with telegram's servers
	wh, err := tgbotapi.NewWebhook(webhookURL)
	if err != nil {
		log.Fatalf("Failed to parse Webhook URL structure: %v", err)
	}

	_, err = bot.Request(wh)
	if err != nil {
		log.Fatalf("Telegram rejected setting this webhook endpoint: %v", err)
	}

	// verify what telegram currently sees for troubleshooting diagnostic visibility
	info, err := bot.GetWebhookInfo()
	if err != nil {
		log.Fatalf("Failed to pull webhook diagnostic info: %v", err)
	}
	if info.LastErrorDate != 0 {
		log.Printf("Warning: Telegram reported a previous webhook delivery failure: %s", info.LastErrorMessage)
	}

	// when we receive smth from telegram, save here
	updates := bot.ListenForWebhook("/webhook")

	// create HTTP listener using background thread (goroutine) and start accepting connection requests
	// both our /webhook and your /api/auth/status routes are served simultaneously from this port
	go func() {
		log.Printf("HTTP Server booting up on port %s...", port)
		if err := http.ListenAndServe(":"+port, nil); err != nil {
			log.Fatalf("Webserver failed to bind or handle connections: %v", err)
		}
	}()

	// catches what we got in "updates" var and reacts
	for update := range updates {
		if update.Message == nil {
			continue
		}

		chatID := update.Message.Chat.ID
		text := update.Message.Text

		// step 1: user sent the initial "/start" command (or clicked start via a Deep Link)
		if strings.HasPrefix(text, "/start") {
			parts := strings.Fields(text) // splits "/start session_89123" into an array

			// check if flutter passed us a session ID parameter in the URL
			if len(parts) > 1 {
				sessionID := parts[1] // Extract "session_89123"
				sessionMgr.RegisterChat(chatID, sessionID)
				log.Printf("Linked ChatID %d to active Flutter Session: %s", chatID, sessionID)
			} else {
				log.Printf("User %d pressed /start directly without a Flutter session ID link", chatID)
			}

			promptText := "Пожалуйста, поделитесь своим номером телефона для регистрации.\nRo'yxatdan o'tish uchun telefon raqamingizni ulashing."
			reply := tgbotapi.NewMessage(chatID, promptText)

			// native telegram button that requests their cryptographically verified contact card
			contactButton := tgbotapi.NewKeyboardButtonContact("📱 Поделиться номером / Raqamni ulashish")

			// build the keyboard grid layout containing our button row
			keyboard := tgbotapi.NewReplyKeyboard(tgbotapi.NewKeyboardButtonRow(contactButton))
			keyboard.ResizeKeyboard = true   // makes the button compact instead of massive
			keyboard.OneTimeKeyboard = true  // automatically collapses the layout view after use

			reply.ReplyMarkup = keyboard

			if _, err := bot.Send(reply); err != nil {
				log.Printf("Error sending contact prompt layout: %v", err)
			}
			continue // instantly proceed to wait for the next webhook update
		}

		// step 2: user clicked our "Share Contact" native button
		if update.Message.Contact != nil {
			phone := update.Message.Contact.PhoneNumber

			// securely intercept their real phone number from Telegram's cryptographically verified payload
			log.Printf("--- PHONE NUMBER RECEIVED --- User: %s, Phone: %s",
				update.Message.From.UserName,
				phone,
			)

			// TODO: When we connect sqlc database actions, we will perform a postgres check here:
			// user, err := db.GetOrCreateUserByPhone(ctx, phone)
			// For testing right now, we will pass a hardcoded database ID of 1 so it compiles and generates real JWTs!
			var dummyUserID int64 = 1

			// call session manager to complete the handshake, signing a genuine JWT
			sessionID, err := sessionMgr.CompleteSession(chatID, dummyUserID, phone, "shop_owner", jwtSecret)
			if err == nil {
				log.Printf("Successfully unlocked Flutter session: %s for phone: %s", sessionID, phone)
			} else {
				log.Printf("Warning: Completed contact verification for ChatID %d but no active session was registered: %v", chatID, err)
			}

			localizedResponse := "Вы успешно зарегистрированы! Можете вернуться в приложение.\nSiz muvaffaqiyatli ro'yxatdan o'tdingiz! Ilovaga qaytishingiz mumkin."
			reply := tgbotapi.NewMessage(chatID, localizedResponse)

			// clean up the UI: remove the custom sharing button from the user's chat screen layout
			reply.ReplyMarkup = tgbotapi.NewRemoveKeyboard(true)

			if _, err := bot.Send(reply); err != nil {
				log.Printf("Error encountered sending network registration reply: %v", err)
			}
			continue // successfully handled, wait for next user action
		}

		// step 3: Fallback safety net — Ignore or reject all other unhandled messaging variants
		log.Printf("[%s] Ignored incoming text interaction: %s", update.Message.From.UserName, update.Message.Text)
	}

}