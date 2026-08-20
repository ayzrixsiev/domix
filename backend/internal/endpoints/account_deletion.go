package endpoints

import (
	"encoding/json"
	"net/http"

	"domix/backend/internal/auth"
)

// the /delete-account page's half of account deletion.
//
// **Google Play requires a deletion path that works without the app installed** - somebody who has
// already uninstalled must still be able to be forgotten - and for a long time this page satisfied
// that by printing an email address. That is a promise a human has to keep by hand, on a mailbox
// nobody watches on a Sunday, so it was the part of the product most likely to be quietly broken.
//
// This makes it the same handshake the app uses to log in, pointed at DELETE instead: type the
// number, confirm it in Telegram, the account is gone. Nothing new had to be invented for it -
// internal/auth's session manager, the deep link and the bot's contact button already existed and
// already carry a proof of ownership stronger than an email ever could.
//
// Two endpoints rather than one, mirroring /api/auth/init and /api/auth/status, because they are
// the same two moments: start something that finishes elsewhere, then ask whether it has.
type AccountDeletion struct {
	SessionMgr  *auth.SessionManager
	BotUsername string
}

// what counts as a phone number at all. the low end is a local Uzbek number without its country
// code, the high end is E.164's own ceiling - deliberately loose, because this value is never used
// to find anybody: it is only ever compared against the contact telegram reports, and *that*
// comparison is the real check. a tight regex here would only reject honest formatting.
const (
	minPhoneDigits = 9
	maxPhoneDigits = 15
)

// POST /api/account-deletion/init - the page hands over a typed phone number and gets a deep link.
//
// **The database is deliberately not consulted here.** Answering "no such account" at this point
// would turn the page into a way to ask, from any browser and without proving anything, whether a
// given phone number belongs to a Domix user - every number in the country, one request at a time.
// The honest answer to that question is given inside Telegram, after the person has shown they own
// the number, and until then every input gets the same reply.
func (d *AccountDeletion) Init(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Phone string `json:"phone"`
	}
	if !decodeJSONBody(w, r, &req) {
		return
	}

	phone := auth.NormalizePhone(req.Phone)
	if len(phone) < minPhoneDigits || len(phone) > maxPhoneDigits {
		writeAPIError(w, http.StatusBadRequest, "invalid_phone", "that is not a phone number")
		return
	}

	sessionID := d.SessionMgr.InitDeletion(phone)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"session_id":   sessionID,
		"telegram_url": "https://t.me/" + d.BotUsername + "?start=" + sessionID,
	})
}

// GET /api/account-deletion/status - the page polls this while the user is away in Telegram.
//
// It answers with a status and nothing else. The login version of this endpoint hands back the
// whole session because the app needs the token out of it; there is nothing here a browser needs
// beyond which of five sentences to render, and the session still holds the phone number that was
// typed into it.
//
// **The purpose check is not tidiness.** Without it, a completed *login* session id posted here
// would read back as `success` - and this page renders `success` as "your account has been
// deleted", about an account that is perfectly intact.
func (d *AccountDeletion) Status(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("session_id")
	if sessionID == "" {
		writeAPIError(w, http.StatusBadRequest, "missing_session", "missing session_id")
		return
	}

	session := d.SessionMgr.GetStatus(sessionID)

	// an unknown id already reports "not_found"; a login session is reported the same way, since as
	// far as this page is concerned it does not exist.
	status := session.Status
	if session.Purpose != auth.PurposeDeletion {
		status = "not_found"
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": status})
}
