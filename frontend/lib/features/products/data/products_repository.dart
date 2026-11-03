import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'product_model.dart';

// the go backend's single-product endpoints (backend/internal/endpoints/product_crud.go). the shop
// catalogue GET is public - a customer browsing the map has no account - and the five writes are
// the owner's: create, update, delete, and upload/remove one product photo (multipart).
class ProductsRepository {
  final AuthService _authService;

  ProductsRepository({AuthService? authService})
    : _authService = authService ?? AuthService();

  // built per call rather than kept as static fields, since every one of these urls carries an id
  static Uri _shopProductsUri(int shopId) =>
      Uri.parse('${ApiConfig.serverRoot}/api/shops/$shopId/products');
  static Uri _productUri(int productId) =>
      Uri.parse('${ApiConfig.serverRoot}/api/products/$productId');
  static Uri _productImageUri(int productId) =>
      Uri.parse('${ApiConfig.serverRoot}/api/products/$productId/image');

  /// Three times the other calls here: the rest of this file sends a few hundred bytes of json, and
  /// this pushes a few hundred *kilobytes* up the slow direction of a connection. Ten seconds would
  /// report a working upload as a failure, and the retry sends the same photo over the same link.
  static const Duration _uploadTimeout = Duration(seconds: 30);

  /// every product in one shop. public - this is what fills the grid on a shop's card, which any
  /// customer can open without logging in.
  Future<List<Product>> fetchShopProducts(int shopId) async {
    final response = await apiGet(_shopProductsUri(shopId));

    if (response.statusCode != 200) {
      throw _exceptionFrom(response);
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((json) => Product.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// add a product of the owner's own, on top of whatever the category template already gave them.
  /// the backend caps this at 30 and answers `product_limit_reached` past it.
  Future<Product> createProduct({
    required int shopId,
    required Product draft,
  }) async {
    final token = await _requireToken();

    final response = await appHttpClient
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

    final response = await appHttpClient
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

    final response = await appHttpClient
        .delete(
          _productUri(productId),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw _exceptionFrom(response);
    }
  }

  /// Uploads one photo and returns the product the server saved it against.
  ///
  /// Multipart rather than a base64 field on [updateProduct], because that is what the endpoint takes
  /// and because a photo is saved the moment it is picked while the rest of the form waits for
  /// «Сохранить». The response is the whole product, so the caller cannot end up with a photo attached
  /// to a stale price.
  Future<Product> uploadProductImage({
    required int productId,
    required String filePath,
  }) async {
    final token = await _requireToken();

    final request = http.MultipartRequest('POST', _productImageUri(productId))
      ..headers['Authorization'] = 'Bearer $token'
      // the field name the handler reads, and the only one it reads
      ..files.add(await http.MultipartFile.fromPath('image', filePath));

    // MultipartRequest streams, so this comes back as a StreamedResponse and has to be collected
    // before the shared error mapper (which reads .body) can look at it
    final streamed = await appHttpClient.send(request).timeout(_uploadTimeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw _exceptionFrom(response);
    }
    return Product.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Takes the owner's photo off a product. The product comes back with whatever photo it should have
  /// *now*, which for a seeded row is the catalogue's own shot - the server decides that, so the app
  /// never has to know which products have a default to fall back to.
  Future<Product> removeProductImage(int productId) async {
    final token = await _requireToken();

    final response = await appHttpClient
        .delete(
          _productImageUri(productId),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw _exceptionFrom(response);
    }
    return Product.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<String> _requireToken() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw const ProductMutationException(
        code: 'unauthorized',
        message: 'Not logged in',
      );
    }
    return token;
  }

  // a failed request should never surface as a raw decode crash, so anything unparseable collapses
  // into the same generic code the ui already knows how to render
  ProductMutationException _exceptionFrom(http.Response response) {
    // a 401 means the stored token will never work again. signing out here keeps the rule in the one
    // place every failed authenticated request in this file already funnels through.
    AuthService.handleUnauthorized(response);

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ProductMutationException(
        code: body['code'] as String? ?? 'server_error',
        message:
            body['error'] as String? ??
            'Request failed (${response.statusCode})',
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
