package endpoints

// what @domix_manager_bot says, in the language the session was started in. the bot never knows
// whether that was the app, the panel or the deletion page, so nothing here names one of them.
type botCopy struct {
	loginPrompt    string
	loginButton    string
	deletePrompt   string
	deleteButton   string
	signedIn       string
	deleted        string
	noAccount      string
	notYourContact string
	notUzbek       string
	expired        string
	startFromApp   string
	failed         string
}

var botCopies = map[string]botCopy{
	"ru": {
		loginPrompt:    "Чтобы войти в Domix, поделитесь номером телефона — нажмите кнопку ниже.",
		loginButton:    "📱 Поделиться номером",
		deletePrompt:   "⚠️ Удаление аккаунта Domix.\nПодтвердите номер кнопкой ниже. Аккаунт, магазины, товары и фотографии будут удалены безвозвратно.",
		deleteButton:   "🗑 Подтвердить удаление",
		signedIn:       "✅ Готово, вы вошли в Domix. Можно возвращаться.",
		deleted:        "✅ Аккаунт Domix удалён вместе с магазинами, товарами и фотографиями. Восстановить его нельзя.",
		noAccount:      "На этот номер аккаунт Domix не зарегистрирован — удалять нечего.",
		notYourContact: "❌ Нужен ваш собственный номер. Нажмите кнопку ниже, а не пересылайте контакт.",
		notUzbek:       "❌ Domix работает только с узбекскими номерами (+998).",
		expired:        "⌛ Время вышло или ссылка устарела. Начните заново там, где нажали кнопку.",
		startFromApp:   "Чтобы войти, откройте приложение Domix и нажмите «Зарегистрироваться через Telegram».",
		failed:         "Что-то пошло не так. Попробуйте ещё раз чуть позже.",
	},
	"uz": {
		loginPrompt:    "Domix'ga kirish uchun telefon raqamingizni ulashing — quyidagi tugmani bosing.",
		loginButton:    "📱 Raqamni ulashish",
		deletePrompt:   "⚠️ Domix akkauntini o‘chirish.\nQuyidagi tugma bilan raqamingizni tasdiqlang. Akkaunt, do‘konlar, mahsulotlar va suratlar butunlay o‘chiriladi.",
		deleteButton:   "🗑 O‘chirishni tasdiqlash",
		signedIn:       "✅ Tayyor, siz Domix'ga kirdingiz. Qaytishingiz mumkin.",
		deleted:        "✅ Domix akkaunti do‘konlar, mahsulotlar va suratlar bilan birga o‘chirildi. Uni tiklab bo‘lmaydi.",
		noAccount:      "Bu raqamga Domix akkaunti ro‘yxatdan o‘tmagan — o‘chiradigan narsa yo‘q.",
		notYourContact: "❌ O‘z raqamingiz kerak. Kontaktni yubormang, quyidagi tugmani bosing.",
		notUzbek:       "❌ Domix faqat O‘zbekiston raqamlari (+998) bilan ishlaydi.",
		expired:        "⌛ Vaqt tugadi yoki havola eskirgan. Tugmani bosgan joyingizdan qaytadan boshlang.",
		startFromApp:   "Kirish uchun Domix ilovasini oching va «Telegram orqali ro‘yxatdan o‘tish» tugmasini bosing.",
		failed:         "Nimadir noto‘g‘ri ketdi. Birozdan keyin qayta urinib ko‘ring.",
	},
	"en": {
		loginPrompt:    "To sign in to Domix, share your phone number with the button below.",
		loginButton:    "📱 Share my number",
		deletePrompt:   "⚠️ Deleting your Domix account.\nConfirm your number with the button below. The account, its stores, products and photos will be deleted for good.",
		deleteButton:   "🗑 Confirm deletion",
		signedIn:       "✅ Done, you are signed in to Domix. You can go back now.",
		deleted:        "✅ Your Domix account has been deleted with its stores, products and photos. It cannot be restored.",
		noAccount:      "No Domix account is registered to this number, so there is nothing to delete.",
		notYourContact: "❌ It has to be your own number. Press the button below instead of forwarding a contact.",
		notUzbek:       "❌ Domix works with Uzbek numbers (+998) only.",
		expired:        "⌛ This link has expired. Start again where you pressed the button.",
		startFromApp:   "To sign in, open the Domix app and press the Telegram button there.",
		failed:         "Something went wrong. Please try again in a moment.",
	},
}

// botLanguage is the language a session is stored with: what the caller asked for, ru otherwise
func botLanguage(lang string) string {
	if _, ok := botCopies[lang]; ok {
		return lang
	}
	return "ru"
}

// botCopyFor also takes telegram's own language_code ("ru", "uz", "en-GB"), for a chat with no session
func botCopyFor(lang string) botCopy {
	if len(lang) > 2 {
		lang = lang[:2]
	}
	return botCopies[botLanguage(lang)]
}
