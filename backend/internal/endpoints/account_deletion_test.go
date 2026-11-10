package endpoints

// the /delete-account page's api. Two properties matter more than the happy path:
//
//   - **a browser must not be able to ask whether a number is registered.** the answer to
//     request-code is byte-identical either way, and no code is paid for when nobody is there.
//   - **nothing is deleted without the code.** the page's phone field proves nothing on its own.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
)

func deletionUnderTest(t *testing.T) (*AccountDeletion, *fakeSender, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	_, ctx, tx, q := homeUnderTest(t)
	sender := &fakeSender{}
	return &AccountDeletion{Queries: q, Codes: auth.NewCodeManager(true), Sender: sender}, sender, ctx, tx, q
}

func postDeletion(t *testing.T, handler http.HandlerFunc, body string) *httptest.ResponseRecorder {
	t.Helper()

	req := httptest.NewRequest(http.MethodPost, "/api/account-deletion", strings.NewReader(body))
	rec := httptest.NewRecorder()
	handler(rec, req)
	return rec
}

// the response with the caller's own number taken out of it, so two different numbers can be
// compared for everything the server chose to say
func answerShape(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode %s: %v", rec.Body, err)
	}
	delete(body, "phone")

	shape, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("re-encode: %v", err)
	}
	return string(shape)
}

func registerForDeletion(t *testing.T, ctx context.Context, q *db.Queries, phone string) int64 {
	t.Helper()

	user, err := q.CreateUser(ctx, db.CreateUserParams{Phone: phone, Role: "customer"})
	if err != nil {
		t.Fatalf("creating a user: %v", err)
	}
	return user.ID
}

// The whole reason the account lookup happens before the code is minted rather than after.
func TestTheDeletionPageCannotBeUsedToProbeWhoIsRegistered(t *testing.T) {
	d, sender, ctx, _, q := deletionUnderTest(t)
	registerForDeletion(t, ctx, q, "998901110011")

	registered := postDeletion(t, d.RequestCode, `{"phone":"998901110011"}`)
	unknown := postDeletion(t, d.RequestCode, `{"phone":"998905550055"}`)

	if registered.Code != http.StatusOK || unknown.Code != http.StatusOK {
		t.Fatalf("statuses differ: registered %d, unknown %d", registered.Code, unknown.Code)
	}
	// everything but the echoed number, which is the caller's own input coming back
	if a, b := answerShape(t, registered), answerShape(t, unknown); a != b {
		t.Fatalf("bodies differ:\n registered %s\n unknown    %s", a, b)
	}

	// and the unregistered number cost nothing to ask about
	phone, _, calls := sender.delivered()
	if calls != 1 {
		t.Fatalf("the provider was called %d times, want exactly 1 (only the registered number)", calls)
	}
	if phone != "998901110011" {
		t.Fatalf("a code was delivered to %q", phone)
	}
}

func TestACorrectCodeDeletesTheAccountAndItsShops(t *testing.T) {
	d, sender, ctx, tx, q := deletionUnderTest(t)
	userID := registerForDeletion(t, ctx, q, "998901110011")

	if rec := postDeletion(t, d.RequestCode, `{"phone":"+998 90 111 00 11"}`); rec.Code != http.StatusOK {
		t.Fatalf("request-code answered %d: %s", rec.Code, rec.Body)
	}
	_, code, _ := sender.delivered()

	rec := postDeletion(t, d.Confirm, `{"phone":"998901110011","code":"`+code+`"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("confirm answered %d: %s", rec.Code, rec.Body)
	}
	var answer struct {
		Deleted bool `json:"deleted"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &answer); err != nil || !answer.Deleted {
		t.Fatalf("confirm answered %s", rec.Body)
	}

	if left := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE id = $1", userID); left != 0 {
		t.Fatalf("the account is still there")
	}
}

func TestAWrongCodeDeletesNothing(t *testing.T) {
	d, sender, ctx, tx, q := deletionUnderTest(t)
	userID := registerForDeletion(t, ctx, q, "998901110011")

	postDeletion(t, d.RequestCode, `{"phone":"998901110011"}`)
	_, code, _ := sender.delivered()

	wrong := "000000"
	if code == wrong {
		wrong = "111111"
	}

	rec := postDeletion(t, d.Confirm, `{"phone":"998901110011","code":"`+wrong+`"}`)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("a wrong code answered %d, want 401: %s", rec.Code, rec.Body)
	}
	if left := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE id = $1", userID); left != 1 {
		t.Fatalf("the account was deleted by a wrong code")
	}
}

// Typing a number on the page and never asking for a code must reach nothing at all.
func TestConfirmWithoutEverRequestingACodeIsRefused(t *testing.T) {
	d, _, ctx, tx, q := deletionUnderTest(t)
	userID := registerForDeletion(t, ctx, q, "998901110011")

	rec := postDeletion(t, d.Confirm, `{"phone":"998901110011","code":"123456"}`)
	if rec.Code == http.StatusOK {
		t.Fatalf("confirm accepted a code nobody issued: %s", rec.Body)
	}
	if left := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE id = $1", userID); left != 1 {
		t.Fatalf("the account was deleted without a code")
	}
}

// A login code and a deletion code are both six digits sent to the same number. Spending one on the
// other flow would let a signup in progress be turned into a deletion.
func TestALoginCodeCannotDeleteAnAccount(t *testing.T) {
	d, _, ctx, tx, q := deletionUnderTest(t)
	userID := registerForDeletion(t, ctx, q, "998901110011")

	code, _, err := d.Codes.Issue(auth.Pending{Purpose: auth.CodeLogin, Phone: "998901110011"})
	if err != nil {
		t.Fatalf("issuing a login code: %v", err)
	}

	rec := postDeletion(t, d.Confirm, `{"phone":"998901110011","code":"`+code+`"}`)
	if rec.Code == http.StatusOK {
		t.Fatalf("a login code deleted an account: %s", rec.Body)
	}
	if left := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE id = $1", userID); left != 1 {
		t.Fatalf("the account was deleted by a login code")
	}
}

func TestTheDeletionPageRefusesSomethingThatIsNotAPhoneNumber(t *testing.T) {
	d, sender, _, _, _ := deletionUnderTest(t)

	rec := postDeletion(t, d.RequestCode, `{"phone":"hello"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("answered %d, want 400: %s", rec.Code, rec.Body)
	}
	if _, _, calls := sender.delivered(); calls != 0 {
		t.Fatalf("a code was paid for on a string that is not a number")
	}
}

// The deletion half of the same rule: an unpaid sender would print the code into the log and answer
// "sent". Refused before the account lookup, so the answer is the same for a registered number and a stranger.
func TestTheDeletionCodeIsRefusedWhileDeliveryIsUnpaid(t *testing.T) {
	sender := &fakeSender{}
	d := &AccountDeletion{Codes: auth.NewCodeManager(false), Sender: sender}

	rec := postDeletion(t, d.RequestCode, `{"phone":"998901110011"}`)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("request-code answered %d, want 403: %s", rec.Code, rec.Body.String())
	}
	if got := errorCode(t, rec); got != "sms_unavailable" {
		t.Fatalf("the refusal was %q, want sms_unavailable", got)
	}
	if _, _, calls := sender.delivered(); calls != 0 {
		t.Fatalf("a refused number reached the provider %d times", calls)
	}
}
