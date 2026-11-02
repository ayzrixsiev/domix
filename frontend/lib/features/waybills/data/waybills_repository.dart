import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/waybills/data/waybill.dart';

/// A send the server refused, or could not be asked. [code] is the server's, and the screen localizes it.
class WaybillSendException implements Exception {
  const WaybillSendException(this.code);

  final String code;

  @override
  String toString() => 'WaybillSendException($code)';
}

/// `/api/waybills`. The account comes from the token, so nothing here can name somebody else's list.
class WaybillsRepository {
  WaybillsRepository({AuthService? authService})
    : _authService = authService ?? AuthService();

  static final Uri _waybillsUri = Uri.parse(
    '${ApiConfig.serverRoot}/api/waybills',
  );
  static final Uri _photoUploadUri = Uri.parse(
    '${ApiConfig.serverRoot}/api/waybills/photo',
  );

  // a full-size photo over 3G, which is the slowest thing this app ever asks of a connection
  static const Duration _uploadTimeout = Duration(seconds: 90);
  static const Duration _sendTimeout = Duration(seconds: 20);

  final AuthService _authService;

  Future<String> _token() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) throw const ApiException(401);
    return token;
  }

  Future<List<Waybill>> fetchWaybills() async {
    final response = await apiGet(
      _waybillsUri,
      headers: {'Authorization': 'Bearer ${await _token()}'},
    );

    if (response.statusCode != 200) {
      if (AuthService.handleUnauthorized(response)) return const [];
      throw ApiException(response.statusCode);
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final item in data) Waybill.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Waybill> sendList({
    required String requestId,
    required ShopCategory category,
    required List<WaybillItem> items,
  }) async {
    final response = await appHttpClient
        .post(
          _waybillsUri,
          headers: {
            'Authorization': 'Bearer ${await _token()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'request_id': requestId,
            'shop_category': category.code,
            'items': [for (final item in items) item.toJson()],
          }),
        )
        .timeout(_sendTimeout);
    return _sent(response);
  }

  Future<Waybill> sendPhoto({
    required String requestId,
    required ShopCategory category,
    required String filePath,
  }) async {
    final request = http.MultipartRequest('POST', _photoUploadUri)
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..fields['request_id'] = requestId
      ..fields['shop_category'] = category.code
      ..files.add(await http.MultipartFile.fromPath('image', filePath));

    final streamed = await appHttpClient.send(request).timeout(_uploadTimeout);
    return _sent(await http.Response.fromStream(streamed));
  }

  Future<Uint8List> fetchPhoto(int waybillId) async {
    final uri = Uri.parse(
      '${ApiConfig.serverRoot}/api/waybills/$waybillId/photo',
    );
    final response = await apiGet(
      uri,
      headers: {'Authorization': 'Bearer ${await _token()}'},
      timeout: const Duration(seconds: 30),
    );

    if (response.statusCode != 200) {
      AuthService.handleUnauthorized(response);
      throw ApiException(response.statusCode);
    }
    return response.bodyBytes;
  }

  Waybill _sent(http.Response response) {
    if (response.statusCode == 201) {
      return Waybill.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    AuthService.handleUnauthorized(response);
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw WaybillSendException(body['code'] as String? ?? 'server_error');
    } on FormatException {
      throw const WaybillSendException('server_error');
    }
  }
}
