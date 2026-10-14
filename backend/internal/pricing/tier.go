// package pricing turns the Basket Price Index into something a customer can read.
//
// **the raw index never reaches the app** - the card says "на 4% дешевле рынка", not "96". the thresholds
// live here and not in Flutter because moving them on the server is a deploy, where moving them in the
// app is a Play release and months of phones disagreeing about what "average" means.
//
// ROADMAP: a band derived from the real spread of indices in a category is a change to this file alone.
package pricing

// which of the three buckets a shop's basket falls in. the string values are the wire contract.
type Tier string

const (
	TierCheaper Tier = "cheaper" // meaningfully below the market
	TierAverage Tier = "average" // indistinguishable from the market
	TierDearer  Tier = "dearer"  // meaningfully above it
)

const (
	// the band: below CheaperBelow is cheap, above DearerAbove is dear, endpoints included in
	// "average". **±2 is a placeholder and should be expected to be wrong** - if real prices vary by
	// 3% this band is noise amplification and shops will flicker between green and red.
	CheaperBelow = 98
	DearerAbove  = 102
)

func TierFor(index int64) Tier {
	switch {
	case index < CheaperBelow:
		return TierCheaper
	case index > DearerAbove:
		return TierDearer
	default:
		return TierAverage
	}
}

// the X in "X% cheaper than market" - unsigned, since the Tier already carries the direction. the
// index is already rounded by the view, and rounding twice is how a shop displays 5% while its own
// index says 104.
func DifferencePercent(index int64) int64 {
	if index < 100 {
		return 100 - index
	}
	return index - 100
}
