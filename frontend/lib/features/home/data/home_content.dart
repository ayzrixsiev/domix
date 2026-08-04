import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

/// A shop as the home screen shows it, and the one type its widgets know about.
///
/// Deliberately not [Shop] itself. The home sections need four facts - a name, where it is, how
/// good it is and what it costs - and giving the widgets the full backend model would let a card
/// quietly start depending on an id or a pair of coordinates. It also keeps the showcase rows in
/// `home_showcase_content.dart` from being passable to anything that expects a persisted shop,
/// which is a property the placeholder file has had since it was written and worth keeping.
///
/// Real shops arrive through [HomeShopPreview.fromShop]; showcase rows are written out as consts.
/// Once both are here, nothing downstream can tell them apart - which is exactly the point: the
/// widgets have no fallback logic in them at all.
class HomeShopPreview {
  const HomeShopPreview({
    required this.name,
    required this.address,
    required this.rating,
    this.priceTier,
    this.priceDifferencePercent,
    this.basketPrice,
    this.isVip = false,
  });

  /// Projects a real backend shop onto what the home screen needs.
  HomeShopPreview.fromShop(Shop shop)
      : name = shop.name,
        address = shop.address,
        rating = shop.rating,
        priceTier = shop.priceTier,
        priceDifferencePercent = shop.priceDifferencePercent,
        basketPrice = shop.basketPrice,
        isVip = shop.isVip;

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

  /// True when the backend answered but had nothing to show - no shop is VIP and none has priced
  /// enough of its catalogue to be ranked. This is the state a fresh database is in, and it is what
  /// the controller tests to decide whether to fall back to the showcase rows.
  ///
  bool get hasNoShops => vipShops.isEmpty && bestOffers.isEmpty;

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
