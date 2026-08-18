import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:frontend/core/constants/api_config.dart';

// blueprint container to hold the data send by backend
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

/// The account as `/api/me` currently reports it.
class MeResult {
  const MeResult({required this.name, required this.phone, required this.role});

  final String name;
  final String phone;
  final String role;
}

/// The server refused our token: deleted account, or an expiry we did not notice locally. Distinct
/// from a plain [Exception] so a caller can tell "you are signed out" from "the network is down" -
/// the second must never sign anybody out.
class SessionExpiredException implements Exception {
  const SessionExpiredException();

  @override
  String toString() => 'SessionExpiredException';
}

class AuthService {
  /// Called when the backend rejects our token, so the app can drop back to the guest state.
  ///
  /// A callback registered by [AuthController] at startup, rather than this file importing the
  /// controller: `data/` sits below `presentation/` and reaching upwards would make the two
  /// impossible to build or test apart. Every repository already depends on AuthService for the
  /// token, so this is the one place all of them can reach without learning about each other.
  static void Function()? onSessionInvalidated;

  /// Whether [response] means the stored token is no longer usable - and if so, signs the user out.
  ///
  /// **A JWT here lives four months and the server keeps no revocation list**, so nothing about the
  /// token itself changes when the account behind it is deleted or disabled. The only signal the app
  /// ever gets is a 401 on the next authenticated call, which is why every one of them runs through
  /// this: without it a deleted user goes on using the app from a phone that never found out, until
  /// the token expires months later.
  ///
  /// Any 401 counts, not just `account_deleted`. An expired signature and a removed account leave
  /// the app in the same place - holding a token that will never work again - and the response to
  /// both is to stop pretending it is signed in.
  static bool handleUnauthorized(http.Response response) {
    if (response.statusCode != 401) return false;
    onSessionInvalidated?.call();
    return true;
  }

  // private, uncopied data
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/auth',
  );
  /// `/api/me` sits outside the `/api/auth` prefix baked into [_baseUrl], so it is built off the
  /// plain server root the rest of the app uses (see ApiConfig).
  static final Uri _meUri = Uri.parse('${ApiConfig.serverRoot}/api/me');

  final _storage = const FlutterSecureStorage();

  static const _jwtKey = 'domix_jwt_token';
  static const _roleKey = 'domix_user_role';
  static const _nameKey = 'domix_user_name';
  static const _phoneKey = 'domix_user_phone';

  // exponential backoff with jitter for network retries
  // we give a backend a nap to recover in case server fails, without constantly calling for it within short period of time
  // initial wait before another call is 200, and then it gets doubled until 5000 (5 seconds)
  static Duration _calculateBackoff(int attempt) {
    const baseDelayMs = 200;
    const maxDelayMs = 5000;
    
    // exponential: 200ms, 400ms, 800ms, 1600ms, 5000ms (capped)
    final delayMs = (baseDelayMs * (1 << attempt)).clamp(0, maxDelayMs);
    
    // small random jitter to prevent thundering herd - all users calling backend at the same time after small crush, it is going to crush server again
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
        return await operation(); // run the function which is wrappeed by _executeWithRetry wrapper
      } catch (e) {
        attempt++;
        
        // if max attempts exceeded, throw the error
        if (attempt >= maxAttempts) {
          throw Exception('$operationName failed after $maxAttempts attempts: $e');
        }
        
        // pause/wait before retrying the wrapped function with exponential backoff logic
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

  /// Whether a stored token has already passed its own expiry, read **from the token itself**.
  ///
  /// A JWT is three base64 chunks separated by dots; the middle one is plain JSON carrying `exp`, a
  /// unix timestamp. Reading it needs no key and no network - the signature is what we cannot forge,
  /// not what we cannot read - so an app opened on a plane can still tell that its four months are
  /// up and show a guest screen instead of a profile it can no longer use.
  ///
  /// Anything unparseable counts as expired. A token we cannot read is a token we cannot send.
  static bool isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      // base64url without padding is what JWT uses; normalize() puts the '=' back so decode accepts it
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;

      final exp = payload['exp'];
      if (exp is! int) return true;

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      // a minute of slack, so a clock a little ahead of the server's does not sign someone out on
      // the very last minute of a valid token
      return DateTime.now().toUtc().isAfter(expiresAt.subtract(const Duration(minutes: 1)));
    } catch (_) {
      return true;
    }
  }

  /// Asks the server who we are now: `GET /api/me`.
  ///
  /// Returns the account on success, throws [SessionExpiredException] when the server says the
  /// session is dead, and throws something else when the *network* is dead. **Those two have to stay
  /// distinguishable**: signing a user out because their train went into a tunnel is a bug, not
  /// caution.
  Future<MeResult> fetchMe() async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw const SessionExpiredException();

    final response = await http
        .get(_meUri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 401) {
      onSessionInvalidated?.call();
      throw const SessionExpiredException();
    }
    if (response.statusCode != 200) {
      // 5xx, 429, anything else - the server is having a moment, but it never said this token is
      // bad. leave the session alone.
      throw Exception('Could not verify the session (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MeResult(
      name: body['name'] as String? ?? '',
      phone: body['phone'] as String? ?? '',
      role: body['role'] as String? ?? 'customer',
    );
  }
  /// Destroys the account on the server: `DELETE /api/me`.
  ///
  /// **This does not touch local storage** - wiping the phone is [logout]'s job, and the caller does
  /// both in order. Keeping them apart is what makes the failure case correct: if the server never
  /// answered, the account may well still exist, and an app that had already erased its own token
  /// would leave the user with no way back in to try again.
  ///
  /// A 401 is treated as success rather than as an error. It means the row is already gone - most
  /// likely deleted from the user's other phone - and the goal ("this account should not exist") is
  /// satisfied. Throwing here would show a failure dialog for something that worked.
  Future<void> deleteAccount() async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw const SessionExpiredException();

    final response = await http
        .delete(_meUri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200 || response.statusCode == 401) return;

    throw Exception('Could not delete the account (${response.statusCode})');
  }

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
