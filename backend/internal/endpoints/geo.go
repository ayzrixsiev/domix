package endpoints

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"domix/backend/internal/geo"
	"domix/backend/internal/ratelimit"
)

// Geo is address search for the map and the location picker, answered by yandex through internal/geo.
//
// **"no such address" and "could not ask" are different answers**: an empty list or a 404 is the first,
// a 502 or a 503 the second, and the app says a different sentence for each.
type Geo struct {
	Service *geo.Service
}

// the opaque handle a suggestion carries. bounded so a caller cannot make us send yandex a megabyte
const maxPlaceURILen = 512

// GET /api/geo/search?q=&lang= - a submitted search, places with their points
func (g *Geo) Search(w http.ResponseWriter, r *http.Request) {
	query, lang, ok := readGeoQuery(w, r)
	if !ok {
		return
	}

	places, err := g.Service.Search(r.Context(), query, lang)
	if err != nil {
		g.writeError(w, r, "address search", err)
		return
	}

	response := make([]PlaceResponse, 0, len(places))
	for _, place := range places {
		response = append(response, placeFrom(place))
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// GET /api/geo/suggest?q=&lang= - the lines under the field as it is typed. a query too short to look
// up is an empty list, not a 400: that is the ordinary state of a half-typed word.
func (g *Geo) Suggest(w http.ResponseWriter, r *http.Request) {
	query, lang, ok := readGeoQuery(w, r)
	if !ok {
		return
	}

	suggestions, err := g.Service.Suggest(r.Context(), query, lang)
	if err != nil {
		g.writeError(w, r, "address suggestions", err)
		return
	}

	response := make([]SuggestionResponse, 0, len(suggestions))
	for _, suggestion := range suggestions {
		response = append(response, suggestionFrom(suggestion))
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// GET /api/geo/place?uri=&lang= - a tapped suggestion, as a point
func (g *Geo) Place(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	lang, ok := readGeoLang(w, r)
	if !ok {
		return
	}

	uri := strings.TrimSpace(r.URL.Query().Get("uri"))
	if !strings.HasPrefix(uri, "ymapsbm1://") || len(uri) > maxPlaceURILen {
		writeAPIError(w, http.StatusBadRequest, "invalid_uri", "uri must be one a suggestion carried")
		return
	}

	place, err := g.Service.Place(r.Context(), uri, lang)
	if err != nil {
		g.writeError(w, r, "a suggested place", err)
		return
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(placeFrom(place))
}

// GET /api/geo/reverse?lat=&lon=&lang= - a pin's address and city
func (g *Geo) Reverse(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	lang, ok := readGeoLang(w, r)
	if !ok {
		return
	}

	latitude, latErr := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	longitude, lonErr := strconv.ParseFloat(r.URL.Query().Get("lon"), 64)
	if latErr != nil || lonErr != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_location", "lat and lon must be numbers")
		return
	}
	if accessErr := validateCoordinates(latitude, longitude); accessErr != nil {
		accessErr.write(w)
		return
	}

	place, err := g.Service.Reverse(r.Context(), latitude, longitude, lang)
	if err != nil {
		g.writeError(w, r, "a pin's address", err)
		return
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(addressFrom(place))
}

func readGeoQuery(w http.ResponseWriter, r *http.Request) (string, geo.Lang, bool) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return "", "", false
	}
	lang, ok := readGeoLang(w, r)
	if !ok {
		return "", "", false
	}

	query := r.URL.Query().Get("q")
	if utf8.RuneCountInString(query) > geo.MaxQueryRunes {
		writeAPIError(w, http.StatusBadRequest, "query_too_long", "search query is too long")
		return "", "", false
	}
	return query, lang, true
}

func readGeoLang(w http.ResponseWriter, r *http.Request) (geo.Lang, bool) {
	lang, ok := geo.ParseLang(r.URL.Query().Get("lang"))
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "invalid_lang", "lang must be ru or uz")
	}
	return lang, ok
}

func (g *Geo) writeError(w http.ResponseWriter, r *http.Request, what string, err error) {
	switch {
	case errors.Is(err, geo.ErrNotFound):
		writeAPIError(w, http.StatusNotFound, "address_not_found", "nothing is there")
	case errors.Is(err, geo.ErrBusy):
		// byte for byte what the caller's own bucket answers, so the app needs no second sentence
		ratelimit.Refuse(w, g.Service.RetryAfter())
	case errors.Is(err, geo.ErrBudgetSpent):
		// geo.Service has already said so in the log, once per refused call
		writeAPIError(w, http.StatusServiceUnavailable, "geocoder_budget_spent", "address search is resting until tomorrow")
	default:
		if callerGone(r) {
			return
		}
		log.Printf("CRITICAL: failed to load %s: %v", what, err)
		writeAPIError(w, http.StatusBadGateway, "geocoder_unavailable", "could not reach address search")
	}
}
