import 'package:frontend/features/stores/data/shop_category.dart';

/// One line of a list.
class WaybillItem {
  const WaybillItem({required this.name, required this.quantity});

  factory WaybillItem.fromJson(Map<String, dynamic> json) => WaybillItem(
    name: json['name'] as String? ?? '',
    quantity: json['quantity'] as String? ?? '',
  );

  final String name;
  final String quantity;

  Map<String, String> toJson() => {'name': name, 'quantity': quantity};
}

/// A list this customer sent from Корзина. Its [id] is the number on the накладная staff print. Exactly
/// one of [items] and [hasPhoto] is set, and the database holds that to be true.
class Waybill {
  const Waybill({
    required this.id,
    required this.category,
    required this.items,
    required this.hasPhoto,
    required this.createdAt,
  });

  factory Waybill.fromJson(Map<String, dynamic> json) => Waybill(
    id: json['id'] as int,
    category: ShopCategory.fromCode(json['shop_category'] as String?),
    items: [
      for (final item in json['items'] as List<dynamic>? ?? const [])
        WaybillItem.fromJson(item as Map<String, dynamic>),
    ],
    hasPhoto: json['has_photo'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final int id;
  final ShopCategory category;
  final List<WaybillItem> items;
  final bool hasPhoto;
  final DateTime createdAt;

  /// `02.11.2026`, on the phone's own clock.
  String get dateLabel {
    final local = createdAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year}';
  }
}
