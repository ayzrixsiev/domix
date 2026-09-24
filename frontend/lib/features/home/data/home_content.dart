import 'dart:math' as math;

import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

/// A shop as the home screen shows it, and the one type its widgets know about - not [Shop] itself,
/// or a card could start depending on a coordinate pair. **Every preview is a real shop**: [shop] is
/// required, so a card that is drawn can always be opened.
class HomeShopPreview {
  /// Projects a real backend shop onto what the home screen needs, keeping the row itself in [shop].
  HomeShopPreview.fromShop(Shop source)
      : shop = source,
        name = source.name,
        address = source.address,
        priceTier = source.priceTier,
        priceDifferencePercent = source.priceDifferencePercent,
        basketPrice = source.basketPrice,
        isVip = source.isVip;

  final String name;
  final String address;

  /// null when there is no honest comparison to make - the rows render no badge rather than a guess
  final PriceTier? priceTier;

  /// The X in "X% cheaper than market". Null exactly when [priceTier] is.
  final int? priceDifferencePercent;

  /// can be set while [priceTier] is null: a price is true with no competitors, a comparison is not
  final int? basketPrice;

  final bool isVip;

  /// the backend row this preview came from - the phone, category and id a shop card needs, all of
  /// which `GET /api/home` already sends
  final Shop shop;
}

/// One tab of "Лучшие предложения". Grouped rather than one flat ranking because the index only
/// compares shops of the *same* category - a mixed list would invite a comparison that is not there.
class CategoryOffers {
  const CategoryOffers({required this.category, required this.shops});

  final ShopCategory category;
  final List<HomeShopPreview> shops;
}

/// Everything `GET /api/home` returns, in one object because it arrives in one response.
class HomeContent {
  const HomeContent({required this.vipShops, required this.bestOffers});

  final List<HomeShopPreview> vipShops;

  /// **The contents of the tabs, not the tabs themselves** - the strip is all four [ShopCategory]
  /// values whatever arrives, so a category the server said nothing about is still a segment.
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

  /// Null for a shop category this build does not know, so a backend that grew a fifth one leaves an
  /// older app showing four tabs rather than crashing. [ShopCategory.fromCode] cannot be used here:
  /// it defaults an unknown code to `universal` and would quietly misfile a stranger's shops.
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

// ── slots: both home sections are a fixed number of positions, drawn whether or not anything is in
// them, and a `null` entry is an empty slot rather than a loading state. the two functions below
// decide which position a shop lands in - a product rule, so it lives here where a test can reach
// it without a screen. ──

/// The rating an empty slot shows, and the one value on it that is not a field name. A literal
/// because there is nothing to derive it from: it describes the field, not a business.
const String kSlotRating = '5';

// ── slots: both home sections are a fixed number of positions, drawn whether or not anything is in
// them, and a `null` entry is an empty slot rather than a loading state. the two functions below
// decide which position a shop lands in - a product rule, so it lives here where a test can reach
// it without a screen. ──

/// The rating an empty slot shows, and the one value on it that is not a field name. A literal
/// because there is nothing to derive it from: it describes the field, not a business.
List<HomeShopPreview?> vipSlotRing(
  List<HomeShopPreview> shops, {
  required int slotCount,
}) {
  final size = math.max(slotCount, shops.length);
  final centre = size ~/ 2;
  final ring = List<HomeShopPreview?>.filled(size, null);

  for (var n = 0; n < shops.length; n++) {
    // 0, +1, −1, +2, −2, … - consecutive integers once n reaches the end, so no two shops collide
    final offset = n.isEven ? -(n ~/ 2) : (n + 1) ~/ 2;
    // `%` is Euclidean in Dart (−1 % 5 is 4), which lets an offset walk off either end and come round
    ring[(centre + offset) % size] = shops[n];
  }
  return ring;
}

/// The slots of one "Лучшие предложения" tab, padded with empty positions up to [slotCount].
/// **In order, not centred** - this is a ranking, where the carousel is a shelf. Never truncates.
List<HomeShopPreview?> rankedSlots(
  List<HomeShopPreview> shops, {
  required int slotCount,
}) {
  final size = math.max(slotCount, shops.length);
  return [
    for (var i = 0; i < size; i++) i < shops.length ? shops[i] : null,
  ];
}
