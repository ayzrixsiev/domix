import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:yandex_maps_mapkit_lite/init.dart' as mapkit_init;
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/map_config.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/app_shell/presentation/screens/app_shell_screen.dart';
import 'package:frontend/features/profile/presentation/widgets/session_expiry_guard.dart';
import 'features/home/presentation/controllers/home_controller.dart';
import 'features/location/presentation/controllers/city_controller.dart';
import 'features/favorites/presentation/controllers/favorites_controller.dart';
import 'features/profile/presentation/controllers/auth_controller.dart';
import 'features/stores/presentation/controllers/stores_controller.dart';
import 'features/products/presentation/controllers/products_controller.dart';
import 'features/waybills/presentation/controllers/waybills_controller.dart';

void main() async {
  // wake up flutter engine drivers to read hardware encrypted storage before drawing ui
  WidgetsFlutterBinding.ensureInitialized();

  // portrait only: every screen here is a vertical feed, a map or a form built on fixed card heights
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // MapKit initializes once, before any map widget is built, and it is a native call. guarded by
  // MapConfig so a desktop `flutter run` or a checkout without a key still boots - the map screens
  // show an explanatory panel instead of crashing.
  if (MapConfig.isAvailable) {
    await mapkit_init.initMapkit(apiKey: MapConfig.apiKey);
  }

  final authController = AuthController();
  // awaited: secure storage plus the token's own expiry, both offline, so the first frame is already
  // correct rather than flickering from profile to guest
  await authController.checkExistingLogin();
  // *not* awaited: a network round trip. the app opens on the cached session and drops to guest a
  // moment later if the server disagrees.
  unawaited(authController.verifySession());
  final storesController = StoresController();
  final favoritesController = FavoritesController();
  final productsController = ProductsController();
  final waybillsController = WaybillsController();
  // built here rather than lazily so a sign-in can reach it; nothing is fetched until the home screen asks
  final homeController = HomeController();
  // what the end of a session has to reach. callbacks rather than imports in either direction, and
  // main() is the one place allowed to know about both: the shops, because deleting an account
  // cascades them away server-side under a map holding a stale snapshot; and the saved products,
  // which are somebody's and must not be handed to whoever signs in on this phone next.
  // what a new session has to fetch: the saved products, which the hearts on every grid are painted
  // from. unawaited - nothing on screen waits for it, and the heart fills when it lands.
  authController.onSessionStarted = () => unawaited(favoritesController.load());

  // a shop owner is answered without other shops' prices and index, so everything read under the last
  // account is read again: home and the map now, a shop's catalogue on its next open
  authController.onViewerChanged = () {
    homeController.handleViewerChanged();
    storesController.handleViewerChanged();
    productsController.markAllStale();
  };

  authController.onSessionEnded = (accountDeleted) {
    storesController.handleSessionEnded(accountDeleted);
    favoritesController.handleSessionEnded();
    waybillsController.handleSessionEnded();
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        // built lazily - nothing here needs loading before first paint
        ChangeNotifierProvider(create: (_) => CityController()),
        ChangeNotifierProvider.value(value: homeController),
        ChangeNotifierProvider.value(value: authController), // make all
        ChangeNotifierProvider.value(value: storesController),
        ChangeNotifierProvider.value(
          value: favoritesController,
        ), // UI components
        ChangeNotifierProvider.value(
          value: productsController,
        ), // to listen to these controllers using notifyListener()
        ChangeNotifierProvider.value(value: waybillsController),
      ],
      child: const DomixApp(),
    ),
  );
}

class DomixApp extends StatelessWidget {
  const DomixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Domix',
      debugShowCheckedModeBanner: false,

      // the app draws its own type sizes and ignores the phone's font-size setting: the layout is built on
      // fixed card heights, so at Android's 1.3 scale the VIP card already overflows. the honest fix is
      // cards that grow with their content - if that ever lands, delete this wrapper rather than raising a
      // fixed number.
      //
      builder: (context, child) => MediaQuery.withNoTextScaling(child: child!),
      locale: Provider.of<LanguageProvider>(context).locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru'), Locale('uz')],
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        // the token, not a copy of its value - a literal here would silently keep the old shade
        scaffoldBackgroundColor: AppColors.background,
      ),

      // the guard is the first route's widget, so it can pop every screen a dead session opened
      home: const SessionExpiryGuard(child: AppShellScreen()),
    );
  }
}
