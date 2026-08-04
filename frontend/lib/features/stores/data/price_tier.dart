/// How a shop's shared basket compares to the market it competes in.
///
/// The three buckets the backend sorts shops into (`internal/pricing`), and the *only* form the
/// Basket Price Index reaches this app in. The raw number - 96, 104 - is never sent, so no screen
/// can accidentally print it, and no threshold lives in a build that would take an App Store
/// release to change. See [Shop.priceTier].
enum PriceTier {
  /// Meaningfully below the market average for this shop's category.
  cheaper('cheaper'),

  /// Close enough to the market average that the difference isn't worth a claim.
  average('average'),

  /// Meaningfully above it.
  dearer('dearer');

  const PriceTier(this.code);

  /// The wire value. A locale-neutral code for the same reason `products.category` is one: the
  /// Russian and Uzbek wording lives in `AppLocalizations`, so adding a language never touches
  /// either side's data.
  final String code;

  /// Null for anything unrecognised, **including null itself** - which is the common case, not an
  /// error: the backend sends `price_tier: null` for a shop with no index yet or one in a market
  /// too small to compare within, and the app renders no badge for either.
  ///
  /// Unrecognised codes fall through to the same null rather than throwing, so a backend that grows
  /// a fourth tier leaves an older app showing no badge instead of crashing on a shop card.
  static PriceTier? tryFromCode(String? code) {
    for (final tier in PriceTier.values) {
      if (tier.code == code) return tier;
    }
    return null;
  }
}
