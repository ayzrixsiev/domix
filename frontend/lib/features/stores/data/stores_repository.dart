import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_get.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'shop_category.dart';
import 'shop_model.dart';

// talks to the go backend's /api/shops endpoint: listing shops (for the map) and creating a new one
class StoresRepository {
  static final Uri _shopsUri = Uri.parse('${ApiConfig.serverRoot}/api/shops');
  static final Uri _myShopsUri = Uri.parse('${ApiConfig.serverRoot}/api/shops/mine');

  final AuthService _authService;

  StoresRepository({AuthService? authService})
      : _authService = authService ?? AuthService();

  // fetch every shop - public data, no login required, used to plot pins on the map
  Future<List<Shop>> fetchStores() async {
    final response = await apiGet(_shopsUri);

    if (response.statusCode != 200) {
      throw Exception('Failed to load shops (${response.statusCode})');
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((json) => Shop.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// One shop, by id - what a product tile has to work with when it is tapped from search or a
  /// category browse.
  ///
  /// **Returns null for a 404 rather than throwing**, because "this shop was deleted while you were
  /// reading about its cement" is not a failure the reader can retry out of, and the screen says a
  /// different sentence for it. Everything else throws, and that one *is* worth a Повторить button.
  Future<Shop?> fetchShop(int shopId) async {
    final response = await apiGet(_shopUri(shopId));

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Failed to load shop (${response.statusCode})');
    }

    return Shop.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // fetch only the shops the current logged-in owner themselves own - backs the "my shops" list
  // that opens from Profile > Управление магазинами > Настройка магазинов
  Future<List<Shop>> fetchMyShops() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('You must be logged in to view your shops');
    }

    final response = await apiGet(_myShopsUri, headers: {'Authorization': 'Bearer $token'});

    if (response.statusCode != 200) {
      AuthService.handleUnauthorized(response);
      throw Exception('Failed to load your shops (${response.statusCode})');
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((json) => Shop.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // create a new shop for the currently logged-in owner.
  //
  // [category] is the one field here with a side effect beyond the shop row: the backend copies
  // that category's product template into the new shop's catalogue in the same transaction, so the
  // owner lands on a screen of ready-made products needing only prices rather than an empty one.
  //
  // no photo yet - the backend leaves image_url null and the app shows a default banner instead
  // (see ShopBanner in map_screen.dart); real photo upload is a later feature.
  Future<Shop> createShop({
    required String name,
    required String contactPhone,
    required String address,
    required ShopCategory category,
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
            'category': category.code,
            'latitude': latitude,
            'longitude': longitude,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 201) {
      AuthService.handleUnauthorized(response);
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

  // edit a shop the caller owns. a full replacement, not a patch: the edit form always submits all
  // four fields, and the backend rejects a blank name/phone/address rather than treating it as
  // "leave this one alone". image_url is untouched - photos aren't uploadable yet.
  Future<Shop> updateShop({
    required int shopId,
    required String name,
    required String contactPhone,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw const ShopMutationException(code: 'unauthorized', message: 'Not logged in');
    }

    final response = await http
        .put(
          _shopUri(shopId),
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

    if (response.statusCode != 200) {
      throw _mutationExceptionFrom(response);
    }

    return Shop.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // delete a shop the caller owns. its products go with it (products.shop_id cascades), which is why
  // the ui puts this behind a typed confirmation rather than a plain "are you sure".
  Future<void> deleteShop(int shopId) async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw const ShopMutationException(code: 'unauthorized', message: 'Not logged in');
    }

    final response = await http
        .delete(_shopUri(shopId), headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw _mutationExceptionFrom(response);
    }
  }

  // built per call rather than kept as a static field like the three above, since the id varies
  static Uri _shopUri(int shopId) => Uri.parse('${ApiConfig.serverRoot}/api/shops/$shopId');

  // a failed edit/delete should never surface as a raw decode crash, so anything unparseable
  // collapses into the same generic code the ui already knows how to render
  ShopMutationException _mutationExceptionFrom(http.Response response) {
    // a 401 means the stored token will never work again - the account was deleted, or the
    // signature expired. sign out here rather than in each caller: every failed authenticated
    // request in this file already funnels through this one function.
    AuthService.handleUnauthorized(response);

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ShopMutationException(
        code: body['code'] as String? ?? 'server_error',
        message: body['error'] as String? ?? 'Request failed (${response.statusCode})',
      );
    } catch (_) {
      return ShopMutationException(
        code: 'server_error',
        message: 'Request failed (${response.statusCode})',
      );
    }
  }
}
