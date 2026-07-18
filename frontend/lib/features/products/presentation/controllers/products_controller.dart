import 'package:flutter/material.dart';
import '../../data/products_repository.dart';

// products controller - simple viewmodel for listing and saving products
class ProductsController extends ChangeNotifier {
  final ProductsRepository _repo;

  List<Map<String, dynamic>> _products = [];
  bool _isLoading = false;

  ProductsController({ProductsRepository? repository}) : _repo = repository ?? ProductsRepository();

  List<Map<String, dynamic>> get products => _products;
  bool get isLoading => _isLoading;

  Future<void> loadProducts(String storeId) async {
    _isLoading = true;
    notifyListeners();
    _products = await _repo.fetchProducts(storeId);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveProduct(Map<String, dynamic> product) async {
    await _repo.saveProduct(product);
    // optionally reload or update local list
    notifyListeners();
  }
}
