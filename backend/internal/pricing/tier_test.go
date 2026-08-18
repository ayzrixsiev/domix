package pricing

import "testing"

// the boundaries, because "98-102 is average" leaves two off-by-one questions and the answer to
// both has to be a decision rather than an accident of which comparison operator got typed.
func TestTierBoundaries(t *testing.T) {
	cases := []struct {
		index int64
		want  Tier
	}{
		{0, TierCheaper},
		{80, TierCheaper},
		{97, TierCheaper},
		{98, TierAverage}, // inclusive: the band is [98, 102]
		{100, TierAverage},
		{102, TierAverage}, // inclusive at the top too
		{103, TierDearer},
		{200, TierDearer},
	}

	for _, c := range cases {
		if got := TierFor(c.index); got != c.want {
			t.Errorf("index %d: want %q, got %q", c.index, c.want, got)
		}
	}
}

func TestDifferencePercentIsUnsigned(t *testing.T) {
	// the sign lives in the Tier, so "4% cheaper" and "4% more expensive" share this number
	for _, c := range []struct{ index, want int64 }{
		{96, 4},
		{104, 4},
		{100, 0},
		{181, 81},
	} {
		if got := DifferencePercent(c.index); got != c.want {
			t.Errorf("index %d: want %d, got %d", c.index, c.want, got)
		}
	}
}
