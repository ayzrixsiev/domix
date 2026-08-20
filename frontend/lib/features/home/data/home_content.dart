import 'dart:math' as math;

import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

/// A shop as the home screen shows it, and the one type its widgets know about.
///
/// Deliberately not [Shop] itself: the home sections need four facts - a name, where it is, how good
/// it is and what it costs - and handing the widgets the full backend model would let a card quietly
/// start depending on a coordinate pair or a product count.
///
/// **Every preview is a real shop, and there is no other way to make one.** There used to be a second
/// constructor that took the four facts on their own, so that `home_showcase_content.dart` could
/// write out invented rows as `const` and have them arrive at the widgets indistinguishable from real
/// ones. That file is gone (the home screen shows the database or an empty slot, never a plausible
/// story), and with it the only reason [shop] was ever nullable. So it is required now, which is what
/// deleted the "this card is inert" branch from three widgets: a card that is drawn from a shop can
/// always be opened.
class HomeShopPreview {
  /// Projects a real backend shop onto what the home screen needs, keeping the row itself in [shop].
  HomeShopPreview.fromShop(Shop source)
      : shop = source,
        name = source.name,
        address = source.address,
        rating = source.rating,
        priceTier = source.priceTier,
        priceDifferencePercent = source.priceDifferencePercent,
        basketPrice = source.basketPrice,
        isVip = source.isVip;

  final String name;
  final String address;
  final double rating;

  /// Cheaper / average / dearer than this shop's own market, or null when there is no honest
  /// comparison to make. See [Shop.priceTier] - the rows render no badge rather than a guess.
  final PriceTier? priceTier;

  /// The X in "X% cheaper than market". Null exactly when [priceTier] is.
  final int? priceDifferencePercent;

  /// What the shared basket costs here, in so'm. Can be set while [priceTier] is null: a price is
  /// true with no competitors, a comparison is not.
  final int? basketPrice;

  final bool isVip;

  /// The backend row this preview came from - what makes a card a way *into* a shop. A shop card
  /// needs the phone, the category and the id its catalogue hangs off, all of which `GET /api/home`
  /// already sends and this type used to throw away.
  final Shop shop;

  /// Whether there is a rating worth drawing. Mirrors [Shop.hasRating] deliberately: the home feed
  /// carries its own lighter model, and a star that appears on the map but not on the home screen
  /// would look like one of the two was broken. Both are false today - nothing writes
  /// `shops.rating`, so every shop reads 0.0, and `⭐ 0.0` claims a bad rating where the truth is
  /// no rating. When a reviews table exists, these two getters flip together.
  bool get hasRating => rating > 0;
}

/// One tab of "Лучшие предложения": a shop category and its cheapest shops.
///
/// The section is grouped rather than one flat ranking because a Basket Price Index only compares
/// shops of the *same* category - a Сантехника basket is a different list of goods from a
/// Универсальный one, so "6% cheaper than market" means a different market on each row. A mixed
/// list would still be ordered correctly, but the badges beside each other would invite a
/// comparison that isn't there.
class CategoryOffers {
  const CategoryOffers({required this.category, required this.shops});

  final ShopCategory category;
  final List<HomeShopPreview> shops;
}

/// Everything `GET /api/home` returns, in one object because it arrives in one response.
class HomeContent {
  const HomeContent({required this.vipShops, required this.bestOffers});

  final List<HomeShopPreview> vipShops;

  /// One entry per shop category that actually has ranked shops, in the backend's canonical order.
  /// The tab strip is built from this, so a category with nothing in it is simply not a tab.
  final List<CategoryOffers> bestOffers;

  static HomeContent fromJson(Map<String, dynamic> json) {
    return HomeContent(
      vipShops: _shops(json['vip_shops']),
      bestOffers: _offerGroups(json['best_offers']),
    );
  }

  static List<CategoryOffers> _offerGroups(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw) ?_offerGroup(item as Map<String, dynamic>),
    ];
  }

  /// Null for a shop category this app build doesn't know, so a backend that grew a fifth category
  /// leaves an older app showing four tabs rather than crashing on one.
  ///
  /// [ShopCategory.fromCode] cannot be used here: it defaults an unknown code to `universal`, which
  /// would merge a stranger's shops into the Универсальный tab and quietly misfile them.
  static CategoryOffers? _offerGroup(Map<String, dynamic> json) {
    final category = ShopCategory.tryFromCode(json['category'] as String?);
    if (category == null) return null;

    return CategoryOffers(category: category, shops: _shops(json['shops']));
  }

  static List<HomeShopPreview> _shops(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        HomeShopPreview.fromShop(Shop.fromJson(item as Map<String, dynamic>)),
    ];
  }
}

// ─────────────────────────────── slots ───────────────────────────────
//
// Both home sections are a **fixed number of positions**, drawn whether or not anything is in them.
// The two functions below decide which position a shop lands in, and they are here rather than in the
// widgets for one reason: where a paying shop appears is a product rule, not a layout detail, and a
// rule wants a test that does not need a screen to run.
//
// A `null` entry is an empty slot. It is not a loading state and not padding - see the widgets that
// draw it.

/// The rating an empty slot shows, as a literal.
///
/// **The one value on an empty slot that is not a field name**, and it is here rather than in either
/// widget because both draw it and two copies of one number can disagree - the same reason
/// `Shop.hasRating` and `HomeShopPreview.hasRating` are documented as mirrors.
///
/// A literal because there is nothing to derive it from: no shop, no reviews table, nothing that
/// could make it true or false. It describes the field - "a rating goes here, out of five" - rather
/// than claiming anything about a business, which is why it is the single exception to the rule that
/// an empty slot invents nothing.
///
/// A `String` and not a number: it is drawn, never compared, and `5` formatted through a locale would
/// be one more thing that could turn into "5.0" on somebody's phone.
const String kSlotRating = '5';

/// The VIP carousel's ring of slots, **filled from the centre outwards**.
///
/// The carousel opens parked on the middle position and loops endlessly in both directions, so the
/// order here is a ring rather than a row: index [slotCount] ~/ 2 is what the customer is looking at
/// when the section scrolls into view, and its neighbours are one swipe away in each direction.
///
/// Shops go in centre-first, then alternating right and left - so with one placement sold, that shop
/// is the card on screen rather than something two swipes away behind empty ones. With five sold the
/// ring is full and the arrangement stops mattering.
///
///     sold │ 0    1    2*   3    4        (* = where the carousel opens)
///     ─────┼─────────────────────────
///       1  │ ·    ·    A    ·    ·
///       2  │ ·    ·    A    B    ·
///       3  │ ·    C    A    B    ·
///       4  │ ·    C    A    B    D
///       5  │ E    C    A    B    D
///
/// **The list is never shorter than [shops].** If the backend ever sends more placements than this
/// build knows about, the ring grows to hold them - dropping one would be hiding something somebody
/// paid for, which is the failure this whole section is built around avoiding.
List<HomeShopPreview?> vipSlotRing(
  List<HomeShopPreview> shops, {
  required int slotCount,
}) {
  final size = math.max(slotCount, shops.length);
  final centre = size ~/ 2;
  final ring = List<HomeShopPreview?>.filled(size, null);

  for (var n = 0; n < shops.length; n++) {
    // 0, +1, −1, +2, −2, … - a run of `size` consecutive integers once n reaches the end, so no two
    // shops can land on the same position.
    final offset = n.isEven ? -(n ~/ 2) : (n + 1) ~/ 2;
    // `%` is Euclidean in Dart (−1 % 5 is 4), which is what lets an offset walk off either end of an
    // even-sized ring and come back round rather than throwing.
    ring[(centre + offset) % size] = shops[n];
  }
  return ring;
}

/// The slots of one "Лучшие предложения" tab: the ranking as the server ordered it, padded with
/// empty positions up to [slotCount].
///
/// **In order, not centred**, and that is the whole difference from the ring above. This section is a
/// ranking - the top of the list is the cheapest shop and the reader is meant to start there - where
/// the carousel is a shelf of five bought placements with a most-valuable spot in the middle. The
/// empty rows underneath say how many places in this category's ranking are still open, which is the
/// one message that reaches an owner who has not finished pricing.
///
/// Never truncates, for the same reason the ring does not: what the server sent, the app shows.
List<HomeShopPreview?> rankedSlots(
  List<HomeShopPreview> shops, {
  required int slotCount,
}) {
  final size = math.max(slotCount, shops.length);
  return [
    for (var i = 0; i < size; i++) i < shops.length ? shops[i] : null,
  ];
}
