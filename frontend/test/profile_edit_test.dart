// The profile editor at the three rules that are not visible from the outside:
//
//   * **a role goes one way**: going back would leave a shop owner holding shops they are no longer
//     authorized to edit, a state no screen can get them out of. The server refuses it too
//     (`role_locked`), so what is tested is that the app explains the rule rather than offering a
//     control the server will reject.
//   * **the number is not a field.** It is the account's identity, and moving it costs a paid sms
//     and a code typed back. A «Сохранить» that sometimes sends a message is a button nobody can
//     predict, so the change lives behind its own step.
//   * **nothing auto-submits.** The X abandons whatever step is open; «Назад» walks one step.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/profile/presentation/screens/profile_edit_screen.dart';
import 'package:frontend/features/profile/data/account_role.dart';

final _strings = AppLocalizations(AppLanguage.ru);

/// Hydrates the real [AuthController] out of a faked secure storage - the only public way into a
/// signed-in state, since the profile state deliberately has no setter.
Future<void> _signIn({required String role}) async {
  String chunk(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;

  final store = {
    'domix_jwt_token': '${chunk({'alg': 'HS256'})}.${chunk({'exp': exp})}.signature',
    'domix_user_role': role,
    'domix_user_name': 'Азиз Рихсиев',
    'domix_user_phone': '998901234567',
  };

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => switch (call.method) {
      'read' => store[(call.arguments as Map)['key']],
      'readAll' => store,
      _ => null,
    },
  );

  // AuthController is a process-wide singleton, so a state left by one test would otherwise leak
  // into the next and make these pass or fail on declaration order
  await AuthController().logout();
  await AuthController().checkExistingLogin();
}

/// Rendered at a real phone's width rather than the 800px test default, so a row that only fits on
/// a tablet fails here instead of on a demo device.
Future<void> _pumpEditor(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider.value(value: AuthController()),
      ],
      // pushed over a page, the way the profile opens it - so the X has somewhere to pop back to
      // and this test can see that it did
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => ProfileEditScreen.open(context),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a customer is offered every role, and told the choice is final', (tester) async {
    await _signIn(role: 'customer');
    await _pumpEditor(tester);

    for (final role in AccountRole.values) {
      expect(find.text(role.label(_strings)), findsOneWidget,
          reason: '${role.name} is missing from the picker');
    }
    expect(find.text(_strings.roleChangeWarning), findsOneWidget);
    expect(find.text(_strings.roleLockedNote), findsNothing);
  });

  testWidgets('a shop owner gets no way back to any other role', (tester) async {
    await _signIn(role: 'shop_owner');
    await _pumpEditor(tester);

    expect(find.text(_strings.roleLockedNote), findsOneWidget);
    // the picker is gone entirely, not merely disabled: the role they cannot have must not be on
    // screen at all
    expect(find.text(_strings.roleCustomer), findsNothing);
  });

  testWidgets('the number is behind its own step, not a field on the form', (tester) async {
    await _signIn(role: 'customer');
    await _pumpEditor(tester);

    // the form commits the name and the role, and says so - nothing here sends a message
    expect(find.text(_strings.saveChangesButton), findsOneWidget);
    expect(find.text(_strings.sendCodeButton), findsNothing);
    // the number is shown, grouped, as a row that leads somewhere
    expect(find.text('+998 90 123 45 67'), findsOneWidget);

    await tester.tap(find.text('+998 90 123 45 67'));
    await tester.pumpAndSettle();

    // now, and only now, is there a button that spends money
    expect(find.text(_strings.newPhoneLabel), findsOneWidget);
    expect(find.text(_strings.sendCodeButton), findsOneWidget);
    expect(find.text(_strings.phoneChangeExplainer), findsOneWidget);
  });

  testWidgets('«Назад» walks one step back, the X abandons the screen', (tester) async {
    await _signIn(role: 'customer');
    await _pumpEditor(tester);

    await tester.tap(find.text('+998 90 123 45 67'));
    await tester.pumpAndSettle();
    expect(find.text(_strings.newPhoneLabel), findsOneWidget);

    await tester.tap(find.text(_strings.stepBackButton));
    await tester.pumpAndSettle();
    // back on the form, with the screen still open
    expect(find.text(_strings.saveChangesButton), findsOneWidget);
    expect(find.text(_strings.newPhoneLabel), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditScreen), findsNothing);
  });
}
