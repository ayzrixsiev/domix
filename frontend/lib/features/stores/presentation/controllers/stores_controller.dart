import 'package:flutter/material.dart';
import '../../data/stores_repository.dart';

// stores controller - viewmodel that exposes store list and simple actions
class StoresController extends ChangeNotifier {
  final StoresRepository _repo;

  List<Map<String, dynamic>> _stores = [];
  bool _isLoading = false;

  StoresController({StoresRepository? repository}) : _repo = repository ?? StoresRepository();

  List<Map<String, dynamic>> get stores => _stores;
  bool get isLoading => _isLoading;

  Future<void> loadStores() async {
    _isLoading = true;
    notifyListeners();
    _stores = await _repo.fetchStores();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveStore(Map<String, dynamic> store) async {
    await _repo.saveStore(store);
    await loadStores();
  }
}
