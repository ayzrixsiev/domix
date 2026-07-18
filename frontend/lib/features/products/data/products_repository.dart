// products_repository.dart - placeholder for product data access

class ProductsRepository {
  Future<List<Map<String, dynamic>>> fetchProducts(String storeId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return [
      {'id': 'p1', 'name': 'Demo Product', 'price': 9.99},
    ];
  }

  Future<void> saveProduct(Map<String, dynamic> product) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
