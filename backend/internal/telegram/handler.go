package telegram

import (
	"context"
	"errors"
	"log"
	"strings"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
	"github.com/jackc/pgx/v5"
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
	// a panic in a goroutine that nobody recovers takes down the *whole process*, not just that
	// goroutine - go has no per-goroutine crash isolation. this loop runs in its own goroutine
	// alongside the http server (see cmd/api/main.go step 7), so without this a single malformed
	// update from telegram would stop the api serving anyone. recovering here turns "the server is
	// down" into "one message was dropped and logged".
	defer func() {
		if r := recover(); r != nil {
			log.Printf("CRITICAL: panic while handling a telegram update: %v", r)
		}
	}()

	if update.Message == nil {
		return
	}

	// From is a *pointer and it is genuinely optional* - telegram leaves it nil for channel posts
	// and for messages from anonymous group admins. every branch below reads From.ID or
	// From.UserName, so without this guard one channel post is a nil dereference.
	if update.Message.From == nil {
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
	// the message *content* is deliberately not logged. this branch catches whatever a user typed
	// at the bot, which is arbitrary text they did not intend to publish - and the bot asks for a
	// phone number, so "whatever they typed" is quite often exactly that.
	log.Printf("chat %d: ignored an unrecognised text message", update.Message.Chat.ID)
}

// send wraps Bot.Send so a failed delivery is logged rather than dropped on the floor. every call
// site here used to discard the error, which meant a user whose message telegram refused simply saw
// nothing happen and there was no record of it anywhere.
func (h *Handler) send(msg tgbotapi.Chattable) {
	if _, err := h.Bot.Send(msg); err != nil {
		log.Printf("Error sending telegram message: %v", err)
	}
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
		h.send(tgbotapi.NewMessage(chatID, errorMsg))
		return
	}

	promptText := "Пожалуйста, поделитесь своим номером телефона для регистрации.\nRo'yxatdan o'tish uchun telefon raqamingizni ulashing."
	reply := tgbotapi.NewMessage(chatID, promptText)
	contactButton := tgbotapi.NewKeyboardButtonContact("📱 Поделиться номером / Raqamni ulashish")
	keyboard := tgbotapi.NewReplyKeyboard(tgbotapi.NewKeyboardButtonRow(contactButton))
	keyboard.ResizeKeyboard = true
	keyboard.OneTimeKeyboard = true
	reply.ReplyMarkup = keyboard

	h.send(reply)
}

func (h *Handler) handleContact(update tgbotapi.Update) {
	chatID := update.Message.Chat.ID
	contact := update.Message.Contact
	phone := contact.PhoneNumber

	// the phone number is this app's entire identity: `users.phone` is the unique key, and whoever
	// proves control of a number *is* that account. but the "share contact" button is not the only
	// way to send a Contact - telegram also lets you forward any entry from your address book, and
	// such a message arrives on this webhook looking almost identical.
	//
	// Contact.UserID is the telegram account the number belongs to, and it is 0 for an address-book
	// entry that isn't a telegram user. requiring it to equal the sender's own id is what makes this
	// a proof of ownership rather than a claim: without the check, anyone with a victim's number
	// saved in their contacts could log in as them by sharing that card, and the backend would hand
	// back a year-long jwt for the victim's account.
	if contact.UserID != update.Message.From.ID {
		log.Printf("SECURITY: chat %d shared a contact belonging to telegram user %d, not themselves (%d) - rejected",
			chatID, contact.UserID, update.Message.From.ID)
		errorMsg := "❌ Пожалуйста, поделитесь своим собственным номером, нажав кнопку ниже.\n\n❌ Iltimos, quyidagi tugma orqali o'z raqamingizni ulashing."
		h.send(tgbotapi.NewMessage(chatID, errorMsg))
		return
	}

	log.Printf("chat %d: contact received (%s)", chatID, maskPhone(phone))

	// pull the name and role the user typed into flutter
	_, name, requestedRole, exists := h.SessionMgr.GetPendingSession(chatID)
	if !exists {
		// if user sends contact after the session id already expired, tell them to redo it through the domix app
		log.Printf("Warning: Got contact for Chat %d, but no active RAM session was waiting! Rejecting to prevent orphaned DB entry.", chatID)
		errorMsg := "❌ Время сессии истекло. Пожалуйста, вернитесь в приложение Domix и нажмите кнопку входа снова.\n\n❌ Seans vaqti tugadi. Iltimos, Domix ilovasiga qaytib, kirish tugmasini qayta bosing."
		h.send(tgbotapi.NewMessage(chatID, errorMsg))
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
		// errors.Is against pgx's sentinel, not a substring match on the message text. the old
		// version compared err.Error() to "no rows in result set", which is wrong twice over: it
		// breaks silently if pgx ever rewords that string, and - worse - any *other* database error
		// whose text happened to contain "no rows" would be read as "this user doesn't exist" and
		// send us straight into CreateUser. every other handler in this codebase already does it
		// this way (see authz.go, product_crud.go); this was the one that didn't.
		if errors.Is(err, pgx.ErrNoRows) {
			log.Printf("chat %d: no account for %s, registering a new one", chatID, maskPhone(phone))

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
				h.send(tgbotapi.NewMessage(chatID, "Ошибка при регистрации. / Ro'yxatdan o'tishda xatolik."))
				return
			}
			finalUserID = newUser.ID
			finalRole = newUser.Role
		} else {
			log.Printf("Database lookup error: %v", err)
			return
		}
	} else {
		log.Printf("chat %d: account %s found, logging in", chatID, maskPhone(phone))
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

	h.send(reply)
}

// maskPhone turns "+998901234567" into "+998*****4567" for the log.
//
// A phone number is the identity key of this whole system - it is what a user is looked up by - so a
// log line containing one in full is a log line that leaks an account identifier to anyone who can
// read logs, which in production means a hosting provider and whatever aggregator sits in front of
// them. Enough digits are kept to match a line against a specific user when somebody reports a
// problem, which is the only reason the number was being logged at all.
func maskPhone(phone string) string {
	if len(phone) <= 8 {
		return "***"
	}
	return phone[:4] + strings.Repeat("*", len(phone)-8) + phone[len(phone)-4:]
}
