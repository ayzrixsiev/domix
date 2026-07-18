import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/products_controller.dart';

class ProductsScreen extends StatelessWidget {
  final String storeId;
  const ProductsScreen({super.key, required this.storeId});

  @override
  Widget build(BuildContext context) {
    // get products controller from DI
    final controller = Provider.of<ProductsController>(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text('products')),
      body: FutureBuilder(
        future: Future(() async {
          // load products for this store on first build
          if (controller.products.isEmpty && !controller.isLoading) {
            await controller.loadProducts(storeId);
          }
        }),
        builder: (context, snapshot) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (controller.isLoading) return const Center(child: CircularProgressIndicator());
              return ListView(
                children: controller.products.map((p) => ListTile(title: Text(p['name'] ?? 'product'))).toList(),
              );
            },
          );
        },
      ),
    );
  }
}
