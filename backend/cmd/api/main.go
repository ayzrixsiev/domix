package main

import (
	"log"
	"net/http"
	"os"

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

	// verification
	if port == "" {
		port = "8080"
	}

	if botToken == "" || webhookURL == "" {
		log.Fatal("Critical Error: TELEGRAM_BOT_TOKEN and WEBHOOK_URL environment variables must be configured")
	}



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

	// create HTTP listener using background thread (goroutine) and start accepting connection request
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

        // step 1: user sent the initial "/start" command
        if update.Message.Text == "/start" {
            promptText := "Пожалуйста, поделитесь своим номером телефона для регистрации.\nRo'yxatdan o'tish uchun telefon raqamingizni ulashing."
            reply := tgbotapi.NewMessage(update.Message.Chat.ID, promptText)
            
            // native telegram button that requests their cryptographically verified contact card
            contactButton := tgbotapi.NewKeyboardButtonContact("📱 Поделиться номером / Raqamni ulashish")
            
            // build the keyboard grid layout containing our button row
            keyboard := tgbotapi.NewReplyKeyboard(tgbotapi.NewKeyboardButtonRow(contactButton))
            keyboard.ResizeKeyboard = true // makes the button compact instead of massive
            keyboard.OneTimeKeyboard = true // automatically collapses the layout view after use
            
            reply.ReplyMarkup = keyboard
            
            if _, err := bot.Send(reply); err != nil {
                log.Printf("Error sending contact prompt layout: %v", err)
            }
            continue // instantly proceed to wait for the next webhook update
        }

        // step 2: user clicked our "Share Contact" native button
        if update.Message.Contact != nil {
            // securely intercept their real phone number from Telegram's cryptographically verified payload
            log.Printf("--- PHONE NUMBER RECEIVED --- User: %s, Phone: %s", 
                update.Message.From.UserName, 
                update.Message.Contact.PhoneNumber,
            )

            localizedResponse := "Вы успешно зарегистрированы!\nSiz muvaffaqiyatli ro'yxatdan o'tdingiz!"
            reply := tgbotapi.NewMessage(update.Message.Chat.ID, localizedResponse)
            
            // clean up the UI: Remove the custom sharing button from the user's chat screen layout
            reply.ReplyMarkup = tgbotapi.NewRemoveKeyboard(true)

            if _, err := bot.Send(reply); err != nil {
                log.Printf("Error encountered sending network registration reply: %v", err)
            }
            continue // successfully handled, wait for next user action
        }

        // ROUTE 3: Fallback safety net — Ignore or reject all other unhandled messaging variants
        log.Printf("[%s] Ignored incoming text interaction: %s", update.Message.From.UserName, update.Message.Text)
    }

}