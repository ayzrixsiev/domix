package geo

// the fixtures under testdata are real answers, captured with the keys on 2026-11-06.

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"domix/backend/internal/ratelimit"
)

func fixture(t *testing.T, name string) []byte {
	t.Helper()
	body, err := os.ReadFile("testdata/" + name)
	if err != nil {
		t.Fatal(err)
	}
	return body
}

func TestNormalizeQueryFoldsWhatNeverChangesTheAnswer(t *testing.T) {
	cases := map[string]string{
		"  Амира   Тёмура, ":   "амира темура",
		"«Чорсу»":              "чорсу",
		"улица 8-Марта 12":     "улица 8-марта 12",
		"Amir Temur\tko'chasi": "amir temur ko'chasi",
	}
	for raw, want := range cases {
		if got := NormalizeQuery(raw); got != want {
			t.Errorf("NormalizeQuery(%q) = %q, want %q", raw, got, want)
		}
	}
}

func TestParseGeocoderReadsYandexsOwnSplitAndThePoint(t *testing.T) {
	places, err := parseGeocoder(fixture(t, "geocoder_search.json"))
	if err != nil {
		t.Fatal(err)
	}
	if len(places) != 5 {
		t.Fatalf("want all 5 results, got %d", len(places))
	}

	got := places[1]
	want := Place{
		Name:        "проспект Амира Темура",
		Description: "Мирабадский район, Ташкент, Узбекистан",
		Address:     "Узбекистан, Ташкент, Мирабадский район, проспект Амира Темура",
		// "lon lat" in the answer: swapped, every pin lands in the indian ocean
		Latitude:  41.300523,
		Longitude: 69.281964,
		City:      "Ташкент",
	}
	if got != want {
		t.Fatalf("got %+v\nwant %+v", got, want)
	}
	if places[4].City != "Чирчик" {
		t.Fatalf("an oblast town is its own city, got %q", places[4].City)
	}
}

func TestParseGeocoderNamesTheCityOfAPinInAPark(t *testing.T) {
	places, err := parseGeocoder(fixture(t, "geocoder_park.json"))
	if err != nil || len(places) != 1 {
		t.Fatalf("want one place, got %v (%v)", places, err)
	}
	if places[0].City != "Ташкент" {
		t.Fatalf("want the locality, got %q", places[0].City)
	}
}

// nothing found is an answer, and must not read as "could not ask"
func TestParseGeocoderAnswersNothingFoundWithAnEmptyList(t *testing.T) {
	places, err := parseGeocoder(fixture(t, "geocoder_nothing.json"))
	if err != nil {
		t.Fatalf("an empty answer is not an error: %v", err)
	}
	if places == nil || len(places) != 0 {
		t.Fatalf("want an empty, non-nil list, got %#v", places)
	}
}

func TestParseGeocoderCallsAnAnswerThatIsNotItsJSONUnavailable(t *testing.T) {
	if _, err := parseGeocoder([]byte("<html>captcha</html>")); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("want ErrUnavailable, got %v", err)
	}
}

func TestParseSuggestReadsTheLinesAndTheirURIs(t *testing.T) {
	suggestions, err := parseSuggest(fixture(t, "suggest.json"))
	if err != nil {
		t.Fatal(err)
	}
	if len(suggestions) != 5 {
		t.Fatalf("want all 5 lines, got %d", len(suggestions))
	}
	got := suggestions[2]
	if got.Title != "улица Амира Темура" || got.Subtitle != "Ахангаран, Ташкентская область" ||
		!strings.HasPrefix(got.URI, "ymapsbm1://geo?data=") {
		t.Fatalf("got %+v", got)
	}
}

func TestParseSuggestDropsALineThatCannotBecomeAPoint(t *testing.T) {
	suggestions, err := parseSuggest([]byte(`{"results":[{"title":{"text":"no uri"},"subtitle":{"text":"x"}}]}`))
	if err != nil || len(suggestions) != 0 {
		t.Fatalf("a line without a uri does nothing when tapped, got %+v (%v)", suggestions, err)
	}
}

// the docs: "если ничего не найдено, параметр может отсутствовать"
func TestParseSuggestReadsAMissingResultsKeyAsNothingFound(t *testing.T) {
	suggestions, err := parseSuggest([]byte(`{}`))
	if err != nil || suggestions == nil || len(suggestions) != 0 {
		t.Fatalf("want an empty, non-nil list, got %#v (%v)", suggestions, err)
	}
}

// countingQuota allows `left` calls, and records every one asked for
type countingQuota struct {
	mu    sync.Mutex
	left  int
	spent int
}

func (q *countingQuota) Spend(context.Context, string) (bool, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.left == 0 {
		return false, nil
	}
	q.left--
	q.spent++
	return true, nil
}

// fakeYandex answers every request with `answer`, and counts them
type fakeYandex struct {
	mu       sync.Mutex
	requests []*http.Request
	answer   func(r *http.Request) (int, []byte)
}

func (f *fakeYandex) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.requests)
}

func serviceUnderTest(t *testing.T, quota Quota, answer func(r *http.Request) (int, []byte)) (*Service, *fakeYandex) {
	t.Helper()
	fake := &fakeYandex{answer: answer}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fake.mu.Lock()
		fake.requests = append(fake.requests, r)
		fake.mu.Unlock()
		status, body := fake.answer(r)
		w.WriteHeader(status)
		w.Write(body)
	}))
	t.Cleanup(server.Close)

	return newService(&yandex{
		geocoderKey: "geocoder-key",
		suggestKey:  "suggest-key",
		geocoderURL: server.URL + "/geocode",
		suggestURL:  server.URL + "/suggest",
		client:      server.Client(),
	}, quota, nil), fake
}

func TestSpellingsOfOneQueryShareOneCallAndOneUnitOfBudget(t *testing.T) {
	quota := &countingQuota{left: 10}
	search := fixture(t, "geocoder_search.json")
	service, fake := serviceUnderTest(t, quota, func(*http.Request) (int, []byte) { return 200, search })

	for _, typed := range []string{"Амира Темура", "  амира   темура", "АМИРА ТЕМУРА,"} {
		places, err := service.Search(context.Background(), typed, Russian)
		if err != nil || len(places) != 5 {
			t.Fatalf("%q: got %d places (%v)", typed, len(places), err)
		}
	}
	if fake.count() != 1 || quota.spent != 1 {
		t.Fatalf("want one call and one unit spent, got %d calls and %d units", fake.count(), quota.spent)
	}
	if got := fake.requests[0].URL.Query().Get("geocode"); got != "амира темура" {
		t.Fatalf("yandex must be sent the normalized text the answer is cached under, got %q", got)
	}

	// the language is part of the key: the same words in uzbek are another answer
	if _, err := service.Search(context.Background(), "амира темура", Uzbek); err != nil {
		t.Fatal(err)
	}
	if fake.count() != 2 {
		t.Fatalf("want a second call for the other language, got %d", fake.count())
	}
}

func TestASpentBudgetRefusesWithoutCallingYandex(t *testing.T) {
	service, fake := serviceUnderTest(t, &countingQuota{left: 0}, func(*http.Request) (int, []byte) {
		return 200, []byte(`{"results":[]}`)
	})

	if _, err := service.Suggest(context.Background(), "чорсу", Russian); !errors.Is(err, ErrBudgetSpent) {
		t.Fatalf("want ErrBudgetSpent, got %v", err)
	}
	if fake.count() != 0 {
		t.Fatalf("a spent budget must never reach yandex, got %d calls", fake.count())
	}
}

func TestAQueryTooShortSpendsNothing(t *testing.T) {
	quota := &countingQuota{left: 10}
	service, fake := serviceUnderTest(t, quota, func(*http.Request) (int, []byte) { return 200, nil })

	suggestions, err := service.Suggest(context.Background(), " це, ", Russian)
	if err != nil || len(suggestions) != 0 || fake.count() != 0 || quota.spent != 0 {
		t.Fatalf("want nothing asked, got %v (%v), %d calls", suggestions, err, fake.count())
	}
}

// **a failure cached would answer "could not ask" for a day after yandex came back**
func TestAFailedCallIsNotCachedButNothingFoundIs(t *testing.T) {
	quota := &countingQuota{left: 10}
	status := http.StatusInternalServerError
	nothing := fixture(t, "geocoder_nothing.json")
	service, fake := serviceUnderTest(t, quota, func(*http.Request) (int, []byte) { return status, nothing })

	if _, err := service.Search(context.Background(), "нигдебург", Russian); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("want ErrUnavailable, got %v", err)
	}

	status = http.StatusOK
	for range 2 {
		places, err := service.Search(context.Background(), "нигдебург", Russian)
		if err != nil || len(places) != 0 {
			t.Fatalf("want an empty answer, got %v (%v)", places, err)
		}
	}
	if fake.count() != 2 {
		t.Fatalf("want the failure retried once and the empty answer cached, got %d calls", fake.count())
	}
}

func TestReverseTakesTheBuildingUnderThePin(t *testing.T) {
	quota := &countingQuota{left: 10}
	house := fixture(t, "geocoder_house.json")
	service, fake := serviceUnderTest(t, quota, func(*http.Request) (int, []byte) { return 200, house })

	// ~35 m from the building's own point
	place, err := service.Reverse(context.Background(), 41.300523, 69.281964, Russian)
	if err != nil {
		t.Fatal(err)
	}
	if place.Address != "Узбекистан, Ташкент, Мирабадский район, проспект Амира Темура, 39" || place.City != "Ташкент" {
		t.Fatalf("got %+v", place)
	}
	if fake.count() != 1 || fake.requests[0].URL.Query().Get("kind") != "house" {
		t.Fatalf("want one call for the nearest house, got %d", fake.count())
	}
}

func TestReverseFallsBackToAnyObjectWhenNoBuildingIsNear(t *testing.T) {
	quota := &countingQuota{left: 10}
	nothing, park := fixture(t, "geocoder_nothing.json"), fixture(t, "geocoder_park.json")
	service, fake := serviceUnderTest(t, quota, func(r *http.Request) (int, []byte) {
		if r.URL.Query().Get("kind") == "house" {
			return 200, nothing
		}
		return 200, park
	})

	place, err := service.Reverse(context.Background(), 41.2995, 69.2401, Russian)
	if err != nil {
		t.Fatal(err)
	}
	if place.City != "Ташкент" || !strings.Contains(place.Address, "Национальный парк") {
		t.Fatalf("got %+v", place)
	}
	if fake.count() != 2 || quota.spent != 2 {
		t.Fatalf("both calls are counted: got %d calls, %d units", fake.count(), quota.spent)
	}
}

func TestReverseWithNothingAnywhereIsNotFoundAndCached(t *testing.T) {
	nothing := fixture(t, "geocoder_nothing.json")
	service, fake := serviceUnderTest(t, &countingQuota{left: 10}, func(*http.Request) (int, []byte) { return 200, nothing })

	for range 2 {
		if _, err := service.Reverse(context.Background(), 42.3, 63.5, Russian); !errors.Is(err, ErrNotFound) {
			t.Fatalf("want ErrNotFound, got %v", err)
		}
	}
	if fake.count() != 2 {
		t.Fatalf("want the two calls of one lookup, then the cache, got %d", fake.count())
	}
}

// **the key travels in the url, and a *url.Error prints the url**
func TestAnUnreachableYandexNeverPutsTheKeyInTheError(t *testing.T) {
	service := newService(&yandex{
		geocoderKey: "secret-geocoder-key",
		geocoderURL: "http://127.0.0.1:1/geocode",
		client:      http.DefaultClient,
	}, &countingQuota{left: 1}, nil)

	_, err := service.Search(context.Background(), "чорсу", Russian)
	if !errors.Is(err, ErrUnavailable) {
		t.Fatalf("want ErrUnavailable, got %v", err)
	}
	if strings.Contains(err.Error(), "secret-geocoder-key") {
		t.Fatalf("the api key leaked into the error: %v", err)
	}
}

// **the pace is spent on yandex calls, not on requests**: an account looping past it must not cost
// anybody a lookup the cache already holds, and a refused call must cost no budget
func TestThePaceRefusesACallButNeverACachedAnswer(t *testing.T) {
	quota := &countingQuota{left: 10}
	search := fixture(t, "geocoder_search.json")
	service, fake := serviceUnderTest(t, quota, func(*http.Request) (int, []byte) { return 200, search })
	service.pace = ratelimit.New(0, 1, time.Minute) // one call, then never another

	if _, err := service.Search(context.Background(), "амира темура", Russian); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Search(context.Background(), "чорсу", Russian); !errors.Is(err, ErrBusy) {
		t.Fatalf("a call past the pace: want ErrBusy, got %v", err)
	}
	if places, err := service.Search(context.Background(), "Амира Темура", Russian); err != nil || len(places) != 5 {
		t.Fatalf("a cached answer was refused along with the call: %d places (%v)", len(places), err)
	}
	if fake.count() != 1 || quota.spent != 1 {
		t.Fatalf("want one call and one unit spent, got %d calls and %d units", fake.count(), quota.spent)
	}
}

// **a failure is shared with the callers queued behind it**: on a slow yandex day each retry would be
// another unit spent and another wait for the caller after it
func TestCallersQueuedBehindAFailedCallShareItsFailure(t *testing.T) {
	quota := &countingQuota{left: 10}
	service, fake := serviceUnderTest(t, quota, func(*http.Request) (int, []byte) {
		// long enough that every other caller is queued on the key by the time this fails
		time.Sleep(100 * time.Millisecond)
		return http.StatusInternalServerError, nil
	})

	var callers sync.WaitGroup
	var failed atomic.Int32
	for range 5 {
		callers.Add(1)
		go func() {
			defer callers.Done()
			if _, err := service.Suggest(context.Background(), "юнусабад", Russian); errors.Is(err, ErrUnavailable) {
				failed.Add(1)
			}
		}()
	}
	callers.Wait()

	if failed.Load() != 5 {
		t.Fatalf("%d of 5 callers were told yandex could not be asked", failed.Load())
	}
	if fake.count() != 1 || quota.spent != 1 {
		t.Fatalf("five queued callers made %d calls and spent %d units, want one of each", fake.count(), quota.spent)
	}
}
