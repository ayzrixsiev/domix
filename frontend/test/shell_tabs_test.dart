import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import 'package:frontend/features/app_shell/presentation/screens/app_shell_screen.dart';
import 'package:frontend/features/app_shell/presentation/widgets/floating_bottom_nav_bar.dart';
import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/location/presentation/controllers/city_controller.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/data/stores_repository.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';
import 'package:frontend/features/waybills/presentation/controllers/waybills_controller.dart';
import 'package:frontend/features/waybills/presentation/screens/waybills_screen.dart';

final _strings = AppLocalizations(AppLanguage.ru);

class _EmptyStoresRepository extends StoresRepository {
  @override
  Future<List<Shop>> fetchStores() async => const [];
}

// the only public way into a signed-in state: the real controller, hydrated out of a faked secure store
Future<void> _signInAs(String? role) async {
  String chunk(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
      1000;

  final store = role == null
      ? <String, String>{}
      : {
          'domix_jwt_token':
              '${chunk({'alg': 'HS256'})}.${chunk({'exp': exp})}.signature',
          'domix_user_role': role,
          'domix_user_name': 'Азиз Рихсиев',
          'domix_user_phone': '998900000000',
        };

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => switch (call.method) {
          'read' => store[(call.arguments as Map)['key']],
          'readAll' => store,
          _ => null,
        },
      );

  // a process-wide singleton: a state left by one test would decide the next
  await AuthController().logout();
  await AuthController().checkExistingLogin();
}

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => CityController()),
        ChangeNotifierProvider(create: (_) => HomeController()),
        ChangeNotifierProvider.value(value: AuthController()),
        ChangeNotifierProvider(
          create: (_) => StoresController(repository: _EmptyStoresRepository()),
        ),
        ChangeNotifierProvider(create: (_) => FavoritesController()),
        ChangeNotifierProvider(create: (_) => ProductsController()),
        ChangeNotifierProvider(create: (_) => WaybillsController()),
      ],
      child: const MaterialApp(home: AppShellScreen()),
    ),
  );
  await tester.pump();
}

Finder _navLabel(String label) => find.descendant(
  of: find.byType(FloatingBottomNavBar),
  matching: find.text(label),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('everybody has the cart on the bar', (tester) async {
    for (final role in ['customer', 'shop_owner', 'admin', null]) {
      await _signInAs(role);
      await _pumpShell(tester);
      expect(_navLabel(_strings.cartTab), findsOneWidget, reason: 'as $role');
    }
  });

  testWidgets('a shop owner\'s cart and profile land where they say', (
    tester,
  ) async {
    await _signInAs('shop_owner');
    await _pumpShell(tester);

    await tester.tap(_navLabel(_strings.profileTab));
    await tester.pump();
    expect(find.text(_strings.manageShops), findsOneWidget);

    await tester.tap(_navLabel(_strings.cartTab));
    await tester.pump();
    final page = find.byType(WaybillsScreen, skipOffstage: false);
    expect(tester.widget<WaybillsScreen>(page).isActive, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  // **the same trap the map guards against** (map_fullscreen_test): Корзина hides the nav bar too, so
  // a failure to bring it back strands the user on a tab with no way out, and nothing throws.
  testWidgets('the cart hides the nav bar, and its back disc brings it back', (
    tester,
  ) async {
    await _signInAs('customer');
    await _pumpShell(tester);
    expect(find.byType(FloatingBottomNavBar), findsOneWidget);

    await tester.tap(_navLabel(_strings.cartTab));
    await tester.pumpAndSettle();
    expect(
      find.byType(FloatingBottomNavBar),
      findsNothing,
      reason: 'the tab runs edge to edge, with its own button over the list',
    );

    await tester.tap(
      find.descendant(
        of: find.byType(WaybillsScreen),
        matching: find.byType(CircleBackButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FloatingBottomNavBar), findsOneWidget);
  });
}
