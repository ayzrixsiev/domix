// «Войти по номеру телефона», against a fake server, at the two answers it exists for.
//
// **Every number but the Play review account is refused `sms_unavailable`** until Gateway is paid
// for, and that refusal has to read as a note pointing at Telegram, never as a red error.
//
// **The review account lands exactly where a telegram sign-in does**: the flow takes itself and the
// onboarding under it off the screen, and the account is the signed-in one. That account is what
// Google's reviewer is given, so this is the path the listing depends on.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/app_form.dart';
import 'package:frontend/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';

final _strings = AppLocalizations(AppLanguage.ru);

/// Answers each request by its path, and remembers what was asked.
class _FakeServer extends HttpOverrides {
  (int, Map<String, dynamic>) Function(String path) answer = (_) =>
      (500, const {});
  final requests = <String, Map<String, dynamic>>{};

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);
}

class _Client implements HttpClient {
  _Client(this.server);

  final _FakeServer server;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(server, url);

  // the setters the shared client's cascade calls, and nothing else is reached
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.server, this.url);

  final _FakeServer server;
  final Uri url;
  final _sent = <int>[];

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_sent.addAll);

  @override
  Future<HttpClientResponse> close() async {
    // the logout at the end carries no body
    server.requests[url.path] = _sent.isEmpty
        ? const {}
        : jsonDecode(utf8.decode(_sent)) as Map<String, dynamic>;
    final (status, body) = server.answer(url.path);
    return _Response(status, utf8.encode(jsonEncode(body)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this._body);

  @override
  final int statusCode;
  final List<int> _body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  int get contentLength => _body.length;
  @override
  HttpHeaders get headers => _Headers();
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _server = _FakeServer();
final _storage = <String, String>{};

/// Opens the onboarding from a launcher, so its own `pop(true)` can be seen, and walks it to the
/// telegram step with a name typed and the owner's role picked.
Future<void> _walkToTelegramStep(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider.value(value: AuthController()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => OnboardingFlow.open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.tap(find.text(_strings.nextButton));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(_strings.policyAcceptLabel),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text(_strings.policyAcceptLabel));
  await tester.tap(find.text(_strings.nextButton));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, 'Азиз');
  await tester.tap(find.text(_strings.roleVendor));
  await tester.tap(find.text(_strings.nextButton));
  await tester.pumpAndSettle();
}

Future<void> _sendNumber(WidgetTester tester, String digits) async {
  await tester.tap(find.text(_strings.phoneSignInButton));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), digits);
  await tester.tap(find.text(_strings.sendCodeButton));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // before anything touches appHttpClient, which builds its HttpClient on first use
  HttpOverrides.global = _server;

  setUp(() {
    _server.requests.clear();
    _storage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = call.arguments as Map;
            final key = args['key'] as String?;
            return switch (call.method) {
              'write' => _storage[key!] = args['value'] as String,
              'read' => _storage[key],
              'readAll' => _storage,
              'delete' => _storage.remove(key),
              _ => null,
            };
          },
        );
  });

  testWidgets('a number sms cannot reach yet is pointed back to telegram', (
    tester,
  ) async {
    _server.answer = (_) => (
      403,
      const {'error': 'sms is not available', 'code': 'sms_unavailable'},
    );

    await _walkToTelegramStep(tester);
    await _sendNumber(tester, '901234567');

    expect(find.text(_strings.smsUnavailable), findsOneWidget);
    expect(
      find.byType(AppErrorLine),
      findsNothing,
      reason: 'the refusal is a note, not a mistake to fix',
    );
    expect(find.text(_strings.sendCodeButton), findsOneWidget);

    // the profile step's answers ride with the number, as they ride in a telegram session
    expect(_server.requests['/api/auth/request-code'], {
      'phone': '998901234567',
      'name': 'Азиз',
      'role': 'shop_owner',
    });

    // «Назад» is one step: the telegram step, with its counter unchanged
    await tester.tap(find.text(_strings.stepBackButton));
    await tester.pumpAndSettle();
    expect(find.text(_strings.telegramSignInButton), findsOneWidget);
    expect(find.text(_strings.stepCounter(4, 4)), findsOneWidget);
  });

  testWidgets('the review account signs in where telegram would land', (
    tester,
  ) async {
    _server.answer = (path) => switch (path) {
      '/api/auth/request-code' => (
        200,
        const {
          'sent': true,
          'phone': '998901110000',
          'expires_in': 300,
          'resend_after': 60,
        },
      ),
      _ => (
        200,
        const {
          'token': 'review-token',
          'user': {
            'id': 7,
            'name': 'Азиз',
            'phone': '998901110000',
            'role': 'shop_owner',
          },
        },
      ),
    };

    await _walkToTelegramStep(tester);
    await _sendNumber(tester, '901110000');
    expect(find.text(_strings.codeSentTo('+998 90 111 00 00')), findsOneWidget);

    // the code screen's back control returns to the number, which is still typed
    await tester.tap(find.text(_strings.changePhoneButton));
    await tester.pumpAndSettle();
    expect(find.text('901110000'), findsOneWidget);
    await tester.tap(find.text(_strings.sendCodeButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '424242');
    await tester.tap(find.text(_strings.verifyCodeButton));
    await tester.pumpAndSettle();

    expect(_server.requests['/api/auth/verify'], {
      'phone': '998901110000',
      'code': '424242',
    });
    expect(
      find.text('open'),
      findsOneWidget,
      reason: 'both routes should be off the screen',
    );
    expect(AuthController().profileState.isVendor, isTrue);
    expect(_storage['domix_jwt_token'], 'review-token');

    // the singleton outlives the test
    await AuthController().logout();
    await tester.pumpAndSettle();
  });
}
