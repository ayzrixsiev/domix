import 'package:frontend/core/constants/api_config.dart';

// a single shop as returned by the go backend's /api/shops endpoint
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.contactPhone,
    required this.address,
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
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      rating: (json['rating'] as num).toDouble(),
      averagePaycheck: json['average_paycheck'] as int,
      imageUrl: json['image_url'] as String?,
      productCount: json['product_count'] as int? ?? 0,
    );
  }
}
