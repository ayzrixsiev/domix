import 'package:flutter/material.dart';
import '../../data/stores_repository.dart';
import '../../data/product_upload_result.dart';
import '../../data/shop_model.dart';

// stores controller - viewmodel behind three separate screens: the map (every shop), the owner's
// "my shops" management list, and the add-shop form.
//
// each of those keeps its own loading/error fields on purpose. they used to share one _errorMessage,
// which meant a map that failed to load left an error card sitting on the add-shop form before the
// owner had even pressed save - unrelated features must not be able to set each other's error text.
class StoresController extends ChangeNotifier {
  final StoresRepository _repo;

  // the public list every shop, for the map
  List<Shop> _stores = [];
  bool _isLoading = false;
  String? _loadError;

  // only the current owner's own shops, for the management list
  List<Shop> _myShops = [];
  bool _isLoadingMyShops = false;
  String? _myShopsError;

  // the add-shop form
  bool _isSaving = false;
  String? _saveError;

  // ShopUploadScreen's bulk-products upload
  bool _isUploading = false;
  ProductUploadResult? _uploadResult;
  ProductUploadException? _uploadError;

  StoresController({StoresRepository? repository}) : _repo = repository ?? StoresRepository();

  List<Shop> get stores => _stores;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  List<Shop> get myShops => _myShops;
  bool get isLoadingMyShops => _isLoadingMyShops;
  String? get myShopsError => _myShopsError;

  bool get isSaving => _isSaving;
  String? get saveError => _saveError;

  bool get isUploading => _isUploading;
  ProductUploadResult? get uploadResult => _uploadResult;
  ProductUploadException? get uploadError => _uploadError;

  Future<void> loadStores() async {
    _isLoading = true;
    notifyListeners();

    try {
      _stores = await _repo.fetchStores();
      _loadError = null;
    } catch (e) {
      _loadError = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMyShops() async {
    _isLoadingMyShops = true;
    notifyListeners();

    try {
      _myShops = await _repo.fetchMyShops();
      _myShopsError = null;
    } catch (e) {
      _myShopsError = e.toString().replaceAll('Exception: ', '');
    }

    _isLoadingMyShops = false;
    notifyListeners();
  }

  // returns true on success, so the add-store screen knows it can close itself
  Future<bool> createShop({
    required String name,
    required String contactPhone,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    _isSaving = true;
    _saveError = null;
    notifyListeners();

    try {
      final shop = await _repo.createShop(
        name: name,
        contactPhone: contactPhone,
        address: address,
        latitude: latitude,
        longitude: longitude,
      );
      // append to both lists rather than re-fetching: the map needs the new pin immediately, and
      // whoever creates a shop is by definition its owner, so it belongs in "my shops" too - without
      // that second append the management list stays empty right after adding your first shop
      _stores = [..._stores, shop];
      _myShops = [shop, ..._myShops]; // newest first, matching ListShopsByOwner's ordering
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      _saveError = e.toString().replaceAll('Exception: ', '');
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  // called by AddStoreScreen as it opens. deliberately silent: no widget is displaying this field
  // yet at that point, and notifying mid-build would trip flutter's "called during build" guard.
  void resetSaveState() {
    _isSaving = false;
    _saveError = null;
  }

  Future<void> uploadProductsFile({required int shopId, required String filePath}) async {
    _isUploading = true;
    _uploadResult = null;
    _uploadError = null;
    notifyListeners();

    try {
      _uploadResult = await _repo.uploadProductsFile(shopId: shopId, filePath: filePath);
      // the shop's product count just changed, so the row this screen was opened from is stale
      await loadMyShops();
    } on ProductUploadException catch (e) {
      _uploadError = e;
    } catch (e) {
      _uploadError = ProductUploadException(code: 'server_error', message: e.toString());
    }

    _isUploading = false;
    notifyListeners();
  }

  // called by ShopUploadScreen as it opens, so one shop's result never shows up under another's
  // name. silent for the same reason as resetSaveState above.
  void resetUploadState() {
    _isUploading = false;
    _uploadResult = null;
    _uploadError = null;
  }
}
