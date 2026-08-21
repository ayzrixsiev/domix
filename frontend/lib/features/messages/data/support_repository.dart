import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_get.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'support_message.dart';

/// Talks to the two support endpoints (backend/internal/endpoints/support.go).
///
///   GET  /api/support/messages  - the caller's whole conversation
///   POST /api/support/messages  - the caller writes in
///
/// **Neither call carries a thread id, and that is the whole authorization model.** The thread is
/// whoever the token says is calling, so there is no id here that could be pointed at somebody
/// else's messages - and nothing for this file to get wrong.
class SupportRepository {
  SupportRepository({AuthService? authService}) : _authService = authService ?? AuthService();

  final AuthService _authService;

  static Uri get _messagesUri => Uri.parse('${ApiConfig.serverRoot}/api/support/messages');

  /// **The read watermark**, kept on the phone.
  ///
  /// There is no server-side "the user has read this" - the admin panel has one
  /// (`support_thread_reads`), but that is a fact about an *admin*, and a second table for the other
  /// direction would be a write on every chat open to answer a question one device can answer for
  /// itself. So: the newest message id the reader has had open. Unread is `newest.id > watermark`,
  /// which stays derived - ids only go up, so a message arriving a second later is unread by
  /// arithmetic rather than because something remembered to set a bit.
  ///
  /// Secure storage rather than `shared_preferences` because it is already a dependency and this is
  /// one integer; it is not a secret, and nothing here depends on it being encrypted.
  static const _lastReadKey = 'domix_support_last_read';

  final _storage = const FlutterSecureStorage();

  /// 0 when nothing has ever been read, which makes every message unread - correct for a fresh
  /// install, and the same answer a failed read gives.
  Future<int> readWatermark() async {
    try {
      return int.tryParse(await _storage.read(key: _lastReadKey) ?? '') ?? 0;
    } catch (e) {
      debugPrint('SupportRepository: cannot read the support watermark ($e)');
      return 0;
    }
  }

  Future<void> writeWatermark(int messageId) async {
    try {
      await _storage.write(key: _lastReadKey, value: messageId.toString());
    } catch (e) {
      debugPrint('SupportRepository: cannot store the support watermark ($e)');
    }
  }

  /// Goes with the thread on logout. A watermark left behind belongs to somebody else's
  /// conversation, so the next account on this phone would open a thread that is already "read".
  Future<void> clearWatermark() async {
    try {
      await _storage.delete(key: _lastReadKey);
    } catch (e) {
      debugPrint('SupportRepository: cannot clear the support watermark ($e)');
    }
  }

  /// The conversation, oldest first - the order the server returns and the order it is drawn in.
  Future<List<SupportMessage>> fetchMessages() async {
    final token = await _requireToken();

    final response = await apiGet(_messagesUri, headers: {'Authorization': 'Bearer $token'});

    if (response.statusCode != 200) {
      throw _exceptionFrom(response);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final messages = body['messages'] as List<dynamic>? ?? const [];
    return messages
        .map((json) => SupportMessage.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Sends one message and returns it as the server stored it.
  ///
  /// Returning the stored message rather than a bool is what lets the chat append a bubble with the
  /// server's own id and timestamp instead of inventing a local one that a later refresh would
  /// replace with a slightly different copy.
  Future<SupportMessage> sendMessage(String body) async {
    final token = await _requireToken();

    final response = await http
        .post(
          _messagesUri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'body': body}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 201) {
      throw _exceptionFrom(response);
    }

    return SupportMessage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<String> _requireToken() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      throw const SupportException(code: 'unauthorized', message: 'Not logged in');
    }
    return token;
  }

  SupportException _exceptionFrom(http.Response response) {
    // a 401 means the stored token will never work again - deleted account, or an expiry the app
    // did not notice. signing out here rather than in the controller keeps the rule in the one
    // place every authenticated request in this file already passes through.
    AuthService.handleUnauthorized(response);

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return SupportException(
        code: body['code'] as String? ?? 'server_error',
        message: body['error'] as String? ?? 'Request failed (${response.statusCode})',
      );
    } catch (_) {
      return SupportException(
        code: 'server_error',
        message: 'Request failed (${response.statusCode})',
      );
    }
  }
}
