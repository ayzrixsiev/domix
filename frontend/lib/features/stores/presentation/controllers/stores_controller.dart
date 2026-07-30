import 'package:flutter/material.dart';
import '../../data/stores_repository.dart';
import '../../data/shop_category.dart';
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

  // the edit-shop form and the delete action, both on EditStoreScreen. they share one busy flag on
  // purpose - the screen disables both buttons while either is in flight, since deleting a shop
  // mid-save (or the reverse) has no sensible outcome.
  bool _isMutatingShop = false;
  ShopMutationException? _shopMutationError;

  StoresController({StoresRepository? repository}) : _repo = repository ?? StoresRepository();

  List<Shop> get stores => _stores;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  List<Shop> get myShops => _myShops;
  bool get isLoadingMyShops => _isLoadingMyShops;
  String? get myShopsError => _myShopsError;

  bool get isSaving => _isSaving;
  String? get saveError => _saveError;

  bool get isMutatingShop => _isMutatingShop;
  ShopMutationException? get shopMutationError => _shopMutationError;


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
    required ShopCategory category,
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
        category: category,
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

  // returns the saved shop on success, null on failure (shopMutationError then holds the reason).
  // returning the shop rather than a bool is what lets the settings screen redraw its header with
  // the new name immediately instead of waiting for the next loadMyShops().
  Future<Shop?> updateShop({
    required int shopId,
    required String name,
    required String contactPhone,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    _isMutatingShop = true;
    _shopMutationError = null;
    notifyListeners();

    try {
      final saved = await _repo.updateShop(
        shopId: shopId,
        name: name,
        contactPhone: contactPhone,
        address: address,
        latitude: latitude,
        longitude: longitude,
      );

      // the PUT response has no product_count (only /api/shops/mine computes one), so carry the
      // count we already know across instead of letting every edit reset the row to "no products"
      final previous = _findById(_myShops, shopId);
      final merged = saved.copyWith(productCount: previous?.productCount ?? 0);

      // replace in place in both lists: the map's pin has to move if the location changed, and the
      // management row has to show the new name. no re-fetch - we already hold the authoritative row.
      _myShops = [for (final s in _myShops) s.id == shopId ? merged : s];
      _stores = [for (final s in _stores) s.id == shopId ? merged : s];

      _isMutatingShop = false;
      notifyListeners();
      return merged;
    } on ShopMutationException catch (e) {
      _shopMutationError = e;
    } catch (e) {
      _shopMutationError = ShopMutationException(code: 'server_error', message: e.toString());
    }

    _isMutatingShop = false;
    notifyListeners();
    return null;
  }

  // returns true on success, so the screen knows it can pop back to the shops list
  Future<bool> deleteShop(int shopId) async {
    _isMutatingShop = true;
    _shopMutationError = null;
    notifyListeners();

    try {
      await _repo.deleteShop(shopId);
      // drop it from both lists rather than re-fetching: the pin must leave the map at the same
      // moment the row leaves the management list, and one round trip can't guarantee that
      _myShops = [for (final s in _myShops) if (s.id != shopId) s];
      _stores = [for (final s in _stores) if (s.id != shopId) s];
      _isMutatingShop = false;
      notifyListeners();
      return true;
    } on ShopMutationException catch (e) {
      _shopMutationError = e;
    } catch (e) {
      _shopMutationError = ShopMutationException(code: 'server_error', message: e.toString());
    }

    _isMutatingShop = false;
    notifyListeners();
    return false;
  }

  // called by EditStoreScreen as it opens, so a failure from a previous visit doesn't paint an error
  // over a form nothing has been submitted from yet. silent for the same reason as resetSaveState.
  void resetShopMutationState() {
    _isMutatingShop = false;
    _shopMutationError = null;
  }

  // called by the products screen after the owner adds or deletes one of their own products. the
  // catalogue itself lives in ProductsController, but the *count* is a field on Shop that only
  // /api/shops/mine computes - so without this the badge on the settings hub would keep showing the
  // number from the last full load until the screen was left and reopened.
  //
  // patching the number we already hold rather than calling loadMyShops() again: one arithmetic
  // operation against a whole round trip, for a value we know exactly how much has changed by.
  void adjustProductCount(int shopId, int delta) {
    final shop = _findById(_myShops, shopId);
    if (shop == null) return;

    // clamped at zero: a count can't go negative, and letting it would turn one lost sync into a
    // permanently wrong badge
    final updated = shop.copyWith(productCount: (shop.productCount + delta).clamp(0, 1 << 30));
    _myShops = [for (final s in _myShops) s.id == shopId ? updated : s];
    notifyListeners();
  }

  // firstWhere with orElse:null needs a nullable element type, which List<Shop> isn't - so this
  // plain loop rather than fighting the type system for a one-liner
  Shop? _findById(List<Shop> list, int id) {
    for (final shop in list) {
      if (shop.id == id) return shop;
    }
    return null;
  }
}
