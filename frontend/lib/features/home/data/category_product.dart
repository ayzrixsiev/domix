import 'package:frontend/features/products/data/product_model.dart';

/// A product as the "Популярные категории" drill-down shows it: the product itself, plus the name
/// of the shop selling it.
///
/// The shop's name is the difference between this list and a shop's own catalogue. Browsing
/// Сантехника across the whole market, "Труба ПВХ 20мм — 45 000 сум" is only useful attached to
/// *where*; on a shop's own page that context is the page.
///
/// A wrapper rather than a field on [Product], because a product genuinely does not have one - it
/// belongs to a shop by id, and only this one query bothers to join the name. Putting a nullable
/// `shopName` on the model would leave every other screen carrying a field that is always null.
class CategoryProduct {
  const CategoryProduct({required this.product, required this.shopName});

  final Product product;
  final String shopName;

  /// The backend flattens the two together - `GET /api/categories/{code}/products` returns product
  /// objects with one extra `shop_name` key - so this reuses [Product.fromJson] rather than
  /// duplicating a decoder that would then have to be kept in step with it.
  factory CategoryProduct.fromJson(Map<String, dynamic> json) {
    return CategoryProduct(
      product: Product.fromJson(json),
      shopName: json['shop_name'] as String? ?? '',
    );
  }
}
