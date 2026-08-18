// package pricing turns the Basket Price Index into something a customer can read.
//
// **The raw index never reaches the app.** A shop's card says "на 4% дешевле рынка" with a green
// dot; it does not say "96". Two reasons, and the second is the one that made this a package:
//
//   - "96" is a comparison the reader has to be taught to perform, on a scale nobody explained. A
//     colour and a sentence are read without instruction.
//   - Every rule below is a *guess* until there is real data. Nobody yet knows whether construction
//     baskets in Tashkent spread by 2% or by 20%, so the boundary between "cheap" and "average" is
//     going to move. Deciding it on the server means moving it is a deploy; deciding it in Flutter
//     would mean an App Store release, and a version of the app that disagrees with the current one
//     living on people's phones for months.
//
// So the API sends a Tier and a percentage, and the app renders them. The app has no thresholds in
// it at all, and cannot be wrong about them.
//
// **Where "dynamic" goes.** The two constants below are the whole policy. Making the band adapt to
// the real distribution - the obvious version being a band derived from the standard deviation of
// the indices in a category, so that "market average" always means "indistinguishable from the
// middle of this market" rather than a fixed ±2 - is a change to this file and nothing else. That
// is the point of it existing.
//
// There is deliberately **no minimum market size**. An earlier version withheld the badge until a
// category had at least three shops, on the grounds that with two shops one is always above the
// average and one always below. The launch cohort is 50-70 shops, so no category will be thin
// enough for that to bite, and a guard for a situation that cannot arise is a branch nobody will
// ever see run.
package pricing

// Tier is which of the three buckets a shop's basket falls in. The string values are the wire
// contract: the app switches on them, so they are locale-neutral codes for the same reason
// products.category is.
type Tier string

const (
	TierCheaper Tier = "cheaper" // meaningfully below the market
	TierAverage Tier = "average" // indistinguishable from the market
	TierDearer  Tier = "dearer"  // meaningfully above it
)

const (
	// the band. an index strictly below CheaperBelow is cheap, strictly above DearerAbove is dear,
	// and everything between is "market average" - including both endpoints.
	//
	// ±2 is a placeholder and should be expected to be wrong. it is narrow, so with any real spread
	// almost every shop will land in the coloured buckets and almost none will read as average.
	// whether that is right depends on data nobody has yet: if construction prices in one city
	// genuinely vary by 15%, a 2% band is correct and most shops really are meaningfully cheaper or
	// dearer than the middle; if they vary by 3%, this band is noise amplification and every shop
	// flickers between green and red as competitors adjust.
	CheaperBelow = 98
	DearerAbove  = 102
)

// TierFor buckets an index.
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

// DifferencePercent is the X in "X% cheaper than market": how far the index sits from 100, without
// a sign, since the direction is already carried by the Tier.
//
// The index is already rounded to a whole number by the view, so there is no second rounding here -
// doing it twice is how a shop ends up displaying 5% while its own index says 104.
func DifferencePercent(index int64) int64 {
	if index < 100 {
		return 100 - index
	}
	return index - 100
}
