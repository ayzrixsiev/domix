// A launch that cannot read secure storage must never sign anybody out. Closed testers were landing on
// the guest screen with the server never having refused their token: the store had failed, not the
// session.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';

class _OfflineHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future.error(const SocketException('Network is unreachable'));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _Offline();

  String chunk(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
      1000;

  late Map<String, String> store;
  late int failingReads;
  late List<String> destructive;
  late Set<String?> resetOnError;

  setUp(() {
    store = {
      'domix_jwt_token':
          '${chunk({'alg': 'HS256'})}.${chunk({'exp': exp})}.signature',
      'domix_user_role': 'customer',
      'domix_user_name': 'Азиз Рихсиев',
      'domix_user_phone': '998900000000',
    };
    failingReads = 0;
    destructive = [];
    resetOnError = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = call.arguments as Map;
            resetOnError.add((args['options'] as Map?)?['resetOnError']);
            final key = args['key'];
            switch (call.method) {
              case 'read':
                if (failingReads > 0) {
                  failingReads--;
                  throw PlatformException(code: 'Exception encountered');
                }
                return store[key];
              case 'delete' || 'deleteAll':
                destructive.add(call.method);
                return null;
              case 'write':
                store[key] = args['value'];
                return null;
            }
            return null;
          },
        );
  });

  test('a store that fails for a moment at launch is read again', () async {
    final controller = AuthController();
    await controller.logout();
    destructive.clear();

    failingReads = 2;
    await controller.checkExistingLogin();

    expect(controller.profileState.isGuest, isFalse);
    expect(destructive, isEmpty);
    expect(resetOnError, {'false'}, reason: 'the plugin would wipe the store');
  });

  test(
    'an unreadable store keeps its token and is tried again on resume',
    () async {
      final controller = AuthController();
      await controller.logout();
      destructive.clear();

      failingReads = 1 << 20;
      await controller.checkExistingLogin();
      expect(controller.profileState.isGuest, isTrue);
      expect(
        destructive,
        isEmpty,
        reason: 'a read failure deleted the session',
      );

      failingReads = 0;
      await controller.verifySession();
      expect(controller.profileState.isGuest, isFalse);
      expect(store['domix_jwt_token'], isNotNull);
    },
  );
}
