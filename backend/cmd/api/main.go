package main

import (
    "context"
    "encoding/json"
    "log"
    "net/http"
    "os"
    "strings"
    "time"

    "domix/backend/internal/auth"
    "domix/backend/db"

    tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
    "github.com/jackc/pgx/v5/pgtype"
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




    // 2. initialize postgresql connection pool
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    dbPool, err := pgxpool.New(ctx, dbURL)
    if err != nil {
        log.Fatalf("Unable to create database connection pool: %v", err)
    }
    defer dbPool.Close()

    if err := dbPool.Ping(ctx); err != nil {
        log.Fatalf("Database connection check failed (Ping): %v", err)
    }
    log.Println("Successfully established secure connection pool with PostgreSQL!")




    // 3. initialize telegram bot api
    bot, err := tgbotapi.NewBotAPI(botToken)
    if err != nil {
        log.Fatalf("Failed to connect to the bot: %v", err)
    }
    bot.Debug = true
    log.Printf("Authorized successfully on account: %s", bot.Self.UserName)




    // 4. initialize Session Manager
    sessionMgr := auth.NewSessionManager()


    // flutter will hit http endpoint to init. login session and send json with user's name and role
    http.HandleFunc("/api/auth/init", func(w http.ResponseWriter, r *http.Request) {

        // set up CORS permissions for two servers to talk
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        w.Header().Set("Content-Type", "application/json")

        // connection permission (flutter knocks to the door of golang)
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }

        var req struct {
            Name string `json:"name"`
            Role string `json:"role"`
        }
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            w.WriteHeader(http.StatusBadRequest)
            json.NewEncoder(w).Encode(map[string]string{"error": "invalid json body"})
            return
        }

        if req.Role != "shop_owner" && req.Role != "admin" {
            req.Role = "customer"
        }
        if req.Name == "" {
            req.Name = "Domix User"
        }

        // create session ticket with name, role and session id
        sessionID := sessionMgr.InitSession(req.Name, req.Role)

        w.WriteHeader(http.StatusOK)
        json.NewEncoder(w).Encode(map[string]string{
            "session_id": sessionID,
            // https://t.me/<bot>?start=<id> is telegram's documented deep-link format (unlike the unofficial tg:// scheme),
            // so mobile os link verification opens the app directly, and it still degrades gracefully to a web preview
            // instead of failing silently if telegram isn't installed or the client cold-starts and drops the param
            "telegram_url": "https://t.me/" + bot.Self.UserName + "?start=" + sessionID,
        })
    })

    // flutter will hit this http post to see the status of login state and get jwt token
    http.HandleFunc("/api/auth/status", func(w http.ResponseWriter, r *http.Request) {


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

        statusData := sessionMgr.GetStatus(sessionID)
        w.WriteHeader(http.StatusOK)
        json.NewEncoder(w).Encode(statusData)
    })


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

    // set up goroutine on a single http sever to listen both for flutter api and telegram webhook simultaneously
    go func() {
        log.Printf("HTTP Server booting up on port %s...", port)
        if err := http.ListenAndServe(":"+port, nil); err != nil {
            log.Fatalf("Webserver failed to bind or handle connections: %v", err)
        }
    }()

    // 7. telegram message processing loop
    for update := range updates {
        if update.Message == nil {
            continue
        }

        chatID := update.Message.Chat.ID
        text := update.Message.Text

        // step 1: user pressed /start via Flutter's deep link
        if strings.HasPrefix(text, "/start") {
            parts := strings.Fields(text)

            // defensive guard: to see whether session id was sent inside telegram link
            linkSuccess := false

            if len(parts) > 1 { // if with session id link length will be 2
                sessionID := parts[1] // string like "sess_a1b2c3d4"

                // link this Telegram ChatID to the waiting created session ticket
                if sessionMgr.LinkChat(chatID, sessionID) {
                    log.Printf("Successfully linked ChatID %d to waiting Session: %s", chatID, sessionID)
                    linkSuccess = true
                } else {
                    log.Printf("Warning: ChatID %d sent session %s, but it was expired or invalid", chatID, sessionID)
                }
            } else {
                log.Printf("User %d pressed /start directly without a Flutter link", chatID)
            }

            if !linkSuccess {
                errorMsg := "❌ Ошибка: сессия истекла или не найдена. Пожалуйста, запустите вход через приложение Domix.\n\n❌ Xatolik: seans muddati tugagan yoki topilmadi. Iltimos, kirishni Domix ilovasi orqali boshlang."
                bot.Send(tgbotapi.NewMessage(chatID, errorMsg))
                continue
            }

            promptText := "Пожалуйста, поделитесь своим номером телефона для регистрации.\nRo'yxatdan o'tish uchun telefon raqamingizni ulashing."
            reply := tgbotapi.NewMessage(chatID, promptText)
            contactButton := tgbotapi.NewKeyboardButtonContact("📱 Поделиться номером / Raqamni ulashish")
            keyboard := tgbotapi.NewReplyKeyboard(tgbotapi.NewKeyboardButtonRow(contactButton))
            keyboard.ResizeKeyboard = true
            keyboard.OneTimeKeyboard = true
            reply.ReplyMarkup = keyboard

            bot.Send(reply)
            continue
        }

        // step 2: user clicked "Share Contact"
        if update.Message.Contact != nil {
            phone := update.Message.Contact.PhoneNumber

            log.Printf("--- PHONE NUMBER RECEIVED --- User: %s, Phone: %s",
                update.Message.From.UserName,
                phone,
            )

            // pull the the name and role the user typed into flutter
            _, name, requestedRole, exists := sessionMgr.GetPendingSession(chatID)
            if !exists {
                // if user send account after session id already expired, we tell them to redo it through domix app 
                log.Printf("Warning: Got contact for Chat %d, but no active RAM session was waiting! Rejecting to prevent orphaned DB entry.", chatID)
                errorMsg := "❌ Время сессии истекло. Пожалуйста, вернитесь в приложение Domix и нажмите кнопку входа снова.\n\n❌ Seans vaqti tugadi. Iltimos, Domix ilovasiga qaytib, kirish tugmasini qayta bosing."
                bot.Send(tgbotapi.NewMessage(chatID, errorMsg))
                continue
            }

            queries := db.New(dbPool)
            var finalUserID int64
            var finalRole string

            // check user in database if already exists - login, if no - sign up
            existingUser, err := queries.GetUserByPhone(context.Background(), phone)
            if err != nil {
                if err.Error() == "no rows in result set" || strings.Contains(err.Error(), "no rows") {
                    log.Printf("User %s not found. Registering new account with custom name '%s'...", phone, name)

                    newUser, createErr := queries.CreateUser(context.Background(), db.CreateUserParams{
                        Name: pgtype.Text{
                            String: name, 
                            Valid:  name != "",
                        },
                        Phone: phone,
                        TelegramChatID: pgtype.Int8{
                            Int64: chatID, 
                            Valid: true,
                        },
                        Role: requestedRole,
                    })
                    if createErr != nil {
                        log.Printf("CRITICAL: Failed to register user: %v", createErr)
                        bot.Send(tgbotapi.NewMessage(chatID, "Ошибка при регистрации. / Ro'yxatdan o'tishda xatolik."))
                        continue
                    }
                    finalUserID = newUser.ID
                    finalRole = newUser.Role
                } else {
                    log.Printf("Database lookup error: %v", err)
                    continue
                }
            } else {
                log.Printf("User %s found. Logging in...", phone)
                finalUserID = existingUser.ID
                finalRole = existingUser.Role

                // role can only be upgraded customer -> shop_owner here (never demoted back down)
                roleChanged := existingUser.Role == "customer" && requestedRole == "shop_owner"
                // name can be updated either way, whenever what they typed this time differs from what's stored
                nameChanged := name != "" && name != existingUser.Name.String

                if roleChanged || nameChanged {
                    newRole := existingUser.Role
                    if roleChanged {
                        log.Printf("Upgrading user ID %d from customer to shop_owner", existingUser.ID)
                        newRole = "shop_owner"
                    }

                    newName := existingUser.Name.String
                    if nameChanged {
                        log.Printf("Updating name for user ID %d from %q to %q", existingUser.ID, existingUser.Name.String, name)
                        newName = name
                    }

                    updatedUser, updateErr := queries.UpdateUserProfile(context.Background(), db.UpdateUserProfileParams{
                        ID: existingUser.ID,
                        Name: pgtype.Text{
                            String: newName,
                            Valid:  newName != "",
                        },
                        TelegramChatID: pgtype.Int8{
                            Int64: chatID,
                            Valid: true,
                        },
                        Role: newRole,
                    })
                    if updateErr == nil {
                        finalRole = updatedUser.Role
                    }
                }
            }

            // mark session ticket as success and generate jwt token
			sessionID, _ := sessionMgr.CompleteSession(chatID, finalUserID, phone, finalRole, jwtSecret)
			log.Printf("Successfully unlocked Flutter session: %s for DB User ID: %d with Role: %s", sessionID, finalUserID, finalRole)

            localizedResponse := "Вы успешно зарегистрированы! Можете вернуться в приложение.\nSiz muvaffaqiyatli ro'yxatdan o'tdingiz! Ilovaga qaytishingiz mumkin."
            reply := tgbotapi.NewMessage(chatID, localizedResponse)
            reply.ReplyMarkup = tgbotapi.NewRemoveKeyboard(true)

            if _, err := bot.Send(reply); err != nil {
                log.Printf("Error sending success reply: %v", err)
            }
            continue
        }

        // step 3: fallback safety net
        log.Printf("[%s] Ignored incoming text interaction: %s", update.Message.From.UserName, update.Message.Text)
    }

}