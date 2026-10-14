import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_client.dart';

// the data the backend sends back when a login session is opened
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

/// What `/api/auth/request-code` answered: the canonical number the code went to, and the two
/// timers the screen counts down.
class CodeRequestResult {
  const CodeRequestResult({
    required this.phone,
    required this.expiresIn,
    required this.resendAfter,
  });

  /// `998XXXXXXXXX` - the server's spelling, which is what `/verify` has to be called with.
  final String phone;

  /// Seconds the code stays valid.
  final int expiresIn;

  /// Seconds before another code may be asked for.
  final int resendAfter;
}

/// A refusal from the auth endpoints, carrying **the server's machine-readable code** rather than
/// its sentence: the server answers in one language and the app draws the reader's, so the mapping
/// to written copy belongs in AppLocalizations.authErrorFor.
class AuthApiException implements Exception {
  const AuthApiException(this.code, {this.retryAfter});

  factory AuthApiException.from(http.Response response, Map<String, dynamic> body) {
    final retryAfter = body['retry_after'];
    return AuthApiException(
      body['code'] as String? ?? 'server_error',
      retryAfter: retryAfter is int ? retryAfter : null,
    );
  }

  final String code;

  /// Seconds to wait, on the two refusals that are about time (`code_cooldown`, `code_quota`).
  final int? retryAfter;

  @override
  String toString() => 'AuthApiException($code)';
}

/// The account as `/api/me` currently reports it.
class MeResult {
  const MeResult({required this.name, required this.phone, required this.role});

  final String name;
  final String phone;
  final String role;
}

// the server refused our token. its own type so a caller can tell "signed out" from "network is
// down" - the second must never sign anybody out.
class SessionExpiredException implements Exception {
  const SessionExpiredException();

  @override
  String toString() => 'SessionExpiredException';
}

class AuthService {
  // registered by AuthController at startup rather than imported: data/ sits below presentation/.
  // silent tells the ui whether to explain the logout - see handleUnauthorized and fetchMe.
  static void Function({required bool silent})? onSessionInvalidated;

  // a jwt here lives four months and the server keeps no revocation list, so a 401 on any
  // authenticated call is the only signal that the account behind the token is gone or disabled.
  // not silent: this 401 answers something the user just did, so they get told why they are out.
  static bool handleUnauthorized(http.Response response) {
    if (response.statusCode != 401) return false;
    onSessionInvalidated?.call(silent: false);
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

  // exponential backoff with jitter: gives a struggling backend room to recover, and the jitter stops
  // every phone retrying in the same instant and knocking it over again
  static Duration _calculateBackoff(int attempt) {
    const baseDelayMs = 200;
    const maxDelayMs = 5000;
    
    // exponential: 200ms, 400ms, 800ms, 1600ms, 5000ms (capped)
    final delayMs = (baseDelayMs * (1 << attempt)).clamp(0, maxDelayMs);
    
    final jitterMs = (delayMs * 0.1 * (0.5 + (DateTime.now().millisecond % 100) / 100)).toInt();
    
    return Duration(milliseconds: delayMs + jitterMs);
  }

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
        
        if (attempt >= maxAttempts) {
          throw Exception('$operationName failed after $maxAttempts attempts: $e');
        }
        
        final delay = _calculateBackoff(attempt - 1);
        await Future.delayed(delay);
      }
    }
  }

  Future<AuthInitResult> initSession({required String name, required String role}) async {
    return _executeWithRetry(
      () async {
        final response = await appHttpClient.post(
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

  Future<AuthStatusResult> checkStatus(String sessionId) async {
    return _executeWithRetry(
      () async {
        final response = await appHttpClient.get(
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

  // hardware-encrypted storage: a stolen phone must not yield a four-month token
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

  // cached profile data, read on cold boot
  Future<String?> getToken() async => await _storage.read(key: _jwtKey);

  /// Whether a stored token has already passed its own expiry, read **from the token itself**: a JWT's
  /// middle chunk is plain JSON carrying `exp`, so an app opened on a plane still knows its four
  /// months are up. Anything unparseable counts as expired - a token we cannot read we cannot send.
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
      // a minute of slack, so a clock a little ahead of the server's does not sign someone out on the
      // very last minute of a valid token
      return DateTime.now().toUtc().isAfter(expiresAt.subtract(const Duration(minutes: 1)));
    } catch (_) {
      return true;
    }
  }

  /// Asks the server who we are now. Throws [SessionExpiredException] when the server says the session
  /// is dead and something else when the *network* is: **those two have to stay distinguishable**,
  /// since signing a user out because their train went into a tunnel is a bug, not caution.
  Future<MeResult> fetchMe() async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw const SessionExpiredException();

    final response = await appHttpClient
        .get(_meUri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 401) {
      // silent: nobody asked for this check, so a dialog would interrupt a user who is only opening
      // the app. they find out on the profile tab, or at the next thing that needs an account.
      onSessionInvalidated?.call(silent: true);
      throw const SessionExpiredException();
    }
    if (response.statusCode != 200) {
      // 5xx, 429, anything else - the server is having a moment, but it never said this token is bad
      throw Exception('Could not verify the session (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MeResult(
      name: body['name'] as String? ?? '',
      phone: body['phone'] as String? ?? '',
      role: body['role'] as String? ?? 'customer',
    );
  }
  /// `PATCH /api/me` - the name, and the one role change the server allows.
  ///
  /// **Both arguments are nullable and a null is not sent**, which is the whole reason this is a PATCH:
  /// the server tells an omitted field from one set to empty, so saving a role cannot blank the name.
  /// The session cache is rewritten before this returns, so storage never disagrees with the controller.
  Future<MeResult> updateProfile({String? name, String? role}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw const SessionExpiredException();

    final response = await appHttpClient
        .patch(
          _meUri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          // the null-aware `?` drops the key entirely rather than sending a null - which is the
          // whole contract of this PATCH: an omitted field is left alone, a null would be a value
          body: jsonEncode({'name': ?name, 'role': ?role}),
        )
        .timeout(const Duration(seconds: 15));

    final me = await _readMeAnswer(response, token);
    return me;
  }

  /// `POST /api/me/phone/request-code` - send a code to the number this account wants to move onto.
  ///
  /// **Not retried, for the reason [requestCode] is not**: every attempt is a paid message.
  Future<CodeRequestResult> requestPhoneChangeCode(String phone) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw const SessionExpiredException();

    final response = await appHttpClient
        .post(
          Uri.parse('${ApiConfig.serverRoot}/api/me/phone/request-code'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'phone': phone}),
        )
        .timeout(const Duration(seconds: 20));

    final body = _decodeBody(response);
    if (response.statusCode != 200) throw AuthApiException.from(response, body);

    return CodeRequestResult(
      phone: body['phone'] as String? ?? phone,
      expiresIn: body['expires_in'] as int? ?? 300,
      resendAfter: body['resend_after'] as int? ?? 60,
    );
  }

  /// `POST /api/me/phone/verify` - the code was right, so the account is now on that number.
  ///
  /// **The token is not replaced and does not need to be.** Its phone claim authorizes nothing -
  /// the server reads the user id off it and nothing else - so the session opened under the old
  /// number keeps working.
  Future<MeResult> verifyPhoneChange({required String phone, required String code}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw const SessionExpiredException();

    final response = await appHttpClient
        .post(
          Uri.parse('${ApiConfig.serverRoot}/api/me/phone/verify'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'phone': phone, 'code': code}),
        )
        .timeout(const Duration(seconds: 15));

    return _readMeAnswer(response, token);
  }

  /// The shared tail of the two authenticated writes: refusals carry a code the screen localizes, a
  /// 401 ends the session, and a success is the account's new state - cached on the way past.
  Future<MeResult> _readMeAnswer(http.Response response, String token) async {
    if (response.statusCode == 401) {
      // not silent: this answers something the user just did, so they get told why they are out
      onSessionInvalidated?.call(silent: false);
      throw const SessionExpiredException();
    }

    final body = _decodeBody(response);
    if (response.statusCode != 200) throw AuthApiException.from(response, body);

    final me = MeResult(
      name: body['name'] as String? ?? '',
      phone: body['phone'] as String? ?? '',
      role: body['role'] as String? ?? 'customer',
    );

    await saveSession(token: token, role: me.role, name: me.name, phone: me.phone);
    return me;
  }

  /// Destroys the account on the server: `DELETE /api/me`.
  ///
  /// **This does not touch local storage** - wiping the phone is [logout]'s job, and if the server
  /// never answered the account may still exist. A 401 counts as success: the row is already gone,
  /// most likely deleted from another phone.
  Future<void> deleteAccount() async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw const SessionExpiredException();

    final response = await appHttpClient
        .delete(_meUri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200 || response.statusCode == 401) return;

    throw Exception('Could not delete the account (${response.statusCode})');
  }


  // -----------------------------------------------------------------------------------------------
  // The phone-code login: POST /api/auth/request-code, then POST /api/auth/verify.
  // -----------------------------------------------------------------------------------------------

  /// `/api/auth/request-code`. Returns what the server echoed back, because the canonical spelling
  /// of the number is the server's to decide - it is what `/verify` must be called with, and what
  /// the "we sent a code to ..." line should show.
  ///
  /// **Not wrapped in [_executeWithRetry], deliberately**: every one of these sends a message that
  /// costs money, and a blind retry on a timeout bills twice and delivers two codes of which only the
  /// second works.
  Future<CodeRequestResult> requestCode({
    required String phone,
    required String name,
    required String role,
  }) async {
    final response = await appHttpClient
        .post(
          Uri.parse('${ApiConfig.serverRoot}/api/auth/request-code'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone, 'name': name, 'role': role}),
        )
        .timeout(const Duration(seconds: 20));

    final body = _decodeBody(response);

    if (response.statusCode != 200) throw AuthApiException.from(response, body);

    return CodeRequestResult(
      phone: body['phone'] as String? ?? phone,
      expiresIn: body['expires_in'] as int? ?? 300,
      resendAfter: body['resend_after'] as int? ?? 60,
    );
  }

  /// `/api/auth/verify`. On success the session is already saved before this returns, so a caller
  /// that forgets to persist it cannot leave a logged-in user looking like a guest.
  Future<MeResult> verifyCode({required String phone, required String code}) async {
    final response = await appHttpClient
        .post(
          Uri.parse('${ApiConfig.serverRoot}/api/auth/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone, 'code': code}),
        )
        .timeout(const Duration(seconds: 15));

    final body = _decodeBody(response);

    if (response.statusCode != 200) throw AuthApiException.from(response, body);

    final token = body['token'] as String?;
    final user = body['user'];
    if (token == null || token.isEmpty || user is! Map<String, dynamic>) {
      // a 200 whose body we cannot read is a server we do not understand, not a login
      throw const AuthApiException('server_error');
    }

    final me = MeResult(
      name: user['name'] as String? ?? '',
      phone: user['phone'] as String? ?? phone,
      role: user['role'] as String? ?? 'customer',
    );

    await saveSession(token: token, role: me.role, name: me.name, phone: me.phone);
    return me;
  }

  /// A body that is not JSON is a proxy's error page rather than our API - ngrok answers an offline
  /// tunnel with HTML and a 404. An empty map lets the status code decide the message.
  static Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<String?> getRole() async => await _storage.read(key: _roleKey);
  Future<String?> getName() async => await _storage.read(key: _nameKey);
  Future<String?> getPhone() async => await _storage.read(key: _phoneKey);

  Future<void> logout() async {
    await _storage.delete(key: _jwtKey);
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _nameKey);
    await _storage.delete(key: _phoneKey);
  }
}
