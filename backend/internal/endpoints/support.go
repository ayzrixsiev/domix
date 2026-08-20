package endpoints

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"unicode/utf8"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/dbctx"
)

// the app's half of the support inbox: a signed-in user reading and writing their own thread.
//
// there is no shop id, no thread id and no recipient in any of this - **the thread is the caller**.
// every statement below is keyed by the user id RequireAuth put on the context, so there is no
// parameter an attacker could point at somebody else's conversation. that is worth more than it
// looks: a support inbox is where people paste their phone numbers and their problems, and a
// /api/support/threads/{id} shaped api would have made "did we check the owner of that id" a
// question somebody has to answer correctly in three handlers.
//
// the admin half lives in admin.go with the rest of the privileged surface, deliberately not here.
type Support struct {
	Queries *db.Queries
}

const (
	// how long one message may be. the number is a product decision rather than a storage limit -
	// the column is TEXT - and it exists because this arrives in a human's inbox: a screenful is a
	// question, ten screenfuls is something that needs a phone call.
	supportMessageMaxRunes = 2000

	// how many messages one account may send in a minute.
	//
	// the general limiter is per-IP and allows 20 requests a second, which is the right ceiling for
	// an api and no protection at all for an inbox somebody reads by hand. this is the per-account
	// question the limiter cannot ask. it is deliberately far above anything a person types - the
	// wall exists for a script, not for someone sending three quick corrections.
	supportMessagesPerMinute = 10
)

type supportMessageResponse struct {
	ID int64 `json:"id"`
	// which side wrote it, which is the only thing the chat bubble's alignment and colour depend on
	FromSupport bool   `json:"from_support"`
	Body        string `json:"body"`
	CreatedAt   string `json:"created_at"`
}

func supportMessageDTO(m db.SupportMessage) supportMessageResponse {
	return supportMessageResponse{
		ID:          m.ID,
		FromSupport: m.FromSupport,
		Body:        m.Body,
		CreatedAt:   timestampString(m.CreatedAt),
	}
}

// one path, two verbs - the same shape Auth.RouteMe uses, and for the same reason: reading the
// thread and adding to it are the same resource.
func (s *Support) Route(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.List(w, r)
	case http.MethodPost:
		s.Send(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// GET /api/support/messages - the caller's whole conversation, oldest first.
func (s *Support) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := s.Queries.ListSupportThread(ctx, userID)
	if err != nil {
		log.Printf("CRITICAL: support thread for user %d failed to load: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the conversation")
		return
	}

	// `make` with a length of zero rather than a nil slice: a nil marshals to `null`, and the app
	// decodes this as a list. the first user ever to open the tab has no messages.
	messages := make([]supportMessageResponse, 0, len(rows))
	for _, row := range rows {
		messages = append(messages, supportMessageDTO(row))
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]any{"messages": messages})
}

type supportSendRequest struct {
	Body string `json:"body"`
}

// POST /api/support/messages - the user writes in.
//
// `from_support` is hardcoded false here and true in the admin handler, so it is never read off a
// request body. a client that could set it would be a client that can post a message appearing to
// come from Domix, into its own thread, quoting whatever it likes.
func (s *Support) Send(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		writeAPIError(w, http.StatusUnauthorized, "unauthorized", "not signed in")
		return
	}

	var req supportSendRequest
	if !decodeJSONBody(w, r, &req) {
		return
	}

	body, fail := cleanSupportBody(req.Body)
	if fail != nil {
		fail.write(w)
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	recent, err := s.Queries.CountRecentSupportMessages(ctx, userID)
	if err != nil {
		log.Printf("CRITICAL: support flood check for user %d failed: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not send the message")
		return
	}
	if recent >= supportMessagesPerMinute {
		// 429 rather than 403: this is "not right now", and the app says so - a permanent-sounding
		// refusal would send someone to the profile screen looking for a setting that blocked them.
		writeAPIError(w, http.StatusTooManyRequests, "too_many_messages",
			"too many messages, wait a minute before sending another")
		return
	}

	message, err := s.Queries.CreateSupportMessage(ctx, db.CreateSupportMessageParams{
		UserID:      userID,
		FromSupport: false,
		Body:        body,
	})
	if err != nil {
		log.Printf("CRITICAL: user %d could not send a support message: %v", userID, err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not send the message")
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(supportMessageDTO(message))
}

// cleanSupportBody trims a submitted message and refuses the two shapes that are not a message.
// shared by both sides of the inbox, so the app and the panel cannot disagree about what counts.
//
// **the length is counted in runes, not bytes.** `len()` counts bytes and every cyrillic letter is
// two of them, so a byte limit of 2000 would cut a russian message in half at exactly the point
// where an english one was still fine - the same trap the search endpoint's two-character floor
// documents, in the other direction.
func cleanSupportBody(raw string) (string, *accessError) {
	body := strings.TrimSpace(raw)
	if body == "" {
		return "", &accessError{http.StatusBadRequest, "empty_message", "a message cannot be empty"}
	}
	if utf8.RuneCountInString(body) > supportMessageMaxRunes {
		return "", &accessError{http.StatusBadRequest, "message_too_long", "the message is too long"}
	}
	return body, nil
}
