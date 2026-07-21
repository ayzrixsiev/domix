import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/localization/language_provider.dart';
import '../controllers/stores_controller.dart';

// simple placeholder stores screen to visualize controller usage
class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // get stores controller from DI
    final controller = Provider.of<StoresController>(context);
    final strings = Provider.of<LanguageProvider>(context).strings;
    
    return Scaffold(
      appBar: AppBar(title: Text(strings.storesTitle)),
      body: FutureBuilder(
        future: Future(() async {
          // load stores on first build
          if (controller.stores.isEmpty && !controller.isLoading) {
            await controller.loadStores();
          }
        }),
        builder: (context, snapshot) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (controller.isLoading) return const Center(child: CircularProgressIndicator());
              return ListView(
                children: controller.stores.map((s) => ListTile(title: Text(s['name'] ?? strings.storeFallback))).toList(),
              );
            },
          );
        },
      ),
    );
  }
}
