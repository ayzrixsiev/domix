package endpoints

import (
	"bytes"
	"context"
	"encoding/json"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
	"domix/backend/internal/ratelimit"
)

const (
	firstRequestID  = "0123456789abcdef0123456789abcdef"
	secondRequestID = "fedcba9876543210fedcba9876543210"
)

func waybillsUnderTest(t *testing.T) (*Waybills, *Admin, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()
	admin, ctx, tx, q := adminUnderTest(t)
	return &Waybills{Queries: q}, admin, ctx, tx, q
}

// through the real chain, RequireAuth then RequireCustomer: a handler called directly would pass with
// the role check removed
func requestWaybill(t *testing.T, ctx context.Context, wb *Waybills, method, target string, asUserID int64,
	contentType string, body []byte, handler http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "+998900000000", 0, testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}

	req := httptest.NewRequestWithContext(ctx, method, target, bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	if segments := strings.Split(strings.Trim(target, "/"), "/"); len(segments) == 4 {
		req.SetPathValue("id", segments[2])
	}

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, wb.Queries, wb.RequireCustomer(handler))(rec, req)
	return rec
}

func sendList(t *testing.T, ctx context.Context, wb *Waybills, userID int64, requestID, category string, items []map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	body, err := json.Marshal(map[string]any{"request_id": requestID, "shop_category": category, "items": items})
	if err != nil {
		t.Fatal(err)
	}
	return requestWaybill(t, ctx, wb, http.MethodPost, "/api/waybills", userID, "application/json", body, wb.Route)
}

func sendPhoto(t *testing.T, ctx context.Context, wb *Waybills, userID int64, requestID string, photo []byte) *httptest.ResponseRecorder {
	t.Helper()
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	form.WriteField("request_id", requestID)
	form.WriteField("shop_category", "plumbing")
	part, err := form.CreateFormFile("image", "list.jpg")
	if err != nil {
		t.Fatal(err)
	}
	part.Write(photo)
	form.Close()
	return requestWaybill(t, ctx, wb, http.MethodPost, "/api/waybills/photo", userID, form.FormDataContentType(), body.Bytes(), wb.CreateFromPhoto)
}

func oneRow() []map[string]string {
	return []map[string]string{{"name": "Цемент М400", "quantity": "10 мешков"}}
}

func decodeWaybill(t *testing.T, rec *httptest.ResponseRecorder) waybillResponse {
	t.Helper()
	if rec.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var created waybillResponse
	decodeBody(t, rec, &created)
	return created
}

// the founder's rule. every route, because a shop owner holds a valid token and an old build or a curl
// does not care that the tab is hidden.
func TestOnlyACustomerCanUseTheCart(t *testing.T) {
	wb, _, ctx, _, q := waybillsUnderTest(t)

	owner := makeUser(t, ctx, q, "Owner", "shop_owner")

	for name, handler := range map[string]http.HandlerFunc{"route": wb.Route, "photo": wb.CreateFromPhoto, "read": wb.Photo} {
		for _, caller := range []int64{owner} {
			rec := requestWaybill(t, ctx, wb, http.MethodGet, "/api/waybills/1/photo", caller, "", nil, handler)
			if rec.Code != http.StatusForbidden {
				t.Errorf("%s as %d = %d, want 403", name, caller, rec.Code)
			}
			var body map[string]string
			decodeBody(t, rec, &body)
			if body["code"] != "customers_only" {
				t.Errorf("%s as %d answered code %q", name, caller, body["code"])
			}
		}
	}
}

func TestAnAdminCanUseTheCart(t *testing.T) {
	wb, _, ctx, _, q := waybillsUnderTest(t)
	admin := makeUser(t, ctx, q, "Admin", "admin")

	if rec := requestWaybill(t, ctx, wb, http.MethodGet, "/api/waybills", admin, "", nil, wb.Route); rec.Code != http.StatusOK {
		t.Errorf("admin listing = %d, want 200", rec.Code)
	}
}

// the same token proves the role is read from the database: a customer who opens a shop loses the tab
// on their very next request.
func TestACustomerWhoBecomesAnOwnerLosesTheCart(t *testing.T) {
	wb, _, ctx, tx, q := waybillsUnderTest(t)

	customer := makeUser(t, ctx, q, "Soon", "customer")
	if rec := requestWaybill(t, ctx, wb, http.MethodGet, "/api/waybills", customer, "", nil, wb.Route); rec.Code != http.StatusOK {
		t.Fatalf("as customer = %d", rec.Code)
	}
	if _, err := tx.Exec(ctx, "UPDATE users SET role = 'shop_owner' WHERE id = $1", customer); err != nil {
		t.Fatal(err)
	}
	if rec := requestWaybill(t, ctx, wb, http.MethodGet, "/api/waybills", customer, "", nil, wb.Route); rec.Code != http.StatusForbidden {
		t.Errorf("after the upgrade = %d, want 403", rec.Code)
	}
}

func TestASentListGetsAUniqueNumberAndComesBackToItsSender(t *testing.T) {
	wb, _, ctx, _, q := waybillsUnderTest(t)

	customer := makeUser(t, ctx, q, "Buyer", "customer")
	first := decodeWaybill(t, sendList(t, ctx, wb, customer, firstRequestID, "plumbing", oneRow()))
	second := decodeWaybill(t, sendList(t, ctx, wb, customer, secondRequestID, "wood", oneRow()))
	if first.ID == second.ID {
		t.Fatalf("two lists share the number %d", first.ID)
	}

	rec := requestWaybill(t, ctx, wb, http.MethodGet, "/api/waybills", customer, "", nil, wb.Route)
	var listed []waybillResponse
	decodeBody(t, rec, &listed)
	if len(listed) != 2 || listed[0].ID != second.ID {
		t.Fatalf("newest first, got %+v", listed)
	}
	if !strings.Contains(string(listed[1].Items), "Цемент М400") {
		t.Errorf("rows did not come back: %s", listed[1].Items)
	}
}

func TestACustomerSeesNobodyElsesLists(t *testing.T) {
	wb, _, ctx, _, q := waybillsUnderTest(t)

	author := makeUser(t, ctx, q, "Author", "customer")
	stranger := makeUser(t, ctx, q, "Stranger", "customer")
	sent := decodeWaybill(t, sendPhoto(t, ctx, wb, author, firstRequestID, testPhoto(t, 800, 800)))

	rec := requestWaybill(t, ctx, wb, http.MethodGet, "/api/waybills", stranger, "", nil, wb.Route)
	var listed []waybillResponse
	decodeBody(t, rec, &listed)
	if len(listed) != 0 {
		t.Errorf("a stranger's list holds %+v", listed)
	}

	target := "/api/waybills/" + strconv.FormatInt(sent.ID, 10) + "/photo"
	if rec := requestWaybill(t, ctx, wb, http.MethodGet, target, stranger, "", nil, wb.Photo); rec.Code != http.StatusNotFound {
		t.Errorf("a stranger reading the photo = %d, want 404", rec.Code)
	}
	if rec := requestWaybill(t, ctx, wb, http.MethodGet, target, author, "", nil, wb.Photo); rec.Code != http.StatusOK {
		t.Errorf("the author reading the photo = %d, want 200", rec.Code)
	}
}

// the answer to the first send got lost on a bad connection and the customer pressed again. one list.
func TestARetryAnswersWithTheSameNumber(t *testing.T) {
	wb, _, ctx, tx, q := waybillsUnderTest(t)

	customer := makeUser(t, ctx, q, "Flaky", "customer")
	first := decodeWaybill(t, sendList(t, ctx, wb, customer, firstRequestID, "plumbing", oneRow()))
	retry := decodeWaybill(t, sendList(t, ctx, wb, customer, firstRequestID, "plumbing", oneRow()))
	if first.ID != retry.ID {
		t.Errorf("a retry was issued a second number: %d and %d", first.ID, retry.ID)
	}
	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM waybills WHERE user_id = $1", customer); n != 1 {
		t.Errorf("%d rows after a retry", n)
	}

	// two customers' app builds drawing the same id must not collide with each other
	other := makeUser(t, ctx, q, "Other", "customer")
	if theirs := decodeWaybill(t, sendList(t, ctx, wb, other, firstRequestID, "plumbing", oneRow())); theirs.ID == first.ID {
		t.Error("one customer was answered with another's list")
	}
}

func TestABadListIsRefusedWithACodeTheAppCanTranslate(t *testing.T) {
	wb, _, ctx, tx, q := waybillsUnderTest(t)

	customer := makeUser(t, ctx, q, "Careless", "customer")
	tooMany := make([]map[string]string, waybillMaxItems+1)
	for i := range tooMany {
		tooMany[i] = oneRow()[0]
	}

	for _, tc := range []struct {
		name, requestID, category, code string
		items                           []map[string]string
	}{
		{"no rows", firstRequestID, "plumbing", "empty_list", nil},
		{"too many rows", firstRequestID, "plumbing", "too_many_items", tooMany},
		{"a blank name", firstRequestID, "plumbing", "invalid_item_name", []map[string]string{{"name": "   ", "quantity": "1"}}},
		{"a long name", firstRequestID, "plumbing", "invalid_item_name", []map[string]string{{"name": strings.Repeat("я", waybillNameMax+1), "quantity": "1"}}},
		{"no quantity", firstRequestID, "plumbing", "invalid_item_quantity", []map[string]string{{"name": "Цемент", "quantity": ""}}},
		{"an unknown market", firstRequestID, "groceries", "invalid_category", oneRow()},
		{"no request id", "", "plumbing", "invalid_request_id", oneRow()},
		{"a guessable request id", "1", "plumbing", "invalid_request_id", oneRow()},
	} {
		rec := sendList(t, ctx, wb, customer, tc.requestID, tc.category, tc.items)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s = %d, want 400", tc.name, rec.Code)
			continue
		}
		var body map[string]string
		decodeBody(t, rec, &body)
		if body["code"] != tc.code {
			t.Errorf("%s answered %q, want %q", tc.name, body["code"], tc.code)
		}
	}
	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM waybills WHERE user_id = $1", customer); n != 0 {
		t.Errorf("%d rows written by refused requests", n)
	}
}

// postgres refuses \u0000 inside jsonb. without the cleaning this is a 500 the customer can never get past.
func TestAControlCharacterInARowIsNotAServerError(t *testing.T) {
	wb, _, ctx, _, q := waybillsUnderTest(t)

	customer := makeUser(t, ctx, q, "Paster", "customer")
	created := decodeWaybill(t, sendList(t, ctx, wb, customer, firstRequestID, "wood",
		[]map[string]string{{"name": "Доска\u0000 \n 50х150", "quantity": " 3\tшт "}}))
	if !strings.Contains(string(created.Items), `"Доска 50х150"`) || !strings.Contains(string(created.Items), `"3 шт"`) {
		t.Errorf("rows were stored as %s", created.Items)
	}
}

func TestAPhotoListStoresAScrubbedLargerJPEG(t *testing.T) {
	wb, _, ctx, tx, q := waybillsUnderTest(t)

	customer := makeUser(t, ctx, q, "Writer", "customer")
	created := decodeWaybill(t, sendPhoto(t, ctx, wb, customer, firstRequestID, testPhoto(t, 3000, 2000)))
	if !created.HasPhoto {
		t.Fatal("has_photo is false")
	}

	var stored []byte
	if err := tx.QueryRow(ctx, "SELECT photo FROM waybills WHERE id = $1", created.ID).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	cfg, err := jpeg.DecodeConfig(bytes.NewReader(stored))
	if err != nil {
		t.Fatalf("the stored photo is not a jpeg: %v", err)
	}
	if cfg.Width != 2000 {
		t.Errorf("stored %dpx wide, want the 2000 a handwritten list needs", cfg.Width)
	}

	rec := sendPhoto(t, ctx, wb, customer, secondRequestID, []byte("not a picture"))
	if rec.Code != http.StatusBadRequest {
		t.Errorf("a file that is no photo = %d, want 400", rec.Code)
	}
}

func TestATypedListHasNoPhotoToRead(t *testing.T) {
	wb, _, ctx, _, q := waybillsUnderTest(t)

	customer := makeUser(t, ctx, q, "Typist", "customer")
	created := decodeWaybill(t, sendList(t, ctx, wb, customer, firstRequestID, "plumbing", oneRow()))

	target := "/api/waybills/" + strconv.FormatInt(created.ID, 10) + "/photo"
	if rec := requestWaybill(t, ctx, wb, http.MethodGet, target, customer, "", nil, wb.Photo); rec.Code != http.StatusNotFound {
		t.Errorf("= %d, want 404", rec.Code)
	}
}

func TestSendingIsMeteredPerAccount(t *testing.T) {
	wb, _, ctx, _, q := waybillsUnderTest(t)
	wb.Sends = ratelimit.New(1.0/600, 1, time.Hour)

	first := makeUser(t, ctx, q, "First", "customer")
	second := makeUser(t, ctx, q, "Second", "customer")

	decodeWaybill(t, sendList(t, ctx, wb, first, firstRequestID, "plumbing", oneRow()))
	if rec := sendList(t, ctx, wb, first, secondRequestID, "plumbing", oneRow()); rec.Code != http.StatusTooManyRequests {
		t.Errorf("past the budget = %d, want 429", rec.Code)
	}
	decodeWaybill(t, sendList(t, ctx, wb, second, firstRequestID, "plumbing", oneRow()))
}

func TestThePanelReadsAndPrintsAList(t *testing.T) {
	wb, admin, ctx, _, q := waybillsUnderTest(t)

	adminID := makeUser(t, ctx, q, "Boss", "admin")
	customer := makeUser(t, ctx, q, "Buyer", "customer")
	typed := decodeWaybill(t, sendList(t, ctx, wb, customer, firstRequestID, "plumbing", oneRow()))
	photo := decodeWaybill(t, sendPhoto(t, ctx, wb, customer, secondRequestID, testPhoto(t, 800, 800)))

	rec := requestAdmin(t, ctx, admin, http.MethodGet, "/api/admin/waybills", adminID, admin.ListWaybills)
	var inbox struct {
		Waybills []adminWaybillResponse `json:"waybills"`
	}
	decodeBody(t, rec, &inbox)
	if len(inbox.Waybills) != 2 {
		t.Fatalf("%d lists in the inbox, want 2", len(inbox.Waybills))
	}
	if inbox.Waybills[1].ItemCount != 1 || inbox.Waybills[1].CustomerName != "Buyer" || !inbox.Waybills[0].HasPhoto {
		t.Errorf("inbox rows: %+v", inbox.Waybills)
	}

	for _, id := range []int64{typed.ID, photo.ID} {
		rec := requestWaybillAsAdmin(t, ctx, admin, adminID, id, admin.WaybillPDF)
		if rec.Code != http.StatusOK {
			t.Fatalf("pdf of %d = %d: %s", id, rec.Code, rec.Body.String())
		}
		if got := rec.Header().Get("Content-Type"); got != "application/pdf" {
			t.Errorf("content type %q", got)
		}
		if got := rec.Header().Get("Content-Disposition"); !strings.Contains(got, "nakladnaya-"+strconv.FormatInt(id, 10)+".pdf") {
			t.Errorf("disposition %q", got)
		}
		if !bytes.HasPrefix(rec.Body.Bytes(), []byte("%PDF-")) {
			t.Errorf("body of %d is not a pdf", id)
		}
	}

	if rec := requestWaybillAsAdmin(t, ctx, admin, adminID, photo.ID, admin.WaybillPhoto); rec.Header().Get("Content-Type") != "image/jpeg" {
		t.Errorf("photo answered %d %q", rec.Code, rec.Header().Get("Content-Type"))
	}
	if rec := requestWaybillAsAdmin(t, ctx, admin, adminID, 987654321, admin.WaybillPDF); rec.Code != http.StatusNotFound {
		t.Errorf("a number never issued = %d, want 404", rec.Code)
	}
}

// the printed form and a phone number are exactly what a shop owner holding a valid token must not reach
func TestAShopOwnerCannotOpenAListInThePanel(t *testing.T) {
	wb, admin, ctx, _, q := waybillsUnderTest(t)

	owner := makeUser(t, ctx, q, "Owner", "shop_owner")
	customer := makeUser(t, ctx, q, "Buyer", "customer")
	sent := decodeWaybill(t, sendPhoto(t, ctx, wb, customer, firstRequestID, testPhoto(t, 800, 800)))

	for name, handler := range map[string]http.HandlerFunc{"read": admin.RouteWaybill, "photo": admin.WaybillPhoto, "pdf": admin.WaybillPDF} {
		if rec := requestWaybillAsAdmin(t, ctx, admin, owner, sent.ID, handler); rec.Code != http.StatusForbidden {
			t.Errorf("%s as an owner = %d, want 403", name, rec.Code)
		}
	}
}

func TestDeletingAListFromThePanelTakesItsPhoto(t *testing.T) {
	wb, admin, ctx, tx, q := waybillsUnderTest(t)

	adminID := makeUser(t, ctx, q, "Boss", "admin")
	customer := makeUser(t, ctx, q, "Spammer", "customer")
	sent := decodeWaybill(t, sendPhoto(t, ctx, wb, customer, firstRequestID, testPhoto(t, 800, 800)))

	rec := requestAdmin(t, ctx, admin, http.MethodDelete, "/api/admin/waybills/"+strconv.FormatInt(sent.ID, 10), adminID, admin.RouteWaybill)
	if rec.Code != http.StatusOK {
		t.Fatalf("delete = %d: %s", rec.Code, rec.Body.String())
	}
	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM waybills WHERE id = $1", sent.ID); n != 0 {
		t.Error("the row survived")
	}
	rec = requestAdmin(t, ctx, admin, http.MethodDelete, "/api/admin/waybills/"+strconv.FormatInt(sent.ID, 10), adminID, admin.RouteWaybill)
	if rec.Code != http.StatusNotFound {
		t.Errorf("deleting it twice = %d, want 404", rec.Code)
	}
}

// the privacy policy's promise: the account goes and every list and photo goes with it, in one statement
func TestDeletingAnAccountTakesItsLists(t *testing.T) {
	wb, _, ctx, tx, q := waybillsUnderTest(t)

	customer := makeUser(t, ctx, q, "Leaving", "customer")
	decodeWaybill(t, sendPhoto(t, ctx, wb, customer, firstRequestID, testPhoto(t, 800, 800)))
	decodeWaybill(t, sendList(t, ctx, wb, customer, secondRequestID, "plumbing", oneRow()))

	if _, err := q.AdminDeleteUser(ctx, customer); err != nil {
		t.Fatal(err)
	}
	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM waybills WHERE user_id = $1", customer); n != 0 {
		t.Errorf("%d lists survived the account", n)
	}
}

// the database is the last word on "rows or a photo", since the panel and the pdf both trust it
func TestAListWithBothRowsAndAPhotoCannotExist(t *testing.T) {
	_, _, ctx, tx, q := waybillsUnderTest(t)
	customer := makeUser(t, ctx, q, "Both", "customer")

	for name, statement := range map[string]string{
		"neither": `INSERT INTO waybills (user_id, request_id, shop_category) VALUES ($1, 'a', 'wood')`,
		"both":    `INSERT INTO waybills (user_id, request_id, shop_category, items, photo) VALUES ($1, 'b', 'wood', '[{"name":"x","quantity":"1"}]', '\x00')`,
	} {
		savepoint, err := tx.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := savepoint.Exec(ctx, statement, customer); err == nil {
			t.Errorf("%s was accepted", name)
		}
		savepoint.Rollback(ctx)
	}
}

func requestWaybillAsAdmin(t *testing.T, ctx context.Context, a *Admin, asUserID, id int64, handler http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()

	token, err := auth.GenerateJWT(asUserID, "+998900000000", 0, testJWTSecret)
	if err != nil {
		t.Fatalf("sign a token: %v", err)
	}
	req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/api/admin/waybills/x", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	req.SetPathValue("id", strconv.FormatInt(id, 10))

	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, a.Queries, a.RequireAdmin(handler))(rec, req)
	return rec
}
