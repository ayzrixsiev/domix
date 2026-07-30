import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'product_model.dart';

// talks to the go backend's single-product endpoints (backend/internal/endpoints/product_crud.go).
// this file used to be a hardcoded stub returning one "Demo Product"; if anything elsewhere still
// describes it that way, that note is stale.
//
//   GET    /api/shops/{id}/products  - public, no token: a customer browsing the map has no account
//   POST   /api/shops/{id}/products  - owner adds one of their own products
//   PUT    /api/products/{id}        - owner edits one product
//   DELETE /api/products/{id}        - owner removes one of their own
class ProductsRepository {
  final AuthService _authService;

  ProductsRepository({AuthService? authService})
      : _authService = authService ?? AuthService();

  // built per call rather than kept as static fields like StoresRepository's, since every one of
  // these urls carries an id
  static Uri _shopProductsUri(int shopId) =>
      Uri.parse('${ApiConfig.serverRoot}/api/shops/$shopId/products');
  static Uri _productUri(int productId) =>
      Uri.parse('${ApiConfig.serverRoot}/api/products/$productId');

  /// every product in one shop. public - this is what fills the grid on a shop's card, which any
  /// customer can open without logging in.
  Future<List<Product>> fetchShopProducts(int shopId) async {
    final response = await http
        .get(_shopProductsUri(shopId))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw _exceptionFrom(response);
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((json) => Product.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// add a product of the owner's own, on top of whatever the category template already gave them.
  /// the backend caps this at 20 and answers `product_limit_reached` past it.
  Future<Product> createProduct({required int shopId, required Product draft}) async {
    final token = await _requireToken();

    final response = await http
        .post(
          _shopProductsUri(shopId),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(draft.toRequestJson()),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 201) {
      throw _exceptionFrom(response);
    }

    return Product.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// a full replacement, not a patch: the edit form always submits every field, and the backend
  /// rejects a blank name/category/unit rather than reading it as "leave this one alone".
  Future<Product> updateProduct(Product product) async {
    final token = await _requireToken();

    final response = await http
        .put(
          _productUri(product.id),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(product.toRequestJson()),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw _exceptionFrom(response);
    }

    return Product.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// only the owner's own products can go; the backend refuses template rows with
  /// `template_product`, since they are the shared basket every shop of that category is compared on
  Future<void> deleteProduct(int productId) async {
    final token = await _requireToken();

    final response = await http
        .delete(_productUri(productId), headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw _exceptionFrom(response);
    }
  }

  Future<String> _requireToken() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw const ProductMutationException(code: 'unauthorized', message: 'Not logged in');
    }
    return token;
  }

  // a failed request should never surface as a raw decode crash, so anything unparseable collapses
  // into the same generic code the ui already knows how to render
  ProductMutationException _exceptionFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ProductMutationException(
        code: body['code'] as String? ?? 'server_error',
        message: body['error'] as String? ?? 'Request failed (${response.statusCode})',
        limit: body['limit'] as int?,
      );
    } catch (_) {
      return ProductMutationException(
        code: 'server_error',
        message: 'Request failed (${response.statusCode})',
      );
    }
  }
}
