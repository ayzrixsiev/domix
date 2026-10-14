package endpoints

// the phone-code login at the http boundary: the json the flutter side has to match, and the refusals
// it has to be able to tell apart. most need no database - a code is minted, checked and refused in
// ram against a fake provider - and only the last few, where a number becomes a users row, need one.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5"

	"domix/backend/db"
	"domix/backend/internal/auth"
)

// fakeSender stands in for verify.Sender. **No test in this package may reach Telegram or Eskiz** -
// a test that sends a real message costs money every time CI runs it, and would fail on any machine
// without credentials.
type fakeSender struct {
	mu    sync.Mutex
	calls int
	phone string
	code  string
	fail  error
}

func (f *fakeSender) Send(_ context.Context, phone, code string) error {
	f.mu.Lock()
	defer f.mu.Unlock()

	f.calls++
	if f.fail != nil {
		return f.fail
	}
	f.phone, f.code = phone, code
	return nil
}

func (f *fakeSender) delivered() (phone, code string, calls int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.phone, f.code, f.calls
}

func (f *fakeSender) refuse(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.fail = err
}

// a login with no database behind it. every path that ends before a users row is touched can be
// tested this way, which is most of them.
func codeUnderTest() (*PhoneAuth, *fakeSender) {
	sender := &fakeSender{}
	return &PhoneAuth{Codes: auth.NewCodeManager(true), Sender: sender, JWTSecret: testJWTSecret}, sender
}

func postAuth(t *testing.T, handler http.HandlerFunc, target string, body map[string]string) *httptest.ResponseRecorder {
	t.Helper()

	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("encoding the request: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, target, strings.NewReader(string(encoded)))
	rec := httptest.NewRecorder()
	handler(rec, req)
	return rec
}

// errorCode pulls the machine-readable code out of an error answer. The app is ru/uz only and never
// shows the english sentence - it switches on this string - so it is the part worth asserting.
func errorCode(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()

	var body struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decoding the error answer: %v\nbody: %s", err, rec.Body.String())
	}
	return body.Code
}

// **The whole flow hangs off this.** The code is stored under the canonical number, so a request
// that keys it under one spelling and a verification that looks it up under another is a silent
// miss - reported to the user as "you never asked for a code", which sends them round the loop
// forever. Both endpoints normalize, with the same function; this is the request half.
func TestRequestCodeKeysEverythingByTheCanonicalNumber(t *testing.T) {
	for _, typed := range []string{"901234567", "998901234567", "+998 90 123 45 67", "(90) 123-45-67"} {
		t.Run(typed, func(t *testing.T) {
			phoneAuth, sender := codeUnderTest()

			rec := postAuth(t, phoneAuth.RequestCode, "/api/auth/request-code",
				map[string]string{"phone": typed, "name": "Аброр", "role": "shop_owner"})
			if rec.Code != http.StatusOK {
				t.Fatalf("request-code answered %d, want 200: %s", rec.Code, rec.Body.String())
			}

			delivered, code, calls := sender.delivered()
			if calls != 1 {
				t.Fatalf("the provider was called %d times, want once", calls)
			}
			if delivered != "998901234567" {
				t.Fatalf("the provider was handed %q, want the canonical 998901234567", delivered)
			}

			// and the entry is *findable* from a different spelling, which is the pair that matters.
			// asked with a deliberately wrong code so this stops before the database: "code_invalid"
			// means the pending entry was found and the digits were compared, "code_not_found" means
			// the two spellings keyed different map entries - the silent failure this guards.
			verified := postAuth(t, phoneAuth.Verify, "/api/auth/verify",
				map[string]string{"phone": "+998 90 123 45 67", "code": wrongDigits(code)})
			if got := errorCode(t, verified); got != "code_invalid" {
				t.Fatalf("verifying under another spelling answered %q, want code_invalid", got)
			}
		})
	}
}

// The answer the phone screen renders. Two countdowns in seconds, so the app does not hardcode
// numbers that would then have to be changed in two repositories at once.
func TestRequestCodeAnswersWithBothCountdowns(t *testing.T) {
	phoneAuth, _ := codeUnderTest()

	rec := postAuth(t, phoneAuth.RequestCode, "/api/auth/request-code",
		map[string]string{"phone": "901234567", "name": "Аброр", "role": "customer"})
	if rec.Code != http.StatusOK {
		t.Fatalf("request-code answered %d, want 200: %s", rec.Code, rec.Body.String())
	}

	var body struct {
		Sent        bool   `json:"sent"`
		Phone       string `json:"phone"`
		ExpiresIn   int    `json:"expires_in"`
		ResendAfter int    `json:"resend_after"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decoding the answer: %v\nbody: %s", err, rec.Body.String())
	}

	if !body.Sent || body.Phone != "998901234567" {
		t.Fatalf("answer was %+v", body)
	}
	if body.ExpiresIn != int(auth.CodeTTL.Seconds()) || body.ResendAfter != int(auth.ResendCooldown.Seconds()) {
		t.Fatalf("countdowns are expires_in=%d resend_after=%d, want %d and %d",
			body.ExpiresIn, body.ResendAfter, int(auth.CodeTTL.Seconds()), int(auth.ResendCooldown.Seconds()))
	}
}

// Every send is paid for, so a number that cannot be one must never reach the provider.
func TestRequestCodeRefusesWhatIsNotAPhoneNumber(t *testing.T) {
	for _, typed := range []string{"", "12345", "79161234567", "8901234567", "не телефон"} {
		t.Run(typed, func(t *testing.T) {
			phoneAuth, sender := codeUnderTest()

			rec := postAuth(t, phoneAuth.RequestCode, "/api/auth/request-code",
				map[string]string{"phone": typed, "name": "Аброр", "role": "customer"})

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("phone %q answered %d, want 400", typed, rec.Code)
			}
			if got := errorCode(t, rec); got != "invalid_phone" {
				t.Fatalf("phone %q answered code %q, want invalid_phone", typed, got)
			}
			if _, _, calls := sender.delivered(); calls != 0 {
				t.Fatalf("phone %q reached the provider %d times", typed, calls)
			}
		})
	}
}

// A user tapping "отправить" twice must not be billed twice, and must be told how long to wait
// rather than just being refused - the app draws the number as a countdown.
func TestASecondRequestIsHeldOffWithACountdown(t *testing.T) {
	phoneAuth, sender := codeUnderTest()
	body := map[string]string{"phone": "901234567", "name": "Аброр", "role": "customer"}

	if rec := postAuth(t, phoneAuth.RequestCode, "/api/auth/request-code", body); rec.Code != http.StatusOK {
		t.Fatalf("the first request answered %d, want 200", rec.Code)
	}

	rec := postAuth(t, phoneAuth.RequestCode, "/api/auth/request-code", body)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("the second request answered %d, want 429", rec.Code)
	}
	if got := errorCode(t, rec); got != "code_cooldown" {
		t.Fatalf("the second request answered code %q, want code_cooldown", got)
	}

	var answer struct {
		RetryAfter int `json:"retry_after"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &answer); err != nil {
		t.Fatalf("decoding the cooldown answer: %v", err)
	}
	// never zero: "retry in 0 seconds" is what makes a client retry immediately, which is the loop
	// the cooldown exists to prevent
	if answer.RetryAfter <= 0 {
		t.Fatalf("retry_after is %d", answer.RetryAfter)
	}
	if header := rec.Header().Get("Retry-After"); header == "" {
		t.Fatal("no Retry-After header on the 429")
	}

	if _, _, calls := sender.delivered(); calls != 1 {
		t.Fatalf("the provider was called %d times, want once", calls)
	}
}

// A provider outage must not lock the number out for a minute: the pending entry goes with the
// failed send, so the user can press the button again immediately instead of waiting for a message
// that was never sent.
func TestAFailedSendDoesNotTrapTheNumberInCooldown(t *testing.T) {
	phoneAuth, sender := codeUnderTest()
	body := map[string]string{"phone": "901234567", "name": "Аброр", "role": "customer"}

	sender.refuse(errors.New("the gateway is down"))

	rec := postAuth(t, phoneAuth.RequestCode, "/api/auth/request-code", body)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("a refused send answered %d, want 502", rec.Code)
	}
	if got := errorCode(t, rec); got != "code_not_sent" {
		t.Fatalf("a refused send answered code %q, want code_not_sent", got)
	}

	sender.refuse(nil)

	if rec := postAuth(t, phoneAuth.RequestCode, "/api/auth/request-code", body); rec.Code != http.StatusOK {
		t.Fatalf("the retry after a failed send answered %d, want 200: %s", rec.Code, rec.Body.String())
	}
}

// Four refusals, four codes. "That code is wrong" and "that code is dead" send the user to
// different screens, and collapsing them into one message is how somebody ends up typing into a
// keypad that will never accept anything again.
func TestVerifyTellsItsRefusalsApart(t *testing.T) {
	cases := []struct {
		name string
		// typed runs against a manager that has already sent one code, and returns what to type
		typed      func(t *testing.T, p *PhoneAuth, sent string) (phone, code string)
		wantStatus int
		wantCode   string
	}{
		{
			name: "one digit off",
			typed: func(_ *testing.T, _ *PhoneAuth, sent string) (string, string) {
				return "901234567", wrongDigits(sent)
			},
			wantStatus: http.StatusUnauthorized,
			wantCode:   "code_invalid",
		},
		{
			name: "a number nobody asked a code for",
			typed: func(_ *testing.T, _ *PhoneAuth, _ string) (string, string) {
				return "901234599", "123456"
			},
			wantStatus: http.StatusBadRequest,
			wantCode:   "code_not_found",
		},
		{
			name: "the third wrong guess",
			typed: func(t *testing.T, p *PhoneAuth, sent string) (string, string) {
				wrong := wrongDigits(sent)
				for guess := 1; guess < auth.MaxCodeAttempts; guess++ {
					rec := postAuth(t, p.Verify, "/api/auth/verify",
						map[string]string{"phone": "901234567", "code": wrong})
					if got := errorCode(t, rec); got != "code_invalid" {
						t.Fatalf("guess %d answered %q, want code_invalid", guess, got)
					}
				}
				return "901234567", wrong
			},
			wantStatus: http.StatusUnauthorized,
			wantCode:   "code_attempts_exhausted",
		},
		{
			name: "not a phone number",
			typed: func(_ *testing.T, _ *PhoneAuth, sent string) (string, string) {
				return "12345", sent
			},
			wantStatus: http.StatusBadRequest,
			wantCode:   "invalid_phone",
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			phoneAuth, sender := codeUnderTest()

			if rec := postAuth(t, phoneAuth.RequestCode, "/api/auth/request-code",
				map[string]string{"phone": "901234567", "name": "Аброр", "role": "customer"}); rec.Code != http.StatusOK {
				t.Fatalf("request-code answered %d", rec.Code)
			}
			_, sent, _ := sender.delivered()

			phone, code := c.typed(t, phoneAuth, sent)
			rec := postAuth(t, phoneAuth.Verify, "/api/auth/verify",
				map[string]string{"phone": phone, "code": code})

			if rec.Code != c.wantStatus {
				t.Fatalf("answered %d, want %d: %s", rec.Code, c.wantStatus, rec.Body.String())
			}
			if got := errorCode(t, rec); got != c.wantCode {
				t.Fatalf("answered code %q, want %q", got, c.wantCode)
			}
		})
	}
}

// wrongDigits is the sent code with its last digit moved on by one.
func wrongDigits(sent string) string {
	last := sent[len(sent)-1]
	if last == '9' {
		last = '0'
	} else {
		last++
	}
	return sent[:len(sent)-1] + string(last)
}

// ---------------------------------------------------------------------------------------------
// from here down a real database is needed: a proven number becomes a users row.

func phoneAuthUnderTest(t *testing.T) (*PhoneAuth, *fakeSender, context.Context, pgx.Tx, *db.Queries) {
	t.Helper()

	_, ctx, tx, queries := homeUnderTest(t)
	sender := &fakeSender{}

	return &PhoneAuth{
		Queries:   queries,
		Codes:     auth.NewCodeManager(true),
		Sender:    sender,
		JWTSecret: testJWTSecret,
	}, sender, ctx, tx, queries
}

// a number no row in the founder's database can already hold. the transaction is rolled back, but a
// fixed number would still collide with a real account on his laptop, and users.phone is UNIQUE.
func unusedPhone() string {
	return fmt.Sprintf("9989%08d", rand.IntN(100_000_000))
}

// signInWithACode walks the whole flow the app walks: ask for a code, read it off the provider,
// type it back. It returns the decoded answer.
func signInWithACode(t *testing.T, ctx context.Context, p *PhoneAuth, sender *fakeSender, phone, name, role string) PhoneAuthResponse {
	t.Helper()

	// a fresh manager per sign-in: the resend cooldown is real, and a test that signs the same
	// number in twice would otherwise be refused the second code
	p.Codes = auth.NewCodeManager(true)

	rec := postAuthWithContext(t, ctx, p.RequestCode, "/api/auth/request-code",
		map[string]string{"phone": phone, "name": name, "role": role})
	if rec.Code != http.StatusOK {
		t.Fatalf("request-code answered %d, want 200: %s", rec.Code, rec.Body.String())
	}

	_, code, _ := sender.delivered()

	rec = postAuthWithContext(t, ctx, p.Verify, "/api/auth/verify",
		map[string]string{"phone": phone, "code": code})
	if rec.Code != http.StatusOK {
		t.Fatalf("verify answered %d, want 200: %s", rec.Code, rec.Body.String())
	}

	var answer PhoneAuthResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &answer); err != nil {
		t.Fatalf("decoding the sign-in answer: %v\nbody: %s", err, rec.Body.String())
	}
	return answer
}

// the handler reads its deadline off the request context, so the request has to carry the
// transaction-bound one - otherwise dbctx.WithTimeout branches off context.Background() and the
// query runs on a connection the transaction does not own. Same reason as getJSON in home_test.go.
func postAuthWithContext(t *testing.T, ctx context.Context, handler http.HandlerFunc, target string, body map[string]string) *httptest.ResponseRecorder {
	t.Helper()

	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("encoding the request: %v", err)
	}

	req := httptest.NewRequestWithContext(ctx, http.MethodPost, target, strings.NewReader(string(encoded)))
	rec := httptest.NewRecorder()
	handler(rec, req)
	return rec
}

// The end of the flow: a correct code creates the account and mints a token the rest of the api
// accepts. The token is the only thing the app keeps, so if the claims are wrong every later
// request is a 401 with nothing to show why.
func TestACorrectCodeCreatesTheAccountAndSignsAToken(t *testing.T) {
	phoneAuth, sender, ctx, tx, _ := phoneAuthUnderTest(t)
	phone := unusedPhone()

	answer := signInWithACode(t, ctx, phoneAuth, sender, phone, "Аброр", "shop_owner")

	if answer.User.Phone != phone || answer.User.Name != "Аброр" || answer.User.Role != "shop_owner" {
		t.Fatalf("signed in as %+v", answer.User)
	}

	claims, err := auth.ValidateJWT(answer.Token, testJWTSecret)
	if err != nil {
		t.Fatalf("the token this endpoint minted does not validate: %v", err)
	}
	if claims.UserID != answer.User.ID || claims.Phone != phone {
		t.Fatalf("token claims are user %d / %q, want %d / %q", claims.UserID, claims.Phone, answer.User.ID, phone)
	}

	// the number is stored canonical, which is what makes the next sign-in find this row
	var stored string
	if err := tx.QueryRow(ctx, "SELECT phone FROM users WHERE id = $1", answer.User.ID).Scan(&stored); err != nil {
		t.Fatalf("reading back the row: %v", err)
	}
	if stored != phone {
		t.Fatalf("users.phone holds %q, want %q", stored, phone)
	}
}

// Signing in again is a login, not a registration - one row, whatever was typed on the way in. The
// role only ever goes up: a shop owner who taps "я покупатель" must not be demoted out of the shops
// they own.
func TestSigningInAgainFindsTheSameAccount(t *testing.T) {
	phoneAuth, sender, ctx, tx, _ := phoneAuthUnderTest(t)
	phone := unusedPhone()

	first := signInWithACode(t, ctx, phoneAuth, sender, phone, "Аброр", "shop_owner")
	second := signInWithACode(t, ctx, phoneAuth, sender, phone, "Аброр Рустамов", "customer")

	if second.User.ID != first.User.ID {
		t.Fatalf("the second sign-in created user %d, the first was %d", second.User.ID, first.User.ID)
	}
	if second.User.Role != "shop_owner" {
		t.Fatalf("the second sign-in left the role as %q, want shop_owner", second.User.Role)
	}
	// the name is theirs to change, either direction
	if second.User.Name != "Аброр Рустамов" {
		t.Fatalf("the name is %q, want the one typed this time", second.User.Name)
	}

	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE phone = $1", phone); n != 1 {
		t.Fatalf("%d rows for one number", n)
	}
}

// **users.phone is the identity column and it holds exactly one spelling.** Migration 000003
// normalized the rows the retired telegram handshake had written with a leading '+', and this is
// what stops a second spelling creeping back in: two spellings of one number in a UNIQUE column are
// two accounts, and the second owns none of the first one's shops.
func TestSigningInStoresTheCanonicalSpellingOfTheNumber(t *testing.T) {
	phoneAuth, sender, ctx, tx, _ := phoneAuthUnderTest(t)
	phone := unusedPhone()

	// every shape a person types, ending on the same row
	for _, typed := range []string{"+" + phone, phone[3:], "+998 " + phone[3:5] + " " + phone[5:8] + " " + phone[8:10] + " " + phone[10:]} {
		answer := signInWithACode(t, ctx, phoneAuth, sender, typed, "Аброр", "customer")
		if answer.User.Phone != phone {
			t.Fatalf("typing %q stored %q, want the canonical %q", typed, answer.User.Phone, phone)
		}
	}

	if n := countRows(t, ctx, tx, "SELECT COUNT(*) FROM users WHERE phone = $1", phone); n != 1 {
		t.Fatalf("%d rows for one number", n)
	}
}

// **The Play review account at the http boundary.** The reviewer is not a special caller - they walk
// the same two endpoints every user walks - so what has to hold is that the provider is never asked
// to deliver anything, and that the code they were handed in the Play Console actually signs them
// in. Without this the review stops on the login screen and the listing is refused.
func TestTheReviewAccountSignsInWithoutAnythingBeingDelivered(t *testing.T) {
	phoneAuth, sender, ctx, _, queries := phoneAuthUnderTest(t)

	const code = "424242"
	phone := unusedPhone()
	phoneAuth.Codes = auth.NewCodeManager(true).WithReviewAccount(phone, code)

	rec := postAuthWithContext(t, ctx, phoneAuth.RequestCode, "/api/auth/request-code",
		map[string]string{"phone": phone, "name": "Google", "role": "customer"})
	if rec.Code != http.StatusOK {
		t.Fatalf("request-code answered %d, want 200: %s", rec.Code, rec.Body.String())
	}

	// the point of the whole mechanism: there is no Telegram account on this number to deliver to
	if _, _, calls := sender.delivered(); calls != 0 {
		t.Fatalf("the provider was called %d times for the review account, want never", calls)
	}

	rec = postAuthWithContext(t, ctx, phoneAuth.Verify, "/api/auth/verify",
		map[string]string{"phone": phone, "code": code})
	if rec.Code != http.StatusOK {
		t.Fatalf("the armed code answered %d, want 200: %s", rec.Code, rec.Body.String())
	}

	var answer PhoneAuthResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &answer); err != nil {
		t.Fatalf("decoding the sign-in answer: %v\nbody: %s", err, rec.Body.String())
	}
	if answer.Token == "" {
		t.Fatal("the review account signed in without being given a token")
	}

	// **it is an ordinary account, not a privileged one.** the bypass decides which code opens one
	// number, never what that account may do - the signup's role mapping is untouched.
	user, err := queries.GetUserByPhone(ctx, phone)
	if err != nil {
		t.Fatalf("the review account left no users row: %v", err)
	}
	if user.Role != "customer" {
		t.Fatalf("the review account was registered as %q, want customer", user.Role)
	}
}

// The same endpoint with nothing armed, which is how production runs once the review is over: a code
// is minted, handed to the provider, and is not the one anybody could have guessed.
func TestWithNoReviewAccountEveryLoginStillGoesThroughTheProvider(t *testing.T) {
	phoneAuth, sender := codeUnderTest()

	rec := postAuth(t, phoneAuth.RequestCode, "/api/auth/request-code",
		map[string]string{"phone": "998901110000", "name": "Аброр", "role": "customer"})
	if rec.Code != http.StatusOK {
		t.Fatalf("request-code answered %d, want 200: %s", rec.Code, rec.Body.String())
	}
	if _, _, calls := sender.delivered(); calls != 1 {
		t.Fatalf("the provider was called %d times, want once", calls)
	}
}
