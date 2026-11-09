// The «Выйти» button at the one guarantee that matters: **the phone is signed out whatever the server
// answers**. A logout that waits on the network would leave someone signed in on a phone they handed
// back, and nothing on screen would say so.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';

/// No network at all: every connection fails the way it does in a lift.
class _OfflineHttpClient implements HttpClient {
  final List<Uri> attempted = [];

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    attempted.add(url);
    return Future.error(const SocketException('Network is unreachable'));
  }

  // the setters the shared client's cascade calls, and nothing else is reached
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Offline extends HttpOverrides {
  _Offline(this.client);

  final _OfflineHttpClient client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logging out offline still signs this phone out', () async {
    // set before anything touches appHttpClient, which builds its HttpClient on first use
    final client = _OfflineHttpClient();
    HttpOverrides.global = _Offline(client);

    String chunk(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final exp =
        DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
        1000;
    final store = <String, String>{
      'domix_jwt_token':
          '${chunk({'alg': 'HS256'})}.${chunk({'exp': exp})}.signature',
      'domix_user_role': 'customer',
      'domix_user_name': 'Азиз Рихсиев',
      'domix_user_phone': '998900000000',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final key = (call.arguments as Map)['key'];
            return switch (call.method) {
              'read' => store[key],
              'readAll' => store,
              'delete' => store.remove(key),
              _ => null,
            };
          },
        );

    final controller = AuthController();
    await controller.checkExistingLogin();
    expect(controller.profileState.isGuest, isFalse);

    await controller.logout();

    expect(
      client.attempted.map((u) => u.path),
      contains('/api/me/logout'),
      reason: 'the server was never asked to end the session',
    );
    expect(store, isEmpty);
    expect(controller.profileState.isGuest, isTrue);
  });
}
