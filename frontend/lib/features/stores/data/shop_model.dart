import 'package:frontend/core/constants/api_config.dart';
import 'price_tier.dart';
import 'shop_category.dart';

// a single shop as returned by the go backend's /api/shops endpoint
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.contactPhone,
    required this.address,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.rating,
    this.priceTier,
    this.priceDifferencePercent,
    this.basketPrice,
    this.isVip = false,
    this.imageUrl,
    this.productCount = 0,
  });

  final int id;
  final String name;
  final String contactPhone;
  final String address;

  // picked once when the shop was created and fixed from then on - it decided which product
  // template seeded the catalogue, so changing it later would leave the shop stocked with the
  // wrong list. see ShopCategory.
  final ShopCategory category;

  final double latitude;
  final double longitude;
  final double rating;

  /// How this shop's basket compares to its market, already decided by the backend: cheaper,
  /// average or dearer.
  ///
  /// **The raw Basket Price Index is deliberately not here, and never crosses the network.** The
  /// number is used for ranking (in SQL) and for picking this tier (in Go), and neither of those
  /// happens in the app - so shipping "96" would only invite a screen to render it, which is a
  /// comparison the reader has to be taught to perform. It also keeps every threshold on the
  /// server: they are guesses until there is real data, and a guess baked into a Flutter build
  /// takes an App Store release to change.
  ///
  /// **Null until the owner has priced every product in the shop's template.** One unpriced row is
  /// enough (the `shop_basket_index` view, tightened in migration 000013), so expect this to be null
  /// for most shops early on - the shop is still a pin on the map, it just publishes no comparison.
  ///
  /// Null in exactly the same circumstances as [basketPrice], since the two come from the same view
  /// row and the view has no partial state. Code that branches on one having checked the other is
  /// handling something the backend cannot send.
  final PriceTier? priceTier;

  /// The X in "X% cheaper than market" - unsigned, since [priceTier] carries the direction. Null
  /// exactly when [priceTier] is.
  final int? priceDifferencePercent;

  /// What the shared basket costs here, in so'm - the index's own first step, before the division.
  ///
  /// Null under the same condition as [priceTier]: every template product priced, or nothing.
  final int? basketPrice;

  /// Whether this shop currently holds a paid placement - the home screen's VIP carousel.
  ///
  /// Computed by the backend from `shops.vip_until > now()` and sent as a plain boolean, so the app
  /// never compares a placement against the *device* clock, which the user can change.
  final bool isVip;

  // only /api/shops/mine counts products - the public map list omits the field entirely, so this
  // defaults to 0 there rather than being a meaningful "this shop has no products". on the category
  // drill-down it means something narrower: how many products this shop prices *in that category*.
  final int productCount;

  // relative path returned by the backend (e.g. "/uploads/shops/xxx.jpg"), or null if no photo was set
  final String? imageUrl;

  // full, directly-loadable url for Image.network, built from the relative path above
  String? get imageFullUrl =>
      imageUrl == null ? null : '${ApiConfig.serverRoot}$imageUrl';

  /// Whether this shop has a rating worth showing at all.
  ///
  /// **Today this is always false, and that is the point.** `shops.rating` is a stored column and
  /// nothing writes to it - there is no reviews table yet - so every shop in the database reads
  /// 0.0. Printed unconditionally that renders as `⭐ 0.0`, which a shop owner opening the app reads
  /// as "customers rated us zero out of five" rather than as "nobody has rated us". Those are
  /// opposite meanings and the second one is the true one.
  ///
  /// The alternative was to invent a number - default to 5.0, or hide the zero behind a `?? 4.5` -
  /// which would put a rating this app cannot justify on every card. Showing nothing is the honest
  /// version: absence of a star says "no reviews" without claiming anything.
  ///
  /// **When a reviews table lands, this getter is the only thing that changes.** Every screen that
  /// draws a star already asks it, so ratings appear everywhere at once and cannot appear on one
  /// screen and not another.
  bool get hasRating => rating > 0;

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'] as int,
      name: json['name'] as String,
      contactPhone: json['contact_phone'] as String,
      address: json['address'] as String,
      category: ShopCategory.fromCode(json['category'] as String?),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      rating: (json['rating'] as num).toDouble(),
      // `as int?` and no `?? 0` throughout: the backend sends an explicit null for a shop with no
      // published index, and collapsing that to 0 here would undo the whole point of the nullable
      // column - a 0 index would render as "100% cheaper than the market"
      priceTier: PriceTier.tryFromCode(json['price_tier'] as String?),
      priceDifferencePercent: json['price_difference_percent'] as int?,
      basketPrice: json['basket_price'] as int?,
      isVip: json['is_vip'] as bool? ?? false,
      imageUrl: json['image_url'] as String?,
      productCount: json['product_count'] as int? ?? 0,
    );
  }

  // PUT /api/shops/{id} returns the shop without a product count (that column is only computed by
  // /api/shops/mine), so an edited shop would otherwise appear to lose its whole catalogue in the
  // list until the next refresh. this carries the field the response didn't restate.
  Shop copyWith({int? productCount}) => Shop(
        id: id,
        name: name,
        contactPhone: contactPhone,
        address: address,
        category: category,
        latitude: latitude,
        longitude: longitude,
        rating: rating,
        priceTier: priceTier,
        priceDifferencePercent: priceDifferencePercent,
        basketPrice: basketPrice,
        isVip: isVip,
        imageUrl: imageUrl,
        productCount: productCount ?? this.productCount,
      );
}

// same contract as ProductMutationException: the backend's messages are english and this app renders
// only ru/uz, so a failed edit/delete carries a stable machine-readable `code` (see writeShopError
// in backend/internal/endpoints/shops.go) that the ui turns into a localized message.
class ShopMutationException implements Exception {
  const ShopMutationException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'ShopMutationException($code): $message';
}
