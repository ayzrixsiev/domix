package telegram

import (
	"context"
	"log"
	"strings"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
)

// processes updates arriving from the telegram bot webhook: linking a flutter login session to
// the chat that pressed /start, then completing that login once the user shares their phone number
type Handler struct {
	Bot        *tgbotapi.BotAPI
	SessionMgr *auth.SessionManager
	Queries    *db.Queries
	JWTSecret  string
}

// blocks forever, processing one update at a time - meant to be run in its own goroutine
func (h *Handler) ProcessUpdates(updates tgbotapi.UpdatesChannel) {
	for update := range updates {
		h.handleUpdate(update)
	}
}

func (h *Handler) handleUpdate(update tgbotapi.Update) {
	if update.Message == nil {
		return
	}

	// step 1: user pressed /start via flutter's deep link
	if strings.HasPrefix(update.Message.Text, "/start") {
		h.handleStart(update.Message.Chat.ID, update.Message.Text)
		return
	}

	// step 2: user clicked "share contact"
	if update.Message.Contact != nil {
		h.handleContact(update)
		return
	}

	// step 3: fallback safety net
	log.Printf("[%s] Ignored incoming text interaction: %s", update.Message.From.UserName, update.Message.Text)
}

func (h *Handler) handleStart(chatID int64, text string) {
	parts := strings.Fields(text)

	// defensive guard: to see whether session id was sent inside telegram link
	linkSuccess := false

	if len(parts) > 1 { // if with session id link length will be 2
		sessionID := parts[1] // string like "sess_a1b2c3d4"

		// link this telegram chatid to the waiting created session ticket
		if h.SessionMgr.LinkChat(chatID, sessionID) {
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
		h.Bot.Send(tgbotapi.NewMessage(chatID, errorMsg))
		return
	}

	promptText := "Пожалуйста, поделитесь своим номером телефона для регистрации.\nRo'yxatdan o'tish uchun telefon raqamingizni ulashing."
	reply := tgbotapi.NewMessage(chatID, promptText)
	contactButton := tgbotapi.NewKeyboardButtonContact("📱 Поделиться номером / Raqamni ulashish")
	keyboard := tgbotapi.NewReplyKeyboard(tgbotapi.NewKeyboardButtonRow(contactButton))
	keyboard.ResizeKeyboard = true
	keyboard.OneTimeKeyboard = true
	reply.ReplyMarkup = keyboard

	h.Bot.Send(reply)
}

func (h *Handler) handleContact(update tgbotapi.Update) {
	chatID := update.Message.Chat.ID
	phone := update.Message.Contact.PhoneNumber

	log.Printf("--- PHONE NUMBER RECEIVED --- User: %s, Phone: %s", update.Message.From.UserName, phone)

	// pull the name and role the user typed into flutter
	_, name, requestedRole, exists := h.SessionMgr.GetPendingSession(chatID)
	if !exists {
		// if user sends contact after the session id already expired, tell them to redo it through the domix app
		log.Printf("Warning: Got contact for Chat %d, but no active RAM session was waiting! Rejecting to prevent orphaned DB entry.", chatID)
		errorMsg := "❌ Время сессии истекло. Пожалуйста, вернитесь в приложение Domix и нажмите кнопку входа снова.\n\n❌ Seans vaqti tugadi. Iltimos, Domix ilovasiga qaytib, kirish tugmasini qayta bosing."
		h.Bot.Send(tgbotapi.NewMessage(chatID, errorMsg))
		return
	}

	// default context with our modification applied to it for db queries (we added 5 seconds timer)
	// so that non of the connections gets stuck forever
	ctx, cancel := dbctx.WithTimeout(context.Background())
	defer cancel()

	var finalUserID int64
	var finalRole string

	// check user in database if already exists - login, if no - sign up
	existingUser, err := h.Queries.GetUserByPhone(ctx, phone)
	if err != nil {
		if err.Error() == "no rows in result set" || strings.Contains(err.Error(), "no rows") {
			log.Printf("User %s not found. Registering new account with custom name '%s'...", phone, name)

			newUser, createErr := h.Queries.CreateUser(ctx, db.CreateUserParams{
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
				h.Bot.Send(tgbotapi.NewMessage(chatID, "Ошибка при регистрации. / Ro'yxatdan o'tishda xatolik."))
				return
			}
			finalUserID = newUser.ID
			finalRole = newUser.Role
		} else {
			log.Printf("Database lookup error: %v", err)
			return
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

			updatedUser, updateErr := h.Queries.UpdateUserProfile(ctx, db.UpdateUserProfileParams{
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
	sessionID, _ := h.SessionMgr.CompleteSession(chatID, finalUserID, phone, finalRole, h.JWTSecret)
	log.Printf("Successfully unlocked Flutter session: %s for DB User ID: %d with Role: %s", sessionID, finalUserID, finalRole)

	localizedResponse := "Вы успешно зарегистрированы! Можете вернуться в приложение.\nSiz muvaffaqiyatli ro'yxatdan o'tdingiz! Ilovaga qaytishingiz mumkin."
	reply := tgbotapi.NewMessage(chatID, localizedResponse)
	reply.ReplyMarkup = tgbotapi.NewRemoveKeyboard(true)

	if _, err := h.Bot.Send(reply); err != nil {
		log.Printf("Error sending success reply: %v", err)
	}
}
