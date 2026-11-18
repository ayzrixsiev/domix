import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/storage/secure_storage.dart';

/// What `/api/auth/init` answered: the session to poll and the t.me link that opens our bot on it.
class TelegramHandshake {
  const TelegramHandshake({
    required this.session,
    required this.link,
    required this.expiresIn,
  });

  /// **The only secret in the flow** - whoever holds it collects the token - so it is never logged.
  final String session;
  final Uri link;

  /// Seconds the bot will wait for the number; the poll stops when they are up.
  final int expiresIn;
}

/// One answer of `/api/auth/status`. [me] is set only on `success`, and by then the session is
/// already in secure storage.
class HandshakePoll {
  const HandshakePoll(this.status, {this.me});

  static const pending = 'pending';
  static const success = 'success';

  final String status;
  final MeResult? me;

  bool get isPending => status == pending;
}

/// What `/api/auth/request-code` answered.
class CodeRequestResult {
  const CodeRequestResult({required this.phone, required this.resendAfter});

  /// `998XXXXXXXXX` - the server's spelling, which is what `/verify` has to be called with.
  final String phone;

  /// Seconds before another code may be asked for.
  final int resendAfter;
}

/// A refusal from the auth endpoints, carrying **the server's machine-readable code** rather than
/// its sentence: the server answers in one language and the app draws the reader's, so the mapping
/// to written copy belongs in AppLocalizations.authErrorFor.
class AuthApiException implements Exception {
  const AuthApiException(this.code, {this.retryAfter});

  factory AuthApiException.from(Map<String, dynamic> body) {
    final retryAfter = body['retry_after'];
    return AuthApiException(
      body['code'] as String? ?? 'server_error',
      retryAfter: retryAfter is int ? retryAfter : null,
    );
  }

  final String code;

  /// Seconds to wait, on `code_cooldown`: the code already sent is still live.
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

/// The session this phone holds, as read back from secure storage on a cold start.
class StoredSession {
  const StoredSession({required this.token, required this.account});

  final String token;
  final MeResult account;
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

  // the server cannot reach the app, so a 401 on any authenticated call is the only signal that the
  // account behind the token is gone or the token was revoked by a logout elsewhere.
  // not silent: this 401 answers something the user just did, so they get told why they are out.
  static bool handleUnauthorized(http.Response response) {
    if (response.statusCode != 401) return false;
    onSessionInvalidated?.call(silent: false);
    return true;
  }

  static final Uri _meUri = Uri.parse('${ApiConfig.serverRoot}/api/me');

  final _storage = appSecureStorage;

  static const _jwtKey = 'domix_jwt_token';
  static const _roleKey = 'domix_user_role';
  static const _nameKey = 'domix_user_name';
  static const _phoneKey = 'domix_user_phone';

  // hardware-encrypted storage: a stolen phone must not yield a four-month token
  Future<void> _saveSession(String token, MeResult me) async {
    await _storage.write(key: _jwtKey, value: token);
    await saveProfile(me);
  }

  /// The account as the server last described it. The token is left alone: rewriting it on every
  /// refresh only adds writes that can fail.
  Future<void> saveProfile(MeResult me) async {
    await _storage.write(key: _roleKey, value: me.role);
    await _storage.write(key: _nameKey, value: me.name);
    await _storage.write(key: _phoneKey, value: me.phone);
  }

  Future<String?> getToken() async => await _storage.read(key: _jwtKey);

  /// The stored session, or null when there is none. **Throws when storage cannot be read**, which is
  /// not the same answer as null: an unreadable store still holds the token, and treating it as empty
  /// signs the user out for nothing. Retried first, because the Keystore can fail for a moment at launch.
  Future<StoredSession?> readStoredSession() async {
    const backoff = [Duration(milliseconds: 250), Duration(milliseconds: 750)];
    for (var attempt = 0; ; attempt++) {
      try {
        final token = await getToken();
        if (token == null || token.isEmpty) return null;
        return StoredSession(
          token: token,
          account: MeResult(
            role: await getRole() ?? 'customer',
            name: await getName() ?? 'Domix User',
            phone: await getPhone() ?? '',
          ),
        );
      } catch (e) {
        if (attempt == backoff.length) rethrow;
        debugPrint('secure storage read failed, retrying: $e');
        await Future<void>.delayed(backoff[attempt]);
      }
    }
  }

  /// Whether a stored token has already passed its own expiry, read **from the token itself**: a JWT's
  /// middle chunk is plain JSON carrying `exp`, so an app opened on a plane still knows its four
  /// months are up. Anything unparseable counts as expired - a token we cannot read we cannot send.
  static bool isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      // base64url without padding is what JWT uses; normalize() puts the '=' back so decode accepts it
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;

      final exp = payload['exp'];
      if (exp is! int) return true;

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      );
      // a minute of slack, so a clock a little ahead of the server's does not sign someone out on the
      // very last minute of a valid token
      return DateTime.now().toUtc().isAfter(
        expiresAt.subtract(const Duration(minutes: 1)),
      );
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

    final me = await _readMeAnswer(response);
    return me;
  }

  /// The tail of an authenticated write: refusals carry a code the screen localizes, a 401 ends the
  /// session, and a success is the account's new state - cached on the way past.
  Future<MeResult> _readMeAnswer(http.Response response) async {
    if (response.statusCode == 401) {
      // not silent: this answers something the user just did, so they get told why they are out
      onSessionInvalidated?.call(silent: false);
      throw const SessionExpiredException();
    }

    final body = _decodeBody(response);
    if (response.statusCode != 200) throw AuthApiException.from(body);

    final me = MeResult(
      name: body['name'] as String? ?? '',
      phone: body['phone'] as String? ?? '',
      role: body['role'] as String? ?? 'customer',
    );

    await saveProfile(me);
    return me;
  }

  /// Destroys the account on the server: `DELETE /api/me`.
  ///
  /// **This does not touch local storage** - wiping the phone is [clearSession]'s job, and if the server
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
  // Signing in through the bot: POST /api/auth/init, then POST /api/auth/status until it answers.
  // -----------------------------------------------------------------------------------------------

  /// `/api/auth/init`. The name and role ride in the session, because the bot hands back a number
  /// and nothing else.
  Future<TelegramHandshake> startTelegramSignIn({
    required String name,
    required String role,
    required String lang,
  }) async {
    final response = await appHttpClient
        .post(
          Uri.parse('${ApiConfig.serverRoot}/api/auth/init'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': name, 'role': role, 'lang': lang}),
        )
        .timeout(const Duration(seconds: 15));

    final body = _decodeBody(response);
    if (response.statusCode != 200) throw AuthApiException.from(body);

    final session = body['session'] as String?;
    final link = Uri.tryParse(body['link'] as String? ?? '');
    if (session == null || session.isEmpty || link == null) {
      throw const AuthApiException('server_error');
    }
    return TelegramHandshake(
      session: session,
      link: link,
      expiresIn: body['expires_in'] as int? ?? 600,
    );
  }

  /// `/api/auth/status`. **The server hands a finished login out once**, so a `success` is saved
  /// before this returns: a caller that dropped it would leave a signed-in account looking like a
  /// guest with no second chance to read the token.
  Future<HandshakePoll> pollTelegramSignIn(String session) async {
    final response = await appHttpClient
        .post(
          Uri.parse('${ApiConfig.serverRoot}/api/auth/status'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'session': session}),
        )
        .timeout(const Duration(seconds: 10));

    final body = _decodeBody(response);
    if (response.statusCode != 200) throw AuthApiException.from(body);

    final status = body['status'] as String? ?? 'server_error';
    if (status != HandshakePoll.success) return HandshakePoll(status);

    return HandshakePoll(status, me: await _saveSignIn(body));
  }

  // -----------------------------------------------------------------------------------------------
  // Signing in with a code: POST /api/auth/request-code, then POST /api/auth/verify. Until Gateway
  // is paid for the server answers `sms_unavailable` to every number but the Play review account.
  // -----------------------------------------------------------------------------------------------

  /// `/api/auth/request-code`. The name and role ride with the number, as they ride in a telegram
  /// session, because `/verify` carries the code alone.
  ///
  /// **Never retried on a timeout**: every send is a paid message, and a blind retry bills twice and
  /// delivers two codes of which only the second works.
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
    if (response.statusCode != 200) throw AuthApiException.from(body);

    return CodeRequestResult(
      phone: body['phone'] as String? ?? phone,
      resendAfter: body['resend_after'] as int? ?? 60,
    );
  }

  /// `/api/auth/verify`. Saved before this returns, like a telegram `success`.
  Future<MeResult> verifyCode({
    required String phone,
    required String code,
  }) async {
    final response = await appHttpClient
        .post(
          Uri.parse('${ApiConfig.serverRoot}/api/auth/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone, 'code': code}),
        )
        .timeout(const Duration(seconds: 15));

    final body = _decodeBody(response);
    if (response.statusCode != 200) throw AuthApiException.from(body);

    return _saveSignIn(body);
  }

  /// The `{token, user}` both sign-ins end in, saved. **One reader for both**, so a code and the bot
  /// cannot land in two different notions of signed in.
  Future<MeResult> _saveSignIn(Map<String, dynamic> body) async {
    final token = body['token'] as String?;
    final user = body['user'];
    if (token == null || token.isEmpty || user is! Map<String, dynamic>) {
      // a 200 whose body we cannot read is a server we do not understand, not a session
      throw const AuthApiException('server_error');
    }

    final me = MeResult(
      name: user['name'] as String? ?? '',
      phone: user['phone'] as String? ?? '',
      role: user['role'] as String? ?? 'customer',
    );
    try {
      await _saveSession(token, me);
    } catch (e) {
      // the server hands this token out once, so a store that cannot be written is reset and written
      // again rather than losing the sign-in; whatever it held was unreadable anyway
      debugPrint('secure storage write failed, resetting it: $e');
      await resetBrokenSecureStorage();
      await _saveSession(token, me);
    }
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

  /// `POST /api/me/logout` - ends every session of this account on the server, which is what stops a
  /// copied token. **Never throws, whatever the server or the network does**: the caller signs the
  /// phone out next either way.
  Future<void> revokeSession() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return;

      await appHttpClient
          .post(
            Uri.parse('${ApiConfig.serverRoot}/api/me/logout'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('revokeSession failed: $e');
    }
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _jwtKey);
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _nameKey);
    await _storage.delete(key: _phoneKey);
  }
}
