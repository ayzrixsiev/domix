import 'package:frontend/core/constants/api_config.dart';
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
    required this.averagePaycheck,
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
  final int averagePaycheck;

  // only /api/shops/mine counts products - the public map list omits the field entirely, so this
  // defaults to 0 there rather than being a meaningful "this shop has no products"
  final int productCount;

  // relative path returned by the backend (e.g. "/uploads/shops/xxx.jpg"), or null if no photo was set
  final String? imageUrl;

  // full, directly-loadable url for Image.network, built from the relative path above
  String? get imageFullUrl =>
      imageUrl == null ? null : '${ApiConfig.serverRoot}$imageUrl';

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
      averagePaycheck: json['average_paycheck'] as int,
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
        averagePaycheck: averagePaycheck,
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
