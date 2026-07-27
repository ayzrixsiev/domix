import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/app_shell/presentation/screens/app_shell_screen.dart';
import 'features/location/presentation/controllers/city_controller.dart';
import 'features/profile/presentation/controllers/auth_controller.dart';
import 'features/stores/presentation/controllers/stores_controller.dart';
import 'features/products/presentation/controllers/products_controller.dart';

void main() async {
  // wake up flutter engine drivers to read hardware encrypted storage before drawing ui
  WidgetsFlutterBinding.ensureInitialized();

  // initialize all controllers before running the app
  // explicitly await initialization to ensure storage/data is ready before ui renders
  final authController = AuthController();
  await authController.checkExistingLogin();
  final storesController = StoresController();
  final productsController = ProductsController();

  runApp(
    DevicePreview(
      enabled: !kReleaseMode,
      builder: (context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          // holds nothing that needs loading before first paint, so it is built lazily here
          // rather than awaited above alongside the controllers that read storage
          ChangeNotifierProvider(create: (_) => CityController()),
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

      // device preview configuration hooks
      builder: DevicePreview.appBuilder,
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