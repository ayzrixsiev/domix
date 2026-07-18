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
  static const _nameKey = 'domix_user_name';
  static const _phoneKey = 'domix_user_phone';

  // exponential backoff with jitter for network retries
  // returns delay in milliseconds for the nth attempt (0-indexed)
  static Duration _calculateBackoff(int attempt) {
    const baseDelayMs = 200;
    const maxDelayMs = 5000;
    
    // exponential: 200ms, 400ms, 800ms, 1600ms, 5000ms (capped)
    final delayMs = (baseDelayMs * (1 << attempt)).clamp(0, maxDelayMs);
    
    // small random jitter to prevent thundering herd
    final jitterMs = (delayMs * 0.1 * (0.5 + (DateTime.now().millisecond % 100) / 100)).toInt();
    
    return Duration(milliseconds: delayMs + jitterMs);
  }

  // execute http operation with exponential backoff retry logic
  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation,
    String operationName, {
    int maxAttempts = 3,
  }) async {
    int attempt = 0;
    
    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        
        // if max attempts exceeded, throw the error
        if (attempt >= maxAttempts) {
          throw Exception('$operationName failed after $maxAttempts attempts: $e');
        }
        
        // wait before retrying with exponential backoff
        final delay = _calculateBackoff(attempt - 1);
        await Future.delayed(delay);
      }
    }
  }

  // 1. send collected name and role to the backend and get back telegram link
  Future<AuthInitResult> initSession({required String name, required String role}) async {
    return _executeWithRetry(
      () async {
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
      },
      'initSession',
      maxAttempts: 3,
    );
  }

  // 2. ask go server for login completion
  Future<AuthStatusResult> checkStatus(String sessionId) async {
    return _executeWithRetry(
      () async {
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
      },
      'checkStatus',
      maxAttempts: 3,
    );
  }

  // 3. save jwt, role, name, and phone in the user's hardware encrypted storage
  Future<void> saveSession({
    required String token,
    required String role,
    required String name,
    required String phone,
  }) async {
    await _storage.write(key: _jwtKey, value: token);
    await _storage.write(key: _roleKey, value: role);
    await _storage.write(key: _nameKey, value: name);
    await _storage.write(key: _phoneKey, value: phone);
  }

  // getters to retrieve cached profile data on cold boot
  Future<String?> getToken() async => await _storage.read(key: _jwtKey);
  Future<String?> getRole() async => await _storage.read(key: _roleKey);
  Future<String?> getName() async => await _storage.read(key: _nameKey);
  Future<String?> getPhone() async => await _storage.read(key: _phoneKey);
  
  // 4. wipe all cached keys upon logout
  Future<void> logout() async {
    await _storage.delete(key: _jwtKey);
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _nameKey);
    await _storage.delete(key: _phoneKey);
  }
}
