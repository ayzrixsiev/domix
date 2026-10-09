package endpoints

import (
	"github.com/jackc/pgx/v5/pgtype"

	"domix/backend/db"
	"domix/backend/internal/imagestore"
	"domix/backend/internal/pricing"
)

// one unified JSON structure for the shop to send to the flutter for all sqlc queries
type ShopResponse struct {
	ID                     int64   `json:"id"`
	Name                   string  `json:"name"`
	ContactPhone           string  `json:"contact_phone"`
	Address                string  `json:"address"`
	Category               string  `json:"category"`
	IsVIP                  bool    `json:"is_vip"`
	BasketPrice            *int64  `json:"basket_price"`             // int: sum of the shop's basket
	PriceTier              *string `json:"price_tier"`               // string: cheaper, avrg, dearer
	PriceDifferencePercent *int64  `json:"price_difference_percent"` // int: e.g 4 percent (cheaper or dearer)
	Latitude               float64 `json:"latitude"`
	Longitude              float64 `json:"longitude"`
	ProductCount           int64   `json:"product_count,omitempty"`

	// the storefront, on the reads that carry one (VIP cards). two ready-made urls like a product's:
	// the app is never told how a thumbnail's path is spelled - see imagestore.ThumbPath.
	ImageURL      string `json:"image_url,omitempty"`
	ImageThumbURL string `json:"image_thumb_url,omitempty"`
}

func ptr(v int64) *int64 {
	value := v
	return &value
}

// the photo, where a read carries one. a stored path is relative and the host is this server's to
// decide, so the urls are built here and never in the app.
func (r *ShopResponse) setPhoto(urls imagestore.URLs, rel pgtype.Text) {
	if !rel.Valid || rel.String == "" {
		return
	}
	r.ImageURL = urls.Master(rel.String)
	r.ImageThumbURL = urls.Thumb(rel.String)
}

func (r *ShopResponse) setPricing(index, basketPrice pgtype.Int8) {
	if !basketPrice.Valid || !index.Valid {
		return
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

// mappers to convert row sql queries results into one unified json structure for flutter

func shopFromList(r db.ListShopsRow) ShopResponse {
	out := ShopResponse{
		ID:           r.ID,
		Name:         r.Name,
		ContactPhone: r.ContactPhone,
		Address:      r.Address,
		Category:     r.Category,
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
		Address:      r.Address,
		Category:     r.Category,
		IsVIP:        r.IsVip,
		Latitude:     r.Latitude,
		Longitude:    r.Longitude,
		ProductCount: r.ProductCount,
	}
	out.setPricing(r.PriceIndex, r.BasketPrice)
	return out
}

// the one mapper that takes the url builder: a VIP card is the only read that draws a storefront.
func shopFromVip(urls imagestore.URLs, r db.ListVipShopsRow) ShopResponse {
	out := ShopResponse{
		ID:           r.ID,
		Name:         r.Name,
		ContactPhone: r.ContactPhone,
		Address:      r.Address,
		Category:     r.Category,
		IsVIP:        r.IsVip,
		Latitude:     r.Latitude,
		Longitude:    r.Longitude,
		ProductCount: r.ProductCount,
	}
	out.setPhoto(urls, r.ImagePath)
	out.setPricing(r.PriceIndex, r.BasketPrice)
	return out
}

func shopFromRanked(r db.ListBestOffersInCategoryRow) ShopResponse {
	out := ShopResponse{
		ID:           r.ID,
		Name:         r.Name,
		ContactPhone: r.ContactPhone,
		Address:      r.Address,
		Category:     r.Category,
		IsVIP:        r.IsVip,
		Latitude:     r.Latitude,
		Longitude:    r.Longitude,
	}
	out.setRankedPricing(r.PriceIndex, r.BasketPrice)
	return out
}

func shopFromCreate(r db.CreateShopRow, productCount int64) ShopResponse {
	return ShopResponse{
		ID:           r.ID,
		Name:         r.Name,
		ContactPhone: r.ContactPhone,
		Address:      r.Address,
		Category:     r.Category,
		IsVIP:        r.IsVip,
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
		Address:      r.Address,
		Category:     r.Category,
		IsVIP:        r.IsVip,
		Latitude:     r.Latitude,
		Longitude:    r.Longitude,
	}
	out.setPricing(r.PriceIndex, r.BasketPrice)
	return out
}
