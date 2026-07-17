import 'dart:convert';                                                  // convert data into json
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';    // to save jwt in the user's phone

// container to hold the data send by backend
class AuthInitResult {
  final String sessionId;
  final String telegramUrl;

  AuthInitResult({required this.sessionId, required this.telegramUrl});
}

class AuthStatusResult {
  final String status; // "pending", "success", or "not_found"
  final String? token;
  final String? phone;
  final String? role;
  final String? name;

  AuthStatusResult({
    required this.status,
    this.token,
    this.phone,
    this.role,
    this.name,
  });

  bool get isSuccess => status == 'success';
}

class AuthService {
  // private, uncopied data
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/auth',
  );
  final _storage = const FlutterSecureStorage();
  static const _jwtKey = 'domix_jwt_token';
  static const _roleKey = 'domix_user_role';

  // 1. send collected name and role to the backend and get back telegram link
  Future<AuthInitResult> initSession({required String name, required String role}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/init'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'role': role}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return AuthInitResult(
        sessionId: data['session_id'],
        telegramUrl: data['telegram_url'],
      );
    } else {
      throw Exception('Failed to initialize login session: ${response.statusCode}');
    }
  }

  // 2. ask go server for login completion
  Future<AuthStatusResult> checkStatus(String sessionId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/status?session_id=$sessionId'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return AuthStatusResult(
        status: data['status'] ?? 'not_found',
        token: data['token'],
        phone: data['phone'],
        role: data['role'],
        name: data['name'],
      );
    } else {
      throw Exception('Server communication error');
    }
  }

  // 3. save jwt and role in the user's hardware encrypted storage
  Future<void> saveSession({required String token, required String role}) async {
    await _storage.write(key: _jwtKey, value: token);
    await _storage.write(key: _roleKey, value: role);
  }

  Future<String?> getToken() async => await _storage.read(key: _jwtKey);
  Future<String?> getRole() async => await _storage.read(key: _roleKey);
  
  Future<void> logout() async {
    await _storage.delete(key: _jwtKey);
    await _storage.delete(key: _roleKey);
  }
}