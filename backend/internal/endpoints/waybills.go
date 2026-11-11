package endpoints

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/catalog"
	"domix/backend/internal/dbctx"
	"domix/backend/internal/imagestore"
	"domix/backend/internal/ratelimit"
	"domix/backend/internal/waybill"
)

// the Корзина tab: a list anybody signed in sends to Domix, owners included. staff read it in the panel
// (admin.go) and no shop ever sees it.
//
//	GET  /api/waybills            - what this account has sent, newest first
//	POST /api/waybills            - send a typed list (json)
//	POST /api/waybills/photo      - send a photographed one (multipart: image, shop_category, request_id)
//	GET  /api/waybills/{id}/photo - the photo of one of their own lists
type Waybills struct {
	Queries *db.Queries

	// the ceiling on sending, per account. nil in tests that call a handler directly.
	Sends *ratelimit.Limiter
}

const (
	waybillMaxItems    = 100
	waybillNameMax     = 150 // products.name
	waybillQuantityMax = 30

	// a tab scrolled by one person, and the app holds the whole answer
	waybillHistoryLimit = 100
)

var waybillRequestID = regexp.MustCompile(`^[0-9a-f]{32}$`)

func (wb *Waybills) Route(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		wb.List(w, r)
	case http.MethodPost:
		wb.Create(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

type waybillResponse struct {
	ID           int64           `json:"id"`
	ShopCategory string          `json:"shop_category"`
	Items        json.RawMessage `json:"items"`
	HasPhoto     bool            `json:"has_photo"`
	CreatedAt    string          `json:"created_at"`
}

func (wb *Waybills) List(w http.ResponseWriter, r *http.Request) {
	userID, _ := auth.UserIDFromContext(r.Context())

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	rows, err := wb.Queries.ListWaybillsOfUser(ctx, db.ListWaybillsOfUserParams{UserID: userID, Limit: waybillHistoryLimit})
	if err != nil {
		if !callerGone(r) {
			log.Printf("CRITICAL: could not list the waybills of user %d: %v", userID, err)
		}
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the lists")
		return
	}

	waybills := make([]waybillResponse, 0, len(rows))
	for _, row := range rows {
		waybills = append(waybills, waybillResponse{
			ID:           row.ID,
			ShopCategory: row.ShopCategory,
			Items:        row.Items,
			HasPhoto:     row.HasPhoto,
			CreatedAt:    timestampString(row.CreatedAt),
		})
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(waybills)
}

type createWaybillRequest struct {
	RequestID    string         `json:"request_id"`
	ShopCategory string         `json:"shop_category"`
	Items        []waybill.Item `json:"items"`
}

func (wb *Waybills) Create(w http.ResponseWriter, r *http.Request) {
	if !wb.allowSend(w, r) {
		return
	}

	var req createWaybillRequest
	if !decodeJSONBody(w, r, &req) {
		return
	}
	if denied := validateWaybillHeader(req.RequestID, req.ShopCategory); denied != nil {
		denied.write(w)
		return
	}
	items, denied := cleanWaybillItems(req.Items)
	if denied != nil {
		denied.write(w)
		return
	}

	encoded, err := json.Marshal(items)
	if err != nil {
		log.Printf("CRITICAL: could not encode a waybill: %v", err)
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not send the list")
		return
	}

	wb.store(w, r, req.RequestID, req.ShopCategory, encoded, nil)
}

// CreateFromPhoto takes a photographed paper list. the limiter speaks before the bytes are read, so
// flooding costs no decode.
func (wb *Waybills) CreateFromPhoto(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if !wb.allowSend(w, r) {
		return
	}

	raw, ok := readUploadedImage(w, r)
	if !ok {
		return
	}
	// readUploadedImage parsed the whole form, so these are read out of memory
	requestID, category := r.FormValue("request_id"), r.FormValue("shop_category")
	if denied := validateWaybillHeader(requestID, category); denied != nil {
		denied.write(w)
		return
	}

	// the re-encode is what strips the coordinates a phone writes into a photo
	photo, err := imagestore.NormalizeDocument(raw)
	if err != nil {
		writeImageError(w, err)
		return
	}

	wb.store(w, r, requestID, category, []byte("[]"), photo)
}

func (wb *Waybills) store(w http.ResponseWriter, r *http.Request, requestID, category string, items, photo []byte) {
	userID, _ := auth.UserIDFromContext(r.Context())

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	row, err := wb.Queries.CreateWaybill(ctx, db.CreateWaybillParams{
		UserID:       userID,
		RequestID:    requestID,
		ShopCategory: category,
		Items:        items,
		Photo:        photo,
	})
	if err != nil {
		if !callerGone(r) {
			log.Printf("CRITICAL: could not store a waybill for user %d: %v", userID, err)
		}
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not send the list")
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(waybillResponse{
		ID:           row.ID,
		ShopCategory: row.ShopCategory,
		Items:        row.Items,
		HasPhoto:     row.HasPhoto,
		CreatedAt:    timestampString(row.CreatedAt),
	})
}

// Photo answers only about the caller's own lists: GetWaybillPhotoOfUser filters by account, so
// somebody else's number is the same 404 as a number that was never issued.
func (wb *Waybills) Photo(w http.ResponseWriter, r *http.Request) {
	userID, _ := auth.UserIDFromContext(r.Context())

	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeAPIError(w, http.StatusBadRequest, "invalid_id", "waybill id must be a positive integer")
		return
	}

	ctx, cancel := dbctx.WithTimeout(r.Context())
	defer cancel()

	photo, err := wb.Queries.GetWaybillPhotoOfUser(ctx, db.GetWaybillPhotoOfUserParams{ID: id, UserID: userID})
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		if !callerGone(r) {
			log.Printf("CRITICAL: could not read the photo of waybill %d: %v", id, err)
		}
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not load the photo")
		return
	}
	writeWaybillPhoto(w, photo)
}

// nil covers both a row that is not there and a typed list, which has no photo to show
func writeWaybillPhoto(w http.ResponseWriter, photo []byte) {
	if photo == nil {
		writeAPIError(w, http.StatusNotFound, "photo_not_found", "this list has no photo")
		return
	}
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Content-Length", strconv.Itoa(len(photo)))
	// somebody's private list, on a computer staff may share
	w.Header().Set("Cache-Control", "no-store")
	w.Write(photo)
}

func (wb *Waybills) allowSend(w http.ResponseWriter, r *http.Request) bool {
	if wb.Sends == nil {
		return true
	}
	userID, _ := auth.UserIDFromContext(r.Context())
	if !wb.Sends.Allow("user:" + strconv.FormatInt(userID, 10)) {
		w.Header().Set("Retry-After", strconv.Itoa(int(wb.Sends.RetryAfter()/time.Second)))
		writeAPIError(w, http.StatusTooManyRequests, "too_many_waybills", "too many lists at once, wait a little")
		return false
	}
	return true
}

func validateWaybillHeader(requestID, category string) *accessError {
	if !waybillRequestID.MatchString(requestID) {
		return &accessError{http.StatusBadRequest, "invalid_request_id", "request_id must be 32 lowercase hex characters"}
	}
	if !catalog.IsValidCategory(category) {
		return &accessError{http.StatusBadRequest, "invalid_category", "unknown shop category"}
	}
	return nil
}

func cleanWaybillItems(raw []waybill.Item) ([]waybill.Item, *accessError) {
	if len(raw) == 0 {
		return nil, &accessError{http.StatusBadRequest, "empty_list", "a list needs at least one row"}
	}
	if len(raw) > waybillMaxItems {
		return nil, &accessError{http.StatusBadRequest, "too_many_items", "a list may not have more than 100 rows"}
	}

	items := make([]waybill.Item, 0, len(raw))
	for _, item := range raw {
		name, quantity := cleanWaybillText(item.Name), cleanWaybillText(item.Quantity)
		if name == "" || utf8.RuneCountInString(name) > waybillNameMax {
			return nil, &accessError{http.StatusBadRequest, "invalid_item_name", "a row needs a name of up to 150 characters"}
		}
		if quantity == "" || utf8.RuneCountInString(quantity) > waybillQuantityMax {
			return nil, &accessError{http.StatusBadRequest, "invalid_item_quantity", "a row needs a quantity of up to 30 characters"}
		}
		items = append(items, waybill.Item{Name: name, Quantity: quantity})
	}
	return items, nil
}

// one line of plain text. **the control characters are not cosmetic**: postgres refuses a \u0000 inside
// jsonb, so one pasted NUL would answer the sender with a 500 on every retry.
func cleanWaybillText(raw string) string {
	spaced := strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, raw)
	return strings.Join(strings.Fields(spaced), " ")
}
