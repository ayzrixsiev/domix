import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/core/network/api_client.dart';
import '../../data/stores_repository.dart';
import '../../data/shop_category.dart';
import '../../data/shop_model.dart';

// viewmodel behind three screens: the map (every shop), the owner's "my shops" list, and the
// add-shop form. each keeps its own loading/error fields on purpose - they used to share one, which
// left a map's failure sitting on the add-shop form before the owner had pressed save.
class StoresController extends ChangeNotifier {
  final StoresRepository _repo;

  // the public list every shop, for the map
  List<Shop> _stores = [];
  bool _isLoading = false;
  LoadFailure? _loadFailure;

  /// When [_stores] was last successfully fetched. **A snapshot of somebody else's database with no
  /// push channel**, so the only honest question the map can ask is "how old is this" - see
  /// [isStoresStale].
  DateTime? _storesFetchedAt;

  // bumped when the account changes, so a load that left under the last one is followed by another
  int _viewer = 0;

  // only the current owner's own shops, for the management list
  List<Shop> _myShops = [];
  bool _isLoadingMyShops = false;
  LoadFailure? _myShopsFailure;

  // the add-shop form
  bool _isSaving = false;
  LoadFailure? _saveFailure;

  // the edit-shop form and the delete action share one busy flag on purpose: the screen disables
  // both buttons while either is in flight, since deleting a shop mid-save has no sensible outcome
  bool _isMutatingShop = false;
  ShopMutationException? _shopMutationError;

  StoresController({StoresRepository? repository})
    : _repo = repository ?? StoresRepository();

  List<Shop> get stores => _stores;
  bool get isLoading => _isLoading;

  /// **The kind, never a message**: every screen draws its own sentence from it, and the exception goes
  /// to `debugPrint` - a raw `ClientException` is one careless `subtitle:` away from a customer.
  LoadFailure? get loadFailure => _loadFailure;

  /// How long a fetched shop list is trusted before the map re-fetches on the next visit. Short
  /// enough that a shop added while the app is open shows up without a restart, long enough that
  /// flicking between tabs is not a request each time.
  static const Duration storesFreshFor = Duration(minutes: 2);

  /// Whether the map should re-fetch: nothing ever loaded, the last attempt failed, or the snapshot
  /// has aged past [storesFreshFor]. The map asks on every tab switch, which is what fixes the bug
  /// this was written for - a failed load used to leave an error banner not even a restart cleared,
  /// since the IndexedStack keeps the State alive.
  bool get isStoresStale {
    if (_loadFailure != null) return true;
    final fetchedAt = _storesFetchedAt;
    if (fetchedAt == null) return true;
    return DateTime.now().difference(fetchedAt) > storesFreshFor;
  }

  List<Shop> get myShops => _myShops;
  bool get isLoadingMyShops => _isLoadingMyShops;
  LoadFailure? get myShopsFailure => _myShopsFailure;

  bool get isSaving => _isSaving;
  LoadFailure? get saveFailure => _saveFailure;

  bool get isMutatingShop => _isMutatingShop;
  ShopMutationException? get shopMutationError => _shopMutationError;

  Future<void> loadStores() async {
    // a second call while one is in flight is a no-op: without it, switching to the map tab during a
    // ten-second timeout stacks a second request behind the first - with the backend down, one per tab
    // switch
    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();
    final asked = _viewer;

    try {
      _stores = await _repo.fetchStores();
      _loadFailure = null;
      _storesFetchedAt = DateTime.now();
    } catch (e) {
      _loadFailure = LoadFailure.of(e);
      // the console is where the real reason goes: the banner shows a fixed sentence, so without this
      // "the tunnel moved" and "the server returned 500" are indistinguishable
      debugPrint('loadStores failed: $e');
    }

    _isLoading = false;
    notifyListeners();

    if (asked != _viewer) await loadStores();
  }

  /// Signed in, signed out or became a shop owner: a seller's map carries no price labels. Re-fetched
  /// at once rather than on the next tab switch, since signing in from a shop sheet lands back on the
  /// map itself.
  void handleViewerChanged() {
    _viewer++;
    _storesFetchedAt = null;
    if (_stores.isNotEmpty && !_isLoading) unawaited(loadStores());
  }

  /// Re-fetches the map's shop list, but only if what we hold is no longer trustworthy - called every
  /// time the map tab becomes visible. [isStoresStale] is where the line is drawn between leaving
  /// deleted shops on the map and putting a ten-second timeout in front of one that just worked.
  Future<void> refreshStoresIfStale() async {
    if (!isStoresStale) return;
    await loadStores();
  }

  /// The session ended: forget whatever belonged to it.
  ///
  /// **Two different facts, which is why this takes a flag.** [_myShops] always goes. [_stores] is the
  /// *public* map, and a logout changes nothing about it - but a **deletion** cascades server-side, so
  /// those pins are dropped here rather than on a re-fetch: a pin has to leave the map at the same
  /// moment the account does. Either way the snapshot is marked stale.
  void handleSessionEnded(bool accountDeleted) {
    if (accountDeleted && _myShops.isNotEmpty) {
      final deletedIds = {for (final shop in _myShops) shop.id};
      _stores = [
        for (final s in _stores)
          if (!deletedIds.contains(s.id)) s,
      ];
    }

    _myShops = [];
    _myShopsFailure = null;
    _isLoadingMyShops = false;
    _storesFetchedAt = null;

    notifyListeners();
  }

  Future<void> loadMyShops() async {
    _isLoadingMyShops = true;
    notifyListeners();

    try {
      _myShops = await _repo.fetchMyShops();
      _myShopsFailure = null;
    } catch (e) {
      _myShopsFailure = LoadFailure.of(e);
      debugPrint('loadMyShops failed: $e');
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
    _saveFailure = null;
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
      // null is a session that died mid-save: SessionExpiryGuard already explains it and pops the form,
      // so no error is set here
      if (shop == null) {
        _isSaving = false;
        notifyListeners();
        return false;
      }

      // append to both lists rather than re-fetching: the map needs the new pin immediately, and whoever
      // creates a shop is by definition its owner
      _stores = [..._stores, shop];
      _myShops = [
        shop,
        ..._myShops,
      ]; // newest first, matching ListShopsByOwner's ordering
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      _saveFailure = LoadFailure.of(e);
      debugPrint('createShop failed: $e');
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  // called by AddStoreScreen as it opens. silent: no widget is displaying this field yet, and
  // notifying mid-build would trip flutter's "called during build" guard.
  void resetSaveState() {
    _isSaving = false;
    _saveFailure = null;
  }

  // returns the saved shop on success, null on failure ([shopMutationError] then holds the reason) -
  // which is what lets the settings screen redraw its header with the new name immediately
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

      // the PUT response has no product_count (only /api/shops/mine computes one), so carry the count we
      // already know across instead of letting every edit reset the row to "no products"
      final previous = _findById(_myShops, shopId);
      final merged = saved.copyWith(productCount: previous?.productCount ?? 0);

      // replace in place in both lists: the map's pin has to move if the location changed, and the
      // management row has to show the new name. no re-fetch - we hold the authoritative row.
      _myShops = [for (final s in _myShops) s.id == shopId ? merged : s];
      _stores = [for (final s in _stores) s.id == shopId ? merged : s];

      _isMutatingShop = false;
      notifyListeners();
      return merged;
    } on ShopMutationException catch (e) {
      _shopMutationError = e;
    } catch (e) {
      _shopMutationError = ShopMutationException(
        code: 'server_error',
        message: e.toString(),
      );
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
      // drop it from both lists rather than re-fetching: the pin must leave the map at the same moment
      // the row leaves the management list, and one round trip cannot guarantee that
      _myShops = [
        for (final s in _myShops)
          if (s.id != shopId) s,
      ];
      _stores = [
        for (final s in _stores)
          if (s.id != shopId) s,
      ];
      _isMutatingShop = false;
      notifyListeners();
      return true;
    } on ShopMutationException catch (e) {
      _shopMutationError = e;
    } catch (e) {
      _shopMutationError = ShopMutationException(
        code: 'server_error',
        message: e.toString(),
      );
    }

    _isMutatingShop = false;
    notifyListeners();
    return false;
  }

  // called by EditStoreScreen as it opens, so a failure from a previous visit does not paint an error
  // over a form nothing has been submitted from. silent for the same reason as resetSaveState.
  void resetShopMutationState() {
    _isMutatingShop = false;
    _shopMutationError = null;
  }

  // called by the products screen after the owner adds or deletes a product: the *count* is a Shop
  // field only /api/shops/mine computes, so without this the settings hub keeps the number from the
  // last full load. patched rather than re-fetched - one arithmetic operation against a round trip.
  void adjustProductCount(int shopId, int delta) {
    final shop = _findById(_myShops, shopId);
    if (shop == null) return;

    // clamped at zero: a count cannot go negative, and letting it would turn one lost sync into a
    // permanently wrong badge
    final updated = shop.copyWith(
      productCount: (shop.productCount + delta).clamp(0, 1 << 30),
    );
    _myShops = [for (final s in _myShops) s.id == shopId ? updated : s];
    notifyListeners();
  }

  // firstWhere with orElse:null needs a nullable element type, which List<Shop> is not
  Shop? _findById(List<Shop> list, int id) {
    for (final shop in list) {
      if (shop.id == id) return shop;
    }
    return null;
  }
}
