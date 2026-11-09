package geo

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

const (
	geocoderURL = "https://geocode-maps.yandex.ru/v1/"
	suggestURL  = "https://suggest-maps.yandex.ru/v1/suggest"

	// Tashkent and its oblast, lower-left~upper-right. typed lookups stay inside it (rspn, strict_bounds):
	// unbounded, «амира темура» answers from Samarkand and Navoi before the rest of Tashkent. the terms
	// forbid dropping or reordering what yandex returns, so the bound has to be yandex's own.
	searchArea = "68.6,40.1~71.0,42.0"

	// the terms ask a mobile app to name itself this way, by its store id
	referer = "http://app.domix.ymapapp"

	maxResults = "5"
)

type yandex struct {
	geocoderKey, suggestKey string
	geocoderURL, suggestURL string
	client                  *http.Client
}

func (y *yandex) search(ctx context.Context, text string, lang Lang) ([]Place, error) {
	return y.geocode(ctx, url.Values{
		"geocode": {text},
		"results": {maxResults},
		"bbox":    {searchArea},
		"rspn":    {"1"},
	}, lang)
}

// kind "house" asks for the nearest building; empty asks for the nearest object of any kind
func (y *yandex) reverse(ctx context.Context, latitude, longitude float64, lang Lang, kind string) ([]Place, error) {
	params := url.Values{
		"geocode": {strconv.FormatFloat(longitude, 'f', -1, 64) + "," + strconv.FormatFloat(latitude, 'f', -1, 64)},
		"results": {"1"},
	}
	if kind != "" {
		params.Set("kind", kind)
	}
	return y.geocode(ctx, params, lang)
}

func (y *yandex) byURI(ctx context.Context, uri string, lang Lang) ([]Place, error) {
	return y.geocode(ctx, url.Values{"uri": {uri}, "results": {"1"}}, lang)
}

func (y *yandex) geocode(ctx context.Context, params url.Values, lang Lang) ([]Place, error) {
	params.Set("apikey", y.geocoderKey)
	params.Set("format", "json")
	params.Set("lang", lang.locale())
	body, err := y.get(ctx, y.geocoderURL, params)
	if err != nil {
		return nil, err
	}
	return parseGeocoder(body)
}

func (y *yandex) suggest(ctx context.Context, text string, lang Lang) ([]Suggestion, error) {
	body, err := y.get(ctx, y.suggestURL, url.Values{
		"apikey":        {y.suggestKey},
		"text":          {text},
		"lang":          {string(lang)},
		"results":       {maxResults},
		// **geo alone cannot answer "Central Asian University".** geo is toponyms - streets, houses,
		// districts, parks - and a university, a mall or a bazaar is an organization, so asking for geo
		// only makes a landmark unfindable however it is spelled. biz costs no extra call and the
		// geocoder resolves an ymapsbm1://org uri with the same key. it also returns bus stops named
		// after the place; the subtitle says which is which, so they are left in.
		"types":         {"geo,biz"},
		"attrs":         {"uri"},
		"bbox":          {searchArea},
		"strict_bounds": {"1"},
		"countries":     {"uz"},
	})
	if err != nil {
		return nil, err
	}
	return parseSuggest(body)
}

func (y *yandex) get(ctx context.Context, base string, params url.Values) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"?"+params.Encode(), nil)
	if err != nil {
		return nil, fmt.Errorf("%w: building the request: %v", ErrUnavailable, cleanURLError(err))
	}
	req.Header.Set("Referer", referer)

	resp, err := y.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrUnavailable, cleanURLError(err))
	}
	defer resp.Body.Close()

	// LimitReader: this body comes from a server we do not run
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("%w: reading the answer: %v", ErrUnavailable, err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%w: http %d: %.200s", ErrUnavailable, resp.StatusCode, body)
	}
	return body, nil
}

// **a *url.Error prints the whole url, and the url carries the api key**: logged as is, every timeout
// would write the key into the server log.
func cleanURLError(err error) error {
	if urlErr, ok := errors.AsType[*url.Error](err); ok {
		return urlErr.Err
	}
	return err
}

type geocoderAnswer struct {
	Response struct {
		GeoObjectCollection struct {
			FeatureMember []struct {
				GeoObject struct {
					Name             string `json:"name"`
					Description      string `json:"description"`
					MetaDataProperty struct {
						GeocoderMetaData struct {
							Text    string `json:"text"`
							Address struct {
								Components []struct {
									Kind string `json:"kind"`
									Name string `json:"name"`
								} `json:"Components"`
							} `json:"Address"`
						} `json:"GeocoderMetaData"`
					} `json:"metaDataProperty"`
					Point struct {
						Pos string `json:"pos"`
					} `json:"Point"`
				} `json:"GeoObject"`
			} `json:"featureMember"`
		} `json:"GeoObjectCollection"`
	} `json:"response"`
}

// an empty featureMember is "nothing found", not an error
func parseGeocoder(body []byte) ([]Place, error) {
	var answer geocoderAnswer
	if err := json.Unmarshal(body, &answer); err != nil {
		return nil, fmt.Errorf("%w: the geocoder answered something that is not its json: %v", ErrUnavailable, err)
	}

	places := []Place{}
	for _, member := range answer.Response.GeoObjectCollection.FeatureMember {
		object := member.GeoObject
		meta := object.MetaDataProperty.GeocoderMetaData

		// "lon lat", longitude first. a point that does not parse cannot be put on the map at all
		pos := strings.Fields(object.Point.Pos)
		if len(pos) != 2 {
			continue
		}
		longitude, lonErr := strconv.ParseFloat(pos[0], 64)
		latitude, latErr := strconv.ParseFloat(pos[1], 64)
		if lonErr != nil || latErr != nil || meta.Text == "" {
			continue
		}

		components := make(map[string]string, len(meta.Address.Components))
		for _, component := range meta.Address.Components {
			// the first of a kind is the larger one: two districts arrive outermost first
			if _, seen := components[component.Kind]; !seen {
				components[component.Kind] = component.Name
			}
		}

		places = append(places, Place{
			Name:        object.Name,
			Description: object.Description,
			Address:     meta.Text,
			Latitude:    latitude,
			Longitude:   longitude,
			City:        cityOf(components),
		})
	}
	return places, nil
}

// a city, else a district of the oblast, else the oblast: a pin in open country still names somewhere
func cityOf(components map[string]string) string {
	for _, kind := range []string{"locality", "area", "province"} {
		if name := components[kind]; name != "" {
			return name
		}
	}
	return ""
}

type suggestAnswer struct {
	// absent rather than empty when nothing matches, per the docs
	Results []struct {
		Title struct {
			Text string `json:"text"`
		} `json:"title"`
		Subtitle struct {
			Text string `json:"text"`
		} `json:"subtitle"`
		URI string `json:"uri"`
	} `json:"results"`
}

func parseSuggest(body []byte) ([]Suggestion, error) {
	var answer suggestAnswer
	if err := json.Unmarshal(body, &answer); err != nil {
		return nil, fmt.Errorf("%w: geosuggest answered something that is not its json: %v", ErrUnavailable, err)
	}

	suggestions := []Suggestion{}
	for _, result := range answer.Results {
		// without a uri the line cannot become a point, so tapping it would do nothing
		if result.URI == "" || result.Title.Text == "" {
			continue
		}
		suggestions = append(suggestions, Suggestion{
			Title:    result.Title.Text,
			Subtitle: result.Subtitle.Text,
			URI:      result.URI,
		})
	}
	return suggestions, nil
}
