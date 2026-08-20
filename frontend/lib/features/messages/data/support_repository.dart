import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:frontend/core/constants/api_config.dart';
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

  /// The conversation, oldest first - the order the server returns and the order it is drawn in.
  Future<List<SupportMessage>> fetchMessages() async {
    final token = await _requireToken();

    final response = await http
        .get(_messagesUri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 10));

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
