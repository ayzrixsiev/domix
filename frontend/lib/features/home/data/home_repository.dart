import 'dart:convert';

import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_get.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// Talks to the two public discovery endpoints behind the home screen. No `Authorization` header
/// anywhere here: the home screen draws before anyone has logged in.
class HomeRepository {
  static final Uri _homeUri = Uri.parse('${ApiConfig.serverRoot}/api/home');

  /// The whole home screen in one request, matching the single `GET /api/home`: all three sections
  /// always render together, so three calls would only buy three chances to half-populate the page.
  Future<HomeContent> fetchHomeContent() async {
    final response = await apiGet(_homeUri);

    if (response.statusCode != 200) {
      throw Exception('Failed to load home content (${response.statusCode})');
    }

    return HomeContent.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Every priced product in one category, across every shop, cheapest first - what a "Популярные
  /// категории" tile opens. Fetched on tap, never with the home load: eleven of the twelve
  /// categories' products would be thrown away on every launch.
  Future<List<CategoryProduct>> fetchProductsByCategory(ProductCategory category) async {
    final uri = Uri.parse('${ApiConfig.serverRoot}/api/categories/${category.code}/products');
    return _fetchProducts(uri);
  }

  /// Products matching a search term, across every shop. The backend answers with the shape
  /// [fetchProductsByCategory] gets, so both render through the same screen and grid.
  ///
  /// `queryParameters` rather than concatenation: `&`, `#` or `%` in a typed query would truncate the
  /// search or break the parse.
  Future<List<CategoryProduct>> searchProducts(String query) async {
    final uri = Uri.parse('${ApiConfig.serverRoot}/api/products/search')
        .replace(queryParameters: {'q': query});
    return _fetchProducts(uri);
  }

  /// The shared half of the two calls above. `as List<dynamic>` is what makes the backend's
  /// `make([]T, 0, n)` load-bearing - a `null` body throws here rather than decoding to an empty list.
  Future<List<CategoryProduct>> _fetchProducts(Uri uri) async {
    final response = await apiGet(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to load products (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final item in data) CategoryProduct.fromJson(item as Map<String, dynamic>),
    ];
  }
}
