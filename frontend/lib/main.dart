import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frontend/features/app_shell/presentation/screens/app_shell_screen.dart';

void main() {
  runApp(
    DevicePreview(
      enabled: !kReleaseMode,
      builder: (context) => const DomixApp(),
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

      // Device Preview configuration hooks
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,
      
      // Clean Light Theme matching your UI design
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      
      home: const AppShellScreen(),
    );
  }
}
