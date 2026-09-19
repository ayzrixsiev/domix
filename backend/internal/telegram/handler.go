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
//
// **This whole package is SUPERSEDED by the phone-code login** (endpoints.PhoneAuth, internal/auth
// code.go, internal/verify). It is kept only while the apk on the founder's phone still calls
// /api/auth/init; when that goes, this package, the bot wiring in cmd/api/main.go, the webhook and
// the TELEGRAM_BOT_TOKEN / WEBHOOK_URL settings all go with it - together, because the deletion page
// shares this same handshake and has to be moved to a code first (CLAUDE.md §3).
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

// sendFinal answers and takes the contact keyboard away with the message. every branch that ends a
// flow needs both, and a reply left with the keyboard still up invites the user to press it again
// against a session that no longer exists.
func (h *Handler) sendFinal(chatID int64, text string) {
	msg := tgbotapi.NewMessage(chatID, text)
	msg.ReplyMarkup = tgbotapi.NewRemoveKeyboard(true)
	h.send(msg)
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
		// deliberately says neither "the app" nor "the website": both flows land here, and by the
		// time a session is gone there is nothing left to say which one it was.
		errorMsg := "❌ Сессия истекла или не найдена. Пожалуйста, начните заново.\n\n❌ Seans muddati tugagan yoki topilmadi. Iltimos, qaytadan boshlang."
		h.sendFinal(chatID, errorMsg)
		return
	}

	// the same button collects the same contact either way, but one of these two flows deletes an
	// account - and asking for a number "for registration" one tap before destroying everything the
	// user owns would be a lie at the worst possible moment.
	promptText := "Пожалуйста, поделитесь своим номером телефона для регистрации.\nRo'yxatdan o'tish uchun telefon raqamingizni ulashing."
	buttonText := "📱 Поделиться номером / Raqamni ulashish"

	if _, session, ok := h.SessionMgr.PendingSession(chatID); ok && session.Purpose == auth.PurposeDeletion {
		promptText = "⚠️ Удаление аккаунта Domix.\nПодтвердите номер телефона кнопкой ниже. Аккаунт, магазины и товары будут удалены безвозвратно.\n\n⚠️ Domix hisobini o'chirish.\nQuyidagi tugma bilan telefon raqamingizni tasdiqlang. Hisob, do'konlar va mahsulotlar butunlay o'chiriladi."
		buttonText = "🗑 Подтвердить удаление / O'chirishni tasdiqlash"
	}

	reply := tgbotapi.NewMessage(chatID, promptText)
	contactButton := tgbotapi.NewKeyboardButtonContact(buttonText)
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

	// pull whatever this chat is in the middle of - the name and role typed into flutter, or the
	// number typed on the deletion page
	_, session, exists := h.SessionMgr.PendingSession(chatID)
	if !exists {
		// if user sends contact after the session id already expired, tell them to redo it through the domix app
		log.Printf("Warning: Got contact for Chat %d, but no active RAM session was waiting! Rejecting to prevent orphaned DB entry.", chatID)
		errorMsg := "❌ Время сессии истекло. Пожалуйста, начните заново.\n\n❌ Seans vaqti tugadi. Iltimos, qaytadan boshlang."
		h.sendFinal(chatID, errorMsg)
		return
	}

	// one handshake, two endings. the proof above is the same for both - this contact belongs to
	// whoever sent it - and from here they part company completely.
	if session.Purpose == auth.PurposeDeletion {
		h.handleDeletion(chatID, phone, session)
		return
	}

	name, requestedRole := session.Name, session.Role

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
				Role:  requestedRole,
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

// handleDeletion is the last step of deleting an account from the /delete-account web page: the
// number was typed in a browser, this is where it is proven and acted on.
//
// **two different questions have to be answered yes before a row goes.** the caller has already
// asked the first - is this contact the sender's own - which is what makes any of this a proof
// rather than a claim. the second is asked here: is it the *same* number that was typed on the
// page. without it the field on that page would be decorative, and someone typing a stranger's
// number would watch their own account disappear while believing they had deleted somebody else's.
//
// there is no confirmation step beyond the button itself. the page said what would be deleted, the
// bot said it again above the button, and a third "are you sure" inside a flow whose only purpose is
// deletion is a step people learn to tap through.
func (h *Handler) handleDeletion(chatID int64, phone string, session auth.SessionData) {
	if auth.NormalizePhone(phone) != session.Phone {
		// not logged with either number in it: this is the branch a mistyped digit reaches, and both
		// numbers here are somebody's personal data.
		log.Printf("chat %d: deletion refused, the shared contact is not the number typed on the page", chatID)
		h.SessionMgr.FinishDeletion(chatID, auth.DeletionMismatch)
		h.sendFinal(chatID, "❌ Этот номер не совпадает с номером, который вы ввели на сайте. Аккаунт не удалён — начните заново.\n\n❌ Bu raqam saytda kiritgan raqamingizga mos kelmadi. Hisob o'chirilmadi — qaytadan boshlang.")
		return
	}

	ctx, cancel := dbctx.WithTimeout(context.Background())
	defer cancel()

	// looked up by the raw number telegram sent, not by the normalized one, because that is exactly
	// how the row was written at registration (see handleContact above). normalizing here would be a
	// second, different idea of what this account's phone number is.
	user, err := h.Queries.GetUserByPhone(ctx, phone)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// safe to say out loud *here* and nowhere else: the person reading it has just proved
			// they own the number, so this tells them nothing they could not already find out.
			log.Printf("chat %d: nothing to delete, no account for this number", chatID)
			h.SessionMgr.FinishDeletion(chatID, auth.DeletionNoAccount)
			h.sendFinal(chatID, "На этот номер аккаунт Domix не зарегистрирован — удалять нечего.\n\nBu raqamga Domix hisobi ro'yxatdan o'tkazilmagan — o'chiradigan narsa yo'q.")
			return
		}
		log.Printf("CRITICAL: deletion lookup failed for chat %d: %v", chatID, err)
		h.SessionMgr.FinishDeletion(chatID, auth.DeletionFailed)
		h.sendFinal(chatID, "Не удалось выполнить запрос. Попробуйте позже.\n\nSo'rovni bajarib bo'lmadi. Keyinroq urinib ko'ring.")
		return
	}

	// one statement takes the account, its shops and their products - the schema cascades, and this
	// is the same query DELETE /api/me runs. see db/queries/users.sql.
	if err := h.Queries.DeleteUser(ctx, user.ID); err != nil {
		log.Printf("CRITICAL: failed to delete user %d: %v", user.ID, err)
		h.SessionMgr.FinishDeletion(chatID, auth.DeletionFailed)
		h.sendFinal(chatID, "Не удалось удалить аккаунт. Попробуйте позже.\n\nHisobni o'chirib bo'lmadi. Keyinroq urinib ko'ring.")
		return
	}

	// the id and nothing else, exactly as endpoints.DeleteMe logs it. every other field on that row
	// was the personal data the user just asked us to forget, and a log file is the one place nobody
	// goes back to clean.
	log.Printf("User %d deleted their account from the deletion page", user.ID)

	h.SessionMgr.FinishDeletion(chatID, auth.DeletionDone)
	h.sendFinal(chatID, "✅ Аккаунт Domix удалён вместе с магазинами и товарами. Восстановить его нельзя.\n\n✅ Domix hisobi do'konlar va mahsulotlar bilan birga o'chirildi. Uni tiklab bo'lmaydi.")
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
