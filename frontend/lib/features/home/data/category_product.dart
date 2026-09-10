import 'package:frontend/features/products/data/product_model.dart';

/// A product as the category drill-down shows it: the product plus the shop selling it - across the
/// market a price is only useful attached to *where*. A wrapper rather than a field on [Product],
/// since only this one query joins the shop name.
class CategoryProduct {
  const CategoryProduct({required this.product, required this.shopName});

  final Product product;
  final String shopName;

  /// The backend flattens the two - product json with one extra `shop_name` key - so this reuses
  /// [Product.fromJson] rather than keeping a second decoder in step with it.
  factory CategoryProduct.fromJson(Map<String, dynamic> json) {
    return CategoryProduct(
      product: Product.fromJson(json),
      shopName: json['shop_name'] as String? ?? '',
    );
  }
}
