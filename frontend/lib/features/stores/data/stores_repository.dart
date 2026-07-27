import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'product_upload_result.dart';
import 'shop_model.dart';

// talks to the go backend's /api/shops endpoint: listing shops (for the map) and creating a new one
class StoresRepository {
  static final Uri _shopsUri = Uri.parse('${ApiConfig.serverRoot}/api/shops');
  static final Uri _myShopsUri = Uri.parse('${ApiConfig.serverRoot}/api/shops/mine');
  static final Uri _productsUploadUri = Uri.parse('${ApiConfig.serverRoot}/api/products/upload');

  final AuthService _authService;

  StoresRepository({AuthService? authService})
      : _authService = authService ?? AuthService();

  // fetch every shop - public data, no login required, used to plot pins on the map
  Future<List<Shop>> fetchStores() async {
    final response = await http.get(_shopsUri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to load shops (${response.statusCode})');
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((json) => Shop.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // fetch only the shops the current logged-in owner themselves own - backs the "my shops" list
  // that opens from Profile > Управление магазинами > Настройка магазинов
  Future<List<Shop>> fetchMyShops() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('You must be logged in to view your shops');
    }

    final response = await http
        .get(_myShopsUri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to load your shops (${response.statusCode})');
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((json) => Shop.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // create a new shop for the currently logged-in owner.
  // no photo yet - the backend leaves image_url null and the app shows a default banner instead
  // (see ShopBanner in map_screen.dart); real photo upload is a later feature.
  Future<Shop> createShop({
    required String name,
    required String contactPhone,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('You must be logged in to add a shop');
    }

    final response = await http
        .post(
          _shopsUri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'name': name,
            'contact_phone': contactPhone,
            'address': address,
            'latitude': latitude,
            'longitude': longitude,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 201) {
      String message = 'Failed to create shop';
      try {
        message = (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String? ?? message;
      } catch (_) {
        // response body wasn't the json shape we expected; keep the generic message
      }
      throw Exception(message);
    }

    return Shop.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // bulk-upload a .xlsx of products for a shop the caller owns (see backend/internal/endpoints/products.go).
  // re-uploading updates existing products by their Артикул instead of duplicating them.
  //
  // throws ProductUploadException on any non-200 so the ui can localize the reason off its `code`
  // rather than showing the backend's english text.
  Future<ProductUploadResult> uploadProductsFile({
    required int shopId,
    required String filePath,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw const ProductUploadException(code: 'unauthorized', message: 'Not logged in');
    }

    final request = http.MultipartRequest('POST', _productsUploadUri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['shop_id'] = shopId.toString()
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResponse = await request.send().timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw _uploadExceptionFrom(response);
    }

    return ProductUploadResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // a failed upload should never surface as a raw decode crash, so anything unparseable collapses
  // into the same generic code the ui already knows how to render
  ProductUploadException _uploadExceptionFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ProductUploadException(
        code: body['code'] as String? ?? 'server_error',
        message: body['error'] as String? ?? 'Upload failed (${response.statusCode})',
        limit: body['limit'] as int?,
      );
    } catch (_) {
      return ProductUploadException(
        code: 'server_error',
        message: 'Upload failed (${response.statusCode})',
      );
    }
  }
}
