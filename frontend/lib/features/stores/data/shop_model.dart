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

  // picked once when the shop was created and fixed from then on - it decided which product template
  // seeded the catalogue, so changing it later would leave the shop stocked with the wrong list
  final ShopCategory category;

  final double latitude;
  final double longitude;
  final double rating;

  /// How this shop's basket compares to its market, already decided by the backend.
  ///
  /// **The raw Basket Price Index never crosses the network**, which keeps every threshold on the
  /// server where changing one is a deploy. **Null until the owner has priced every product in the
  /// shop's template** (migration 000013), and null in exactly the same circumstances as
  /// [basketPrice], since the two come from one view row.
  final PriceTier? priceTier;

  /// unsigned, since [priceTier] carries the direction. null exactly when [priceTier] is.
  final int? priceDifferencePercent;

  /// What the shared basket costs here, in so'm - the index's own first step, before the division.
  /// Null under the same condition as [priceTier]: every template product priced, or nothing.
  final int? basketPrice;

  /// Whether this shop holds a paid placement. Computed by the backend from `shops.vip_until > now()`
  /// and sent as a boolean, so the app never compares a placement against the *device* clock.
  final bool isVip;

  // only /api/shops/mine counts products - the public map list omits the field, so 0 here is a
  // default rather than "this shop has no products". on the category drill-down it means something
  // narrower: how many products this shop prices *in that category*.
  final int productCount;

  // relative path returned by the backend (e.g. "/uploads/shops/xxx.jpg"), or null if no photo was set
  final String? imageUrl;

  // full, directly-loadable url for Image.network, built from the relative path above
  String? get imageFullUrl =>
      imageUrl == null ? null : '${ApiConfig.serverRoot}$imageUrl';

  /// Whether this shop has a rating worth showing at all.
  ///
  /// **Today this is always false, and that is the point**: nothing writes `shops.rating`, so every
  /// shop reads 0.0 and `⭐ 0.0` says "customers rated us zero" where the truth is "nobody has rated
  /// us". When a reviews table lands, this getter is the only thing that changes.
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
      // `as int?` and no `?? 0`: the backend sends an explicit null for a shop with no published index,
      // and a 0 index would render as "100% cheaper than the market"
      priceTier: PriceTier.tryFromCode(json['price_tier'] as String?),
      priceDifferencePercent: json['price_difference_percent'] as int?,
      basketPrice: json['basket_price'] as int?,
      isVip: json['is_vip'] as bool? ?? false,
      imageUrl: json['image_url'] as String?,
      productCount: json['product_count'] as int? ?? 0,
    );
  }

  // PUT /api/shops/{id} returns the shop without a product count (only /api/shops/mine computes it),
  // so without this an edited shop appears to lose its whole catalogue until the next refresh
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

// the same contract as ProductMutationException: the backend writes english and this app renders
// only ru/uz, so a failed edit or delete carries a stable machine-readable `code` the ui localizes.
class ShopMutationException implements Exception {
  const ShopMutationException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'ShopMutationException($code): $message';
}
