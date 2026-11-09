package endpoints

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"domix/backend/internal/geo"
	"domix/backend/internal/ratelimit"
)

type unlimitedQuota struct{}

func (unlimitedQuota) Spend(context.Context, string) (bool, error) { return true, nil }

// **the app has one sentence for a refusal**, so the app's pace on yandex calls has to answer exactly
// what a caller's own bucket does - code, status and body - or it reads as some other failure.
func TestARefusedYandexCallAnswersLikeTheCallersOwnBucket(t *testing.T) {
	pace := ratelimit.New(300.0/3600, 1, time.Minute)
	service, err := geo.New(geo.Settings{GeocoderKey: "k", SuggestKey: "k"}, unlimitedQuota{}, pace)
	if err != nil {
		t.Fatal(err)
	}

	paced := httptest.NewRecorder()
	(&Geo{Service: service}).writeError(paced, httptest.NewRequest(http.MethodGet, "/api/geo/suggest", nil),
		"address suggestions", geo.ErrBusy)

	bucket := pace.Wrap(func(http.ResponseWriter, *http.Request) {})
	bucket(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/geo/suggest", nil))
	limited := httptest.NewRecorder()
	bucket(limited, httptest.NewRequest(http.MethodGet, "/api/geo/suggest", nil))

	if paced.Code != http.StatusTooManyRequests || limited.Code != http.StatusTooManyRequests {
		t.Fatalf("want two 429s, got %d and %d", paced.Code, limited.Code)
	}
	if paced.Body.String() != limited.Body.String() {
		t.Fatalf("the pace answered %s, the caller's bucket %s", paced.Body, limited.Body)
	}
	if got := paced.Header().Get("Retry-After"); got != "12" {
		t.Fatalf("Retry-After %q, want 12 - one token at three hundred an hour", got)
	}
}
