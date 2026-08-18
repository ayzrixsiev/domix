package endpoints

import (
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/pricing"
)

// one shape for a shop on the wire, whichever query produced it.
//
// two reasons it isn't just the sqlc row struct. first, there are now seven of those - ListShops,
// ListShopsByOwner, ListVipShops, ListBestOffers, ListShopsByProductCategory, CreateShop,
// UpdateShop - and they are near-identical, because sqlc emits one struct per query by design.
// second, they are full of pgtype wrappers (pgtype.Text, pgtype.Numeric, pgtype.Int8) which
// serialize as `{"String":"","Valid":false}` rather than as the null the app expects.
type ShopResponse struct {
	ID           int64  `json:"id"`
	Name         string `json:"name"`
	ContactPhone string `json:"contact_phone"`
	ImageURL     string `json:"image_url,omitempty"`
	Address      string `json:"address"`
	Category     string `json:"category"`

	Rating float64 `json:"rating"`

	// the paid placement tier behind the home screen's VIP carousel. sent on every shop, not just
	// the VIP ones, so the app can badge a shop wherever it appears rather than only in the list
	// that filtered on it.
	//
	// a boolean on the wire even though the database stores a `vip_until` date (migration 000009).
	// the app's only question is "badge this or not", and sending the date would invite a client to
	// start comparing it against the *device* clock - which is user-settable, so a shop's placement
	// would expire early or late depending on whose phone is looking at it.
	IsVIP bool `json:"is_vip"`

	// What the shared basket costs at this shop, in сум - step 1 of the Basket Price Index, and the
	// only *absolute* price the app ever shows for a shop.
	//
	// a *pointer*, for exactly the reason ProductResponse.Price is one: a shop that has priced less
	// than 30% of its catalogue has no basket *yet*, which is a different fact from "this shop is
	// free". it serializes as `basket_price: null` and the app renders nothing.
	BasketPrice *int64 `json:"basket_price"`

	// The Basket Price Index, already turned into something readable: `"cheaper"`, `"average"` or
	// `"dearer"`, with the distance from the market as a whole percent.
	//
	// **The raw index is deliberately not on this struct.** It is used for ranking, which happens in
	// SQL, and for choosing the tier, which happens in internal/pricing - so the app has no use for
	// it, and "96" is a comparison a reader has to be taught to perform anyway. Keeping the number
	// server-side is also what makes the thresholds changeable: they are a guess until there is real
	// data, and moving a guess that lives in Flutter means an App Store release.
	//
	// Null when the shop has no index at all - it has priced less than 30% of its catalogue - which
	// is the same circumstance that leaves BasketPrice null. The app shows no badge.
	PriceTier *string `json:"price_tier"`

	// The X in "X% cheaper than market" - unsigned, since PriceTier already carries the direction.
	// Null exactly when PriceTier is.
	PriceDifferencePercent *int64 `json:"price_difference_percent"`

	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`

	// omitempty because only the two queries that compute it send it: /api/shops/mine, and the
	// category drill-down (where it counts the shop's products *in that category*, not all of them)
	ProductCount int64 `json:"product_count,omitempty"`
}

// pgtype.Numeric -> float64. Float64Value returns an error only for a value that isn't
// representable - NaN, or a numeric wider than a float64 - and rating is NUMERIC(2,1), so it cannot
// happen here. dropping it yields 0.0, which is also what an unrated shop holds.
func ratingOf(n pgtype.Numeric) float64 {
	f, _ := n.Float64Value()
	return f.Float64
}

// the queries whose numbers come from an INNER JOIN get a plain int64: the join itself guarantees
// the shop had a row in shop_basket_index, so there is nothing nullable about it. the pointer still
// has to be taken from a local rather than from the parameter, or every element of a loop would
// share one address.
func ptr(v int64) *int64 {
	value := v
	return &value
}

// fills in the three price fields together, because they are one fact and setting them separately
// is how a response ends up carrying a badge with no basket behind it.
//
// takes the raw index and market size and hands back what goes on the wire - which is where the
// index stops. everything below this line in the response knows only "cheaper by 4%".
func (r *ShopResponse) setPricing(index, basketPrice pgtype.Int8) {
	if !basketPrice.Valid || !index.Valid {
		return // the shop hasn't priced enough of its catalogue to be ranked at all
	}

	r.BasketPrice = ptr(basketPrice.Int64)
	tier := string(pricing.TierFor(index.Int64))
	r.PriceTier = &tier
	r.PriceDifferencePercent = ptr(pricing.DifferencePercent(index.Int64))
}

// the INNER JOIN variant: the join guarantees a row, so these arrive as plain int64s.
func (r *ShopResponse) setRankedPricing(index, basketPrice int64) {
	r.setPricing(
		pgtype.Int8{Int64: index, Valid: true},
		pgtype.Int8{Int64: basketPrice, Valid: true},
	)
}

// mappers, one per sqlc row shape. they are written out longhand rather than unified behind
// generics or reflection: go generics cannot read a field off a type parameter, and reflection would
// trade a compile-time guarantee for a runtime one in the layer whose whole job is to be the stable
// contract with the app. a mistyped field here is a build failure.

func shopFromList(r db.ListShopsRow) ShopResponse {
	out := ShopResponse{
		ID:           r.ID,
		Name:         r.Name,
		ContactPhone: r.ContactPhone,
		ImageURL:     r.ImageUrl.String,
		Address:      r.Address,
		Category:     r.Category,
		Rating:       ratingOf(r.Rating),
		IsVIP:        r.IsVip,
		Latitude:     r.Latitude,
		Longitude:    r.Longitude,
	}
	out.setPricing(r.PriceIndex, r.BasketPrice)
	return out
}

func shopFromOwned(r db.ListShopsByOwnerRow) ShopResponse {
	out := ShopResponse{
		ID:           r.ID,
		Name:         r.Name,
		ContactPhone: r.ContactPhone,
		ImageURL:     r.ImageUrl.String,
		Address:      r.Address,
		Category:     r.Category,
		Rating:       ratingOf(r.Rating),
		IsVIP:        r.IsVip,
		Latitude:     r.Latitude,
		Longitude:    r.Longitude,
		ProductCount: r.ProductCount,
	}
	out.setPricing(r.PriceIndex, r.BasketPrice)
	return out
}

// ListVipShopsRow and ListBestOffersRow are field-for-field identical - same names, same types, same
// order - because the two queries differ only in their WHERE and ORDER BY. go lets one be converted
// to the other outright when the underlying types match like that, so the two sections share a
// mapper instead of keeping two copies that could drift apart.
func shopFromRanked(r db.ListBestOffersInCategoryRow) ShopResponse {
	out := ShopResponse{
		ID:           r.ID,
		Name:         r.Name,
		ContactPhone: r.ContactPhone,
		ImageURL:     r.ImageUrl.String,
		Address:      r.Address,
		Category:     r.Category,
		Rating:       ratingOf(r.Rating),
		IsVIP:        r.IsVip,
		Latitude:     r.Latitude,
		Longitude:    r.Longitude,
	}
	out.setRankedPricing(r.PriceIndex, r.BasketPrice)
	return out
}

// productCount is passed in rather than read off the row: CreateShop runs before the category
// template has been seeded, so the count it could report is 0, while the number the app needs is
// the size of the template about to land in the same transaction.
func shopFromCreate(r db.CreateShopRow, productCount int64) ShopResponse {
	return ShopResponse{
		ID:           r.ID,
		Name:         r.Name,
		ContactPhone: r.ContactPhone,
		ImageURL:     r.ImageUrl.String,
		Address:      r.Address,
		Category:     r.Category,
		Rating:       ratingOf(r.Rating),
		IsVIP:        r.IsVip,
		// PriceIndex and BasketPrice are left nil, which is the truth: nothing in a shop created a
		// millisecond ago has a price yet. the query does not even select them - see the note on
		// CreateShop in db/queries/shops.sql.
		Latitude:     r.Latitude,
		Longitude:    r.Longitude,
		ProductCount: productCount,
	}
}

func shopFromUpdate(r db.UpdateShopRow) ShopResponse {
	out := ShopResponse{
		ID:           r.ID,
		Name:         r.Name,
		ContactPhone: r.ContactPhone,
		ImageURL:     r.ImageUrl.String,
		Address:      r.Address,
		Category:     r.Category,
		Rating:       ratingOf(r.Rating),
		IsVIP:        r.IsVip,
		Latitude:     r.Latitude,
		Longitude:    r.Longitude,
	}
	out.setPricing(r.PriceIndex, r.BasketPrice)
	return out
}
