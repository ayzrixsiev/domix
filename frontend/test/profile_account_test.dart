// The profile screen at the two things a session actually decides: **which account this is** and
// **what its buttons do**.
//
// Both were broken at once, and neither looked like a crash from the outside:
//
//   * an `admin` signing in got the *customer* profile. the server had them right - it authorizes
//     admin exactly like shop_owner - but the app compared the role against the single literal
//     `shop_owner`, so an administrator with ten shops on the map was shown a screen with no way
//     into any of them. it reads as "registering as a shop owner did not work".
//   * «Удалить аккаунт» did nothing at all. the handler's first line read the localized copy through
//     a *listening* `Provider.of`, which asserts outside of a build - and an assertion thrown inside
//     a gesture callback surfaces in the console and nowhere else. no dialog, no error, a dead row.
//
// So the two tests here are: a role that is not `shop_owner` still reaching the owner's screen, and
// a tap on the most destructive button in the app reaching its confirmation.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/profile/presentation/screens/profile_screen.dart';

final _strings = AppLocalizations(AppLanguage.ru);

/// Hydrates the real [AuthController] out of a faked secure storage - the only public way into a
/// signed-in state, since the profile state deliberately has no setter.
Future<void> _signIn({required String role}) async {
  // a token whose `exp` is in the future. AuthController reads that claim itself, offline, so a
  // hand-built one is exactly as good as a real one here.
  String chunk(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;

  final store = {
    'domix_jwt_token': '${chunk({'alg': 'HS256'})}.${chunk({'exp': exp})}.signature',
    'domix_user_role': role,
    'domix_user_name': 'Азиз Рихсиев',
    'domix_user_phone': '+998900000000',
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

/// An empty secure store: nobody is signed in. Same shape as [_signIn] so the singleton is reset
/// the same way - a state left behind by another test is what would otherwise decide this one.
Future<void> _signOut() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => call.method == 'readAll' ? <String, String>{} : null,
  );

  await AuthController().logout();
  await AuthController().checkExistingLogin();
}

/// Rendered at a real phone's width rather than the 800px test default, so a row that only fits on a
/// tablet fails here instead of on a demo device.
Future<void> _pumpProfile(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider.value(value: AuthController()),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('every role the server may authorize for shops maps to the owner profile', () {
    // the pair authz.go lets through, and nothing else
    expect(AuthController.canManageShops('shop_owner'), isTrue);
    expect(AuthController.canManageShops('admin'), isTrue);
    expect(AuthController.canManageShops('customer'), isFalse);
    // an unknown role is not a shop owner: a value this version does not recognise must not be
    // handed the destructive half of the app on a guess
    expect(AuthController.canManageShops('worker'), isFalse);
  });

  testWidgets('an admin gets the shop-owner profile, not the customer one', (tester) async {
    await _signIn(role: 'admin');
    await _pumpProfile(tester);

    expect(AuthController().profileState.isVendor, isTrue);
    // the entry point into the shops. its absence was the whole reported symptom.
    expect(find.text(_strings.manageShops), findsOneWidget);
    expect(find.text(_strings.vendorBadge), findsOneWidget);
  });

  testWidgets('a customer keeps the customer profile', (tester) async {
    await _signIn(role: 'customer');
    await _pumpProfile(tester);

    expect(find.text(_strings.manageShops), findsNothing);
    // ...but still gets the deletion path, which Google Play requires of every account
    expect(find.text(_strings.deleteAccount), findsOneWidget);
  });

  testWidgets('a guest gets the onboarding flow, not a profile', (tester) async {
    await _signOut();
    await _pumpProfile(tester);

    expect(AuthController().profileState.isGuest, isTrue);

    // step one of OnboardingFlow - the language choice, and the counter saying how many steps
    // there are. the step carries no title of its own: two language tiles do not need a sentence
    // above them saying they are language tiles.
    expect(find.text(_strings.onboardingTitle), findsOneWidget);
    expect(find.text(AppLanguage.ru.displayName), findsOneWidget);
    expect(find.text(AppLanguage.uz.displayName), findsOneWidget);
    expect(find.text(_strings.stepCounter(1, 5)), findsOneWidget);

    // the three rows a guest used to be handed. favourites and language mean nothing without an
    // account, and support is its own tab in the nav bar - so all three were a menu that either did
    // nothing or sent the visitor back to this same screen to log in first.
    expect(find.text(_strings.favorites), findsNothing);
    expect(find.text(_strings.support), findsNothing);

    // and none of the signed-in screen leaks through
    expect(find.text(_strings.logout), findsNothing);
    expect(find.text(_strings.deleteAccount), findsNothing);
  });

  testWidgets('«Поддержка» is gone from the signed-in menu too, it lives in the nav bar', (tester) async {
    await _signIn(role: 'customer');
    await _pumpProfile(tester);

    expect(find.text(_strings.support), findsNothing);
    // the rows either side of where it sat are still there, so this is a removal and not a
    // collapsed menu
    expect(find.text(_strings.favorites), findsOneWidget);
    expect(find.textContaining(_strings.languageSettings), findsOneWidget);
  });

  testWidgets('tapping «Удалить аккаунт» opens the confirmation', (tester) async {
    await _signIn(role: 'shop_owner');
    await _pumpProfile(tester);

    await tester.tap(find.text(_strings.deleteAccount));
    await tester.pumpAndSettle();

    // stops at the dialog on purpose - confirming would go to the network. the bug was never in the
    // request, it was in getting this far.
    expect(find.text(_strings.deleteAccountConfirmTitle), findsOneWidget);
    expect(find.text(_strings.deleteAccountConfirmBody), findsOneWidget);
  });
}
