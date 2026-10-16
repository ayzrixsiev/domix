import 'dart:convert';

import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// Talks to the two public discovery endpoints behind the home screen. No `Authorization` header: the
/// home screen draws before anyone has logged in. A refusal throws [ApiException] with the status, so
/// a screen can tell "server busy" from "phone offline" - see [LoadFailure].
class HomeRepository {
  /// Mirrors `searchResultsLimit` on the server. **A page shorter than this is the last one**, which
  /// is how the results screen knows whether to offer "Ещё" without asking the api.
  static const int searchPageSize = 100;

  static final Uri _homeUri = Uri.parse('${ApiConfig.serverRoot}/api/home');

  /// The whole home screen in one request, matching the single `GET /api/home`: all three sections
  /// always render together, so three calls would only buy three chances to half-populate the page.
  Future<HomeContent> fetchHomeContent() async {
    final response = await apiGet(_homeUri);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode);
    }

    return HomeContent.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Every priced product in one category, across every shop, cheapest first - what a "Популярные
  /// категории" tile opens. Fetched on tap, never with the home load: eleven of the twelve
  /// categories' products would be thrown away on every launch.
  Future<List<CategoryProduct>> fetchProductsByCategory(
    ProductCategory category,
  ) async {
    final uri = Uri.parse(
      '${ApiConfig.serverRoot}/api/categories/${category.code}/products',
    );
    return _fetchProducts(uri);
  }

  /// Products matching a search term, across every shop. The backend answers with the shape
  /// [fetchProductsByCategory] gets, so both render through the same screen and grid.
  ///
  /// `queryParameters` rather than concatenation: `&`, `#` or `%` in a typed query would truncate the
  /// search or break the parse.
  ///
  /// [offset] is the number of rows already held, which is how the next page is asked for.
  Future<List<CategoryProduct>> searchProducts(
    String query, {
    int offset = 0,
  }) async {
    final uri = Uri.parse('${ApiConfig.serverRoot}/api/products/search')
        .replace(
          queryParameters: {'q': query, if (offset > 0) 'offset': '$offset'},
        );
    return _fetchProducts(uri);
  }

  /// The shared half of the two calls above. `as List<dynamic>` is what makes the backend's
  /// `make([]T, 0, n)` load-bearing - a `null` body throws here rather than decoding to an empty list.
  Future<List<CategoryProduct>> _fetchProducts(Uri uri) async {
    final response = await apiGet(uri);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode);
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final item in data)
        CategoryProduct.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// The names offered under the search field as it is typed, from `GET /api/products/suggest`.
  ///
  /// The server answers this one out of memory, with no database behind it, which is what makes a
  /// request every few keystrokes affordable. A query too short to look up comes back as an empty
  /// list rather than an error.
  Future<List<String>> suggestProducts(String query) async {
    final uri = Uri.parse(
      '${ApiConfig.serverRoot}/api/products/suggest',
    ).replace(queryParameters: {'q': query});
    final response = await apiGet(uri, timeout: const Duration(seconds: 4));

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode);
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return [for (final name in data) name as String];
  }
}
