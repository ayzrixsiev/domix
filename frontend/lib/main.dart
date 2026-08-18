import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:yandex_maps_mapkit_lite/init.dart' as mapkit_init;
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/map_config.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/app_shell/presentation/screens/app_shell_screen.dart';
import 'features/home/presentation/controllers/home_controller.dart';
import 'features/location/presentation/controllers/city_controller.dart';
import 'features/profile/presentation/controllers/auth_controller.dart';
import 'features/stores/presentation/controllers/stores_controller.dart';
import 'features/products/presentation/controllers/products_controller.dart';

void main() async {
  // wake up flutter engine drivers to read hardware encrypted storage before drawing ui
  WidgetsFlutterBinding.ensureInitialized();

  // portrait only. every screen here is a vertical feed, a map or a form, and none of them was
  // designed against a 360px-tall viewport - in landscape the VIP carousel alone is taller than the
  // screen. locking it is one line; making five screens work sideways is not, and nobody asked for
  // sideways.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // initialize all controllers before running the app
  // explicitly await initialization to ensure storage/data is ready before ui renders
  // MapKit has to be initialized once, before any map widget is built, and it is a native call -
  // so it is guarded twice. `isSupportedPlatform` keeps a desktop `flutter run` alive (the plugin
  // simply does not exist there, and calling in would throw before the first frame), and `hasApiKey`
  // keeps a checkout without a key alive. The map screens show an explanatory panel in both cases
  // rather than a crash; see MapConfig.
  if (MapConfig.isAvailable) {
    await mapkit_init.initMapkit(apiKey: MapConfig.apiKey);
  }

  final authController = AuthController();
  // awaited: reads secure storage and checks the token's own expiry, both fast and both offline, so
  // the first frame is already correct rather than flickering from profile to guest.
  await authController.checkExistingLogin();
  // *not* awaited: this one is a network round trip. the app opens on the cached session and drops
  // to guest a moment later if the server disagrees - which beats holding a splash screen on every
  // cold start to pay for a check that almost always passes.
  unawaited(authController.verifySession());
  final storesController = StoresController();
  final productsController = ProductsController();

  // the one wire between the login state machine and the map's shop list.
  //
  // deleting an account destroys that owner's shops server-side (the schema cascades), so the pins
  // the map is holding become wrong at that exact moment - and nothing would ever tell it, because
  // the shop list is fetched once and kept. this is what tells it. a callback rather than an import
  // in either direction: AuthController knows nothing about shops and StoresController knows nothing
  // about sessions, and main() is the one place that is allowed to know about both.
  authController.onSessionEnded = storesController.handleSessionEnded;

  runApp(
    DevicePreview(
      // desktop only in practice: on a phone or the emulator the device *is* the frame, so this
      // wraps a real 1080x2400 screen in a picture of a smaller one, which helps nobody.
      enabled: !kReleaseMode && !MapConfig.isSupportedPlatform,
      builder: (context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          // holds nothing that needs loading before first paint, so it is built lazily here
          // rather than awaited above alongside the controllers that read storage
          ChangeNotifierProvider(create: (_) => CityController()),
          // same: the home screen kicks off its own fetch from initState, so there is nothing to
          // await here - building it lazily keeps a cold start off the network until the first
          // frame is already on screen
          ChangeNotifierProvider(create: (_) => HomeController()),
          ChangeNotifierProvider.value(value: authController),      // make all
          ChangeNotifierProvider.value(value: storesController),    // UI components
          ChangeNotifierProvider.value(value: productsController),  // to listen to these controllers using notifyListener()
        ],
        child: const DomixApp(),
      ),
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

      // **the app draws its own type sizes and ignores the phone's font-size setting.**
      //
      // Flutter's default is to multiply every font size by MediaQuery.textScaler, which Android's
      // "Размер шрифта" slider drives from 0.85 up to 2.0. The layout here is built on fixed card
      // heights - ProductTile is 208px, the VIP card 232 - so scaled text has nowhere to go and
      // overflows: measured at 1.3 ("Крупнее", an ordinary setting) the VIP card overflows by 9px,
      // and at 1.6 the product tiles go too.
      //
      // This is a deliberate trade the founder chose: the design stays exactly as drawn on every
      // phone, and a user who has enlarged their system font for a reason does not get it here. The
      // honest fix is cards that grow with their content, and if that ever gets built this wrapper
      // is what should be deleted - not raised to a bigger fixed number.
      //
      // this slot used to hold two wrappers, DevicePreview's on the outside and ours within it.
      // DevicePreview is gone - the emulator does its job properly - and this is the half that
      // stays, since it is what enforces the paragraph above.
      // two wrappers in one slot, and the order is load-bearing. DevicePreview.appBuilder is on
      // the outside because it supplies the simulated phone's MediaQuery (its size, its padding,
      // its text scale); withNoTextScaling sits *inside* it, so ours is the nearer MediaQuery and
      // wins for every widget below - including over DevicePreview's own font-size slider, which
      // would otherwise demonstrate a scaling the real app refuses to do (§11).
      // **Delete the DevicePreview half before release, not this one.**
      builder: (context, child) =>
          DevicePreview.appBuilder(context, MediaQuery.withNoTextScaling(child: child!)),
      locale: Provider.of<LanguageProvider>(context).locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru'),
        Locale('uz'),
      ],
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        // the token, not a copy of its value - this literal was a duplicate of AppColors.background
        // and would have silently kept the old shade when that token was darkened
        scaffoldBackgroundColor: AppColors.background,
      ),

      home: const AppShellScreen(),
    );
  }
}
