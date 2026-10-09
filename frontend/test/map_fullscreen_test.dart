// The map is the one tab that takes the whole screen: opening it hides the shell's nav bar, and the
// disc left of the search field is what brings both the home screen and the bar back.
//
// It is pinned here because the failure is a trap rather than a glitch. The nav bar going missing is
// obvious; the bar failing to *come back* leaves the user on a full-screen map with no way out of
// it, and that is reachable by any change to the shell's index handling - a guard that returns
// early, a tab index renumbered, the PopScope swallowing a pop it should not. None of it throws.
//
// The whole shell is built rather than MapScreen alone, because the rule being checked belongs to
// neither on its own: the screen only reports "the user pressed the way out", and the shell decides
// what that means.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/app_shell/presentation/screens/app_shell_screen.dart';
import 'package:frontend/features/app_shell/presentation/widgets/floating_bottom_nav_bar.dart';
import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/map/presentation/widgets/map_search_panel.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/data/stores_repository.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';
import 'package:frontend/features/location/presentation/controllers/city_controller.dart';

/// Answers nothing, which is the point: this test is about the shell's chrome, and a shop list would
/// only add a fetch to wait on.
class _EmptyStoresRepository extends StoresRepository {
  @override
  Future<List<Shop>> fetchStores() async => const [];
}

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => CityController()),
        ChangeNotifierProvider(create: (_) => HomeController()),
        ChangeNotifierProvider(create: (_) => AuthController()),
        ChangeNotifierProvider(
          create: (_) => StoresController(repository: _EmptyStoresRepository()),
        ),
        ChangeNotifierProvider(create: (_) => FavoritesController()),
        ChangeNotifierProvider(create: (_) => ProductsController()),
      ],
      child: const MaterialApp(home: AppShellScreen()),
    ),
  );
  await tester.pump();
}

Finder get _navBar => find.byType(FloatingBottomNavBar);

/// The disc left of the search field. Found through the panel's `leading` rather than by glyph: the
/// icon is a detail, "there is a way out of the map" is the rule.
Finder get _exitButton =>
    find.descendant(of: find.byType(MapSearchPanel), matching: find.byType(MapBarButton)).first;

Future<void> _openMap(WidgetTester tester) async {
  await tester.tap(find.text('Карта'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('the map hides the nav bar, and its own button brings it back', (tester) async {
    await _pumpShell(tester);
    expect(_navBar, findsOneWidget, reason: 'the home screen keeps the bar');

    await _openMap(tester);
    expect(_navBar, findsNothing, reason: 'the map runs edge to edge, with no bar over its lower third');

    await tester.tap(_exitButton);
    await tester.pump();
    await tester.pump();

    expect(_navBar, findsOneWidget);
    // and it lands on the home screen rather than wherever the user came from: the map is reached
    // from every tab, so "back" has to mean one definite place
    expect(find.text('Карта'), findsOneWidget);
  });
}
