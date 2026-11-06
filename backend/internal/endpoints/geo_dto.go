package endpoints

import "domix/backend/internal/geo"

// one result row of an address search, and a tapped suggestion once it is a point. title is the part a
// person recognises, subtitle where it is, address the whole line that is stored on a shop.
type PlaceResponse struct {
	Title     string  `json:"title"`
	Subtitle  string  `json:"subtitle"`
	Address   string  `json:"address"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

// a line under the field as it is typed. no coordinates: the app hands uri back to /api/geo/place
type SuggestionResponse struct {
	Title    string `json:"title"`
	Subtitle string `json:"subtitle"`
	URI      string `json:"uri"`
}

// a pin's address. city is null where yandex names none, and the header keeps the city it was showing
type AddressResponse struct {
	Address string  `json:"address"`
	City    *string `json:"city"`
}

func placeFrom(p geo.Place) PlaceResponse {
	return PlaceResponse{
		Title:     p.Name,
		Subtitle:  p.Description,
		Address:   p.Address,
		Latitude:  p.Latitude,
		Longitude: p.Longitude,
	}
}

func suggestionFrom(s geo.Suggestion) SuggestionResponse {
	return SuggestionResponse{Title: s.Title, Subtitle: s.Subtitle, URI: s.URI}
}

func addressFrom(p geo.Place) AddressResponse {
	out := AddressResponse{Address: p.Address}
	if p.City != "" {
		out.City = &p.City
	}
	return out
}
