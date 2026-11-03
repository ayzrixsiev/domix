import 'dart:convert';

import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/profile/data/auth_service.dart';

/// `/api/favorites`. Every call is authenticated - a favourite belongs to an account, and the server
/// takes the account from the token rather than from anything this app sends.
class FavoritesRepository {
  FavoritesRepository({AuthService? authService})
    : _authService = authService ?? AuthService();

  static final Uri _favoritesUri = Uri.parse(
    '${ApiConfig.serverRoot}/api/favorites',
  );

  final AuthService _authService;

  Future<Map<String, String>> _headers() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) throw const ApiException(401);
    return {'Authorization': 'Bearer $token'};
  }

  /// The whole list, which is also where the grids' hearts come from - see FavoritesController.
  Future<List<CategoryProduct>> fetchFavorites() async {
    final response = await apiGet(_favoritesUri, headers: await _headers());

    if (response.statusCode != 200) {
      if (AuthService.handleUnauthorized(response)) return const [];
      throw ApiException(response.statusCode);
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final item in data)
        CategoryProduct.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// PUT saves, DELETE removes, and both are idempotent on the server - which is what lets the app
  /// paint the heart first and send afterwards.
  Future<void> setFavorite(int productId, {required bool saved}) async {
    final uri = Uri.parse('${ApiConfig.serverRoot}/api/favorites/$productId');
    final headers = await _headers();

    final response = saved
        ? await appHttpClient
              .put(uri, headers: headers)
              .timeout(const Duration(seconds: 10))
        : await appHttpClient
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      if (AuthService.handleUnauthorized(response)) return;
      throw ApiException(response.statusCode);
    }
  }
}
