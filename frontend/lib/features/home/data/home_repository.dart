import 'dart:convert';

import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_get.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// Talks to the two public discovery endpoints behind the home screen.
///
/// No `Authorization` header anywhere in this file, and that is deliberate rather than an oversight:
/// the home screen is the first thing the app draws, before anyone has logged in, so both endpoints
/// are public on the backend too (see `endpoints.Home`). Attaching a token would work but would
/// imply a permission model that isn't there.
class HomeRepository {
  static final Uri _homeUri = Uri.parse('${ApiConfig.serverRoot}/api/home');

  /// The whole home screen in one request.
  ///
  /// One call rather than three, matching the single `GET /api/home` on the backend: the screen
  /// always renders all three sections together, so three requests would buy nothing but three
  /// chances for one of them to fail on its own and leave the page half-populated.
  Future<HomeContent> fetchHomeContent() async {
    final response = await apiGet(_homeUri);

    if (response.statusCode != 200) {
      throw Exception('Failed to load home content (${response.statusCode})');
    }

    return HomeContent.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Every priced product in one category, across every shop, cheapest first - what a
  /// "Популярные категории" tile opens.
  ///
  /// Fetched only when a tile is tapped, never as part of the home load. Twelve categories' worth
  /// of products is far more than the home screen could use, and eleven of the twelve would be
  /// thrown away on every launch.
  Future<List<CategoryProduct>> fetchProductsByCategory(ProductCategory category) async {
    final uri = Uri.parse('${ApiConfig.serverRoot}/api/categories/${category.code}/products');
    return _fetchProducts(uri);
  }

  /// Products matching a search term, across every shop - what the home screen's field submits to.
  ///
  /// The backend answers with the exact shape `fetchProductsByCategory` gets, so the results render
  /// through the same screen and the same grid. A search result and a category result are the same
  /// object arriving by a different door.
  ///
  /// `Uri`'s `queryParameters` rather than string concatenation: the query is whatever the customer
  /// typed, which is Cyrillic at minimum and may contain `&`, `#` or `%`. Pasted into a url by hand,
  /// any of those three silently truncates the search or breaks the parse.
  Future<List<CategoryProduct>> searchProducts(String query) async {
    final uri = Uri.parse('${ApiConfig.serverRoot}/api/products/search')
        .replace(queryParameters: {'q': query});
    return _fetchProducts(uri);
  }

  /// The shared half of the two calls above: fetch, check, decode a list of products.
  ///
  /// `as List<dynamic>` is the line that makes the backend's `make([]T, 0, n)` load-bearing - a
  /// `null` body would throw here rather than decode to an empty list.
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
