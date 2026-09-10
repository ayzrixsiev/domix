/// How a shop's shared basket compares to the market it competes in: the three buckets the backend
/// sorts shops into, and the *only* form the Basket Price Index reaches this app in. The raw number
/// is never sent, so no screen can print it and no threshold needs a store release to change.
enum PriceTier {
  /// Meaningfully below the market average for this shop's category.
  cheaper('cheaper'),

  /// Close enough to the market average that the difference isn't worth a claim.
  average('average'),

  /// Meaningfully above it.
  dearer('dearer');

  const PriceTier(this.code);

  /// The wire value. Locale-neutral for the same reason `products.category` is: the ru/uz wording
  /// lives in `AppLocalizations`, so adding a language never touches either side's data.
  final String code;

  /// Null for anything unrecognised, **including null itself** - the common case, not an error: the
  /// backend sends null for a shop with no index or a market too small to compare within, and a
  /// backend that grows a fourth tier leaves an older app showing no badge rather than crashing.
  static PriceTier? tryFromCode(String? code) {
    for (final tier in PriceTier.values) {
      if (tier.code == code) return tier;
    }
    return null;
  }
}
