// package geo turns typed text into places and a point on the map into an address, through Yandex's
// free HTTP Geocoder and Geosuggest.
//
// **the keys never leave this server**: the app asks our api, and this package is the only code that
// knows Yandex is behind it. each product allows a thousand calls a day for the whole app, so a call is
// the last resort: answers are cached by normalized query, and DailyQuota counts a call before it is made.
package geo

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"domix/backend/internal/ratelimit"
)

const (
	EnvGeocoderKey = "YANDEX_GEOCODER_KEY"
	EnvSuggestKey  = "YANDEX_SUGGEST_KEY"
)

const (
	// the app's own floor: below it a query matches half of Tashkent and is not worth a call
	MinQueryRunes = 3
	MaxQueryRunes = 100

	// the terms allow a cache of up to 30 days. a day keeps a renamed street from lingering, and an
	// address asked once is usually asked again the same day.
	cacheTTL = 24 * time.Hour

	// how long past the ttl a copy may still answer when yandex cannot: a spent budget or an outage
	// then costs only the queries nobody asked this week. **the privacy policy promises an answer is
	// held at most a week**, ttl included - lengthen either and the policy has to move with it.
	cacheStaleFor = 6 * 24 * time.Hour

	// covers the reverse lookup's two calls back to back
	fetchTimeout = 12 * time.Second

	// how far the nearest building may be from a pin and still be its address
	houseRadiusMeters = 100
)

var (
	ErrNotFound    = errors.New("geo: nothing is there")
	ErrUnavailable = errors.New("geo: yandex could not be asked")
	ErrBudgetSpent = errors.New("geo: today's yandex budget is spent")

	// the whole app is calling yandex faster than its pace allows. answered as the same 429 a caller's
	// own bucket gives, since the app has one sentence for both
	ErrBusy = errors.New("geo: yandex calls are arriving faster than the app's pace")
)

// Place is one geocoder answer. Name and Description are yandex's own split of Address, the most
// specific part first.
type Place struct {
	Name        string
	Description string
	Address     string
	Latitude    float64
	Longitude   float64

	// the settlement around the place, empty when yandex names none - what the home header's pill shows
	City string
}

// Suggestion is one line under the field as it is typed. it has no coordinates: geosuggest sends none,
// and URI is what Service.Place resolves into a point once the line is tapped.
type Suggestion struct {
	Title    string
	Subtitle string
	URI      string
}

// Lang is the app's language, which is also the language yandex answers in.
type Lang string

const (
	Russian Lang = "ru"
	Uzbek   Lang = "uz"
)

// ParseLang reads the app's `lang`; an absent one is russian, the app's default.
func ParseLang(raw string) (Lang, bool) {
	switch Lang(raw) {
	case "", Russian:
		return Russian, true
	case Uzbek:
		return Uzbek, true
	}
	return "", false
}

// the geocoder wants a locale. uz_UZ is missing from its documented list but answers in latin uzbek.
func (l Lang) locale() string {
	if l == Uzbek {
		return "uz_UZ"
	}
	return "ru_RU"
}

// NormalizeQuery is the cache key and also the text sent to yandex, so a cached answer is exactly the
// answer for its key. case, spacing, ё and stray punctuation at the ends never change what is found.
func NormalizeQuery(raw string) string {
	text := strings.ToLower(strings.Join(strings.Fields(raw), " "))
	text = strings.ReplaceAll(text, "ё", "е")
	return strings.TrimFunc(text, func(r rune) bool {
		return unicode.IsPunct(r) || unicode.IsSpace(r)
	})
}

type Settings struct {
	GeocoderKey string
	SuggestKey  string
}

func SettingsFromEnv() Settings {
	return Settings{
		GeocoderKey: strings.TrimSpace(os.Getenv(EnvGeocoderKey)),
		SuggestKey:  strings.TrimSpace(os.Getenv(EnvSuggestKey)),
	}
}

// Quota spends one call to a yandex product before it is made, and answers false once the day's budget
// is gone.
type Quota interface {
	Spend(ctx context.Context, product string) (bool, error)
}

const (
	productGeocoder = "geocoder"
	productSuggest  = "suggest"
)

type Service struct {
	yandex *yandex
	quota  Quota

	// every copy of the app in one bucket, spent per yandex call and never per cached answer - see spend.
	// nil is no pace, which is what the tests build.
	pace *ratelimit.Limiter

	search  *cache[[]Place]
	suggest *cache[[]Suggestion]

	// nil is a held answer here: "nothing is there" is cached like any other, or every retry spends a call
	place   *cache[*Place]
	reverse *cache[*Place]
}

// New refuses to build without both keys: an api that boots green and answers every address lookup
// with an error is found out by the first owner creating a shop.
func New(s Settings, quota Quota, pace *ratelimit.Limiter) (*Service, error) {
	if s.GeocoderKey == "" {
		return nil, fmt.Errorf("geo: %s is not set", EnvGeocoderKey)
	}
	if s.SuggestKey == "" {
		return nil, fmt.Errorf("geo: %s is not set", EnvSuggestKey)
	}
	return newService(&yandex{
		geocoderKey: s.GeocoderKey,
		suggestKey:  s.SuggestKey,
		geocoderURL: geocoderURL,
		suggestURL:  suggestURL,
		// one client, so every call reuses a warm tls connection
		client: &http.Client{Timeout: 5 * time.Second},
	}, quota, pace), nil
}

func newService(y *yandex, quota Quota, pace *ratelimit.Limiter) *Service {
	return &Service{
		yandex:  y,
		quota:   quota,
		pace:    pace,
		search:  newCache[[]Place](cacheTTL, cacheStaleFor),
		suggest: newCache[[]Suggestion](cacheTTL, cacheStaleFor),
		place:   newCache[*Place](cacheTTL, cacheStaleFor),
		reverse: newCache[*Place](cacheTTL, cacheStaleFor),
	}
}

// Search is a submitted search: places matching the text, inside Tashkent and its oblast.
func (s *Service) Search(ctx context.Context, query string, lang Lang) ([]Place, error) {
	text := NormalizeQuery(query)
	if utf8.RuneCountInString(text) < MinQueryRunes {
		return nil, nil
	}
	return s.search.get(ctx, string(lang)+"|"+text, func(ctx context.Context) ([]Place, error) {
		if err := s.spend(ctx, productGeocoder); err != nil {
			return nil, err
		}
		return s.yandex.search(ctx, text, lang)
	})
}

// Suggest is the list under the field while it is typed.
func (s *Service) Suggest(ctx context.Context, query string, lang Lang) ([]Suggestion, error) {
	text := NormalizeQuery(query)
	if utf8.RuneCountInString(text) < MinQueryRunes {
		return nil, nil
	}
	return s.suggest.get(ctx, string(lang)+"|"+text, func(ctx context.Context) ([]Suggestion, error) {
		if err := s.spend(ctx, productSuggest); err != nil {
			return nil, err
		}
		return s.yandex.suggest(ctx, text, lang)
	})
}

// Place resolves a tapped suggestion's URI into a point.
func (s *Service) Place(ctx context.Context, uri string, lang Lang) (Place, error) {
	place, err := s.place.get(ctx, string(lang)+"|"+uri, func(ctx context.Context) (*Place, error) {
		if err := s.spend(ctx, productGeocoder); err != nil {
			return nil, err
		}
		return first(s.yandex.byURI(ctx, uri, lang))
	})
	return found(place, err)
}

// Reverse is the address of a pin. **the nearest building first**: a pin on a shop beside a park would
// otherwise answer with the park. only when no building is that close does a second call take the
// nearest object of any kind - a field outside a village still has a district and a city.
func (s *Service) Reverse(ctx context.Context, latitude, longitude float64, lang Lang) (Place, error) {
	// ~10 m, rounded before the call as well as for the key, so the cached answer is the one for its key
	latitude, longitude = roundTo4(latitude), roundTo4(longitude)
	key := fmt.Sprintf("%s|%.4f,%.4f", lang, latitude, longitude)

	place, err := s.reverse.get(ctx, key, func(ctx context.Context) (*Place, error) {
		if err := s.spend(ctx, productGeocoder); err != nil {
			return nil, err
		}
		house, err := first(s.yandex.reverse(ctx, latitude, longitude, lang, "house"))
		if err != nil {
			return nil, err
		}
		if house != nil && distanceMeters(latitude, longitude, house.Latitude, house.Longitude) <= houseRadiusMeters {
			return house, nil
		}

		if err := s.spend(ctx, productGeocoder); err != nil {
			return nil, err
		}
		return first(s.yandex.reverse(ctx, latitude, longitude, lang, ""))
	})
	return found(place, err)
}

// RetryAfter is when a caller refused with ErrBusy may ask again.
func (s *Service) RetryAfter() time.Duration {
	if s.pace == nil {
		return time.Second
	}
	return s.pace.RetryAfter()
}

// one key: the pace is a ceiling on the whole app, not on anybody in it
const paceKey = "app"

// a database that cannot count is a refusal too: the key is blocked for good if it goes over, and a
// missing suggestion is the cheaper failure
func (s *Service) spend(ctx context.Context, product string) error {
	// **the pace is spent here, on a call, and never on a request**: a cached answer does not reach this
	// line, so one free account looping can drain the pace without costing anybody else a lookup the
	// cache could answer. checked before the count, which is a write to postgres.
	if s.pace != nil && !s.pace.Allow(paceKey) {
		log.Printf("WARNING: yandex calls are arriving faster than the app's pace - refusing a %s call", product)
		return ErrBusy
	}

	ok, err := s.quota.Spend(ctx, product)
	if err != nil {
		return fmt.Errorf("%w: counting the %s call: %v", ErrUnavailable, product, err)
	}
	if !ok {
		log.Printf("WARNING: the %s budget for today is spent - address lookups answer from cache only", product)
		return ErrBudgetSpent
	}
	return nil
}

func first(places []Place, err error) (*Place, error) {
	if err != nil || len(places) == 0 {
		return nil, err
	}
	return &places[0], nil
}

func found(place *Place, err error) (Place, error) {
	if err != nil {
		return Place{}, err
	}
	if place == nil {
		return Place{}, ErrNotFound
	}
	return *place, nil
}

func roundTo4(v float64) float64 { return math.Round(v*1e4) / 1e4 }

// flat-earth is exact enough over a hundred metres
func distanceMeters(lat1, lon1, lat2, lon2 float64) float64 {
	const metersPerDegree = 111_320
	dLat := (lat2 - lat1) * metersPerDegree
	dLon := (lon2 - lon1) * metersPerDegree * math.Cos((lat1+lat2)/2*math.Pi/180)
	return math.Hypot(dLat, dLon)
}
