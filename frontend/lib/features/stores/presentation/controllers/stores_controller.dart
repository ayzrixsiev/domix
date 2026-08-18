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

  /// When [_stores] was last successfully fetched, or null if it never has been.
  ///
  /// **This list is a snapshot of somebody else's database and there is no push channel.** Shops
  /// appear, move and disappear without the app being told, so the only honest question the map can
  /// ask is "how old is what I am showing" - see [isStoresStale].
  DateTime? _storesFetchedAt;

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

  /// How long a fetched shop list is trusted before the map re-fetches it on the next visit.
  ///
  /// Two minutes is short enough that a shop added or deleted while the app is open shows up
  /// without a restart, and long enough that flicking between tabs does not put the map on the
  /// network every time. It is not a correctness guarantee and cannot be - see [isStoresStale].
  static const Duration storesFreshFor = Duration(minutes: 2);

  /// Whether the map should re-fetch before drawing again.
  ///
  /// True when nothing has ever loaded, when the last attempt failed, or when the snapshot has aged
  /// past [storesFreshFor]. The map calls [refreshStoresIfStale] each time its tab becomes visible,
  /// which is what fixes both halves of the bug this was written for: a load that failed used to
  /// leave a permanent «Не удалось загрузить магазины» that not even restarting the app cleared,
  /// because [MapScreen.initState] runs once per app session and the IndexedStack keeps the State
  /// alive across every tab switch.
  bool get isStoresStale {
    if (_loadError != null) return true;
    final fetchedAt = _storesFetchedAt;
    if (fetchedAt == null) return true;
    return DateTime.now().difference(fetchedAt) > storesFreshFor;
  }

  List<Shop> get myShops => _myShops;
  bool get isLoadingMyShops => _isLoadingMyShops;
  String? get myShopsError => _myShopsError;

  bool get isSaving => _isSaving;
  String? get saveError => _saveError;

  bool get isMutatingShop => _isMutatingShop;
  ShopMutationException? get shopMutationError => _shopMutationError;


  Future<void> loadStores() async {
    // a second call while one is already in flight is a no-op. without it, switching to the map tab
    // while a ten-second timeout is still counting down would stack a second request behind the
    // first - and with the backend down, one per tab switch.
    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      _stores = await _repo.fetchStores();
      _loadError = null;
      _storesFetchedAt = DateTime.now();
    } catch (e) {
      _loadError = e.toString().replaceAll('Exception: ', '');
      // printed as well as stored. the banner shows a fixed russian sentence, so without this the
      // difference between "the tunnel moved" and "the server returned 500" is invisible from the
      // console - and those need completely different fixes.
      debugPrint('loadStores failed: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Re-fetches the map's shop list, but only if what we hold is no longer trustworthy.
  ///
  /// Called every time the map tab becomes visible. The cheap answer - "we already have a list,
  /// don't ask again" - is what left deleted shops on the map and a dead error banner on screen;
  /// the expensive one - fetch on every tab switch - puts a ten-second timeout in the way of a map
  /// that was working a second ago. [isStoresStale] is where the line between them is drawn.
  Future<void> refreshStoresIfStale() async {
    if (!isStoresStale) return;
    await loadStores();
  }

  /// The session ended: forget whatever belonged to it.
  ///
  /// **Two different facts, which is why this takes a flag rather than just clearing everything.**
  ///
  ///   * [_myShops] always goes. It is the management list, and there is nobody left to manage it.
  ///   * [_stores] is the *public* map, and a logout changes nothing about it - those shops are
  ///     still open, still on the map, still somebody's. Wiping it on logout would blank the map
  ///     for a user who simply signed out.
  ///
  /// When the account was **deleted**, the second sentence stops being true: the schema cascades, so
  /// the server destroyed that owner's shops and every product in them in the same statement. Those
  /// pins are wrong from that moment, and the app knows exactly which ones they are - it is holding
  /// the list. So they are dropped here, the same way [deleteShop] drops one, rather than waiting
  /// for a re-fetch: the pin has to leave the map at the same moment the account does, and a round
  /// trip cannot promise that.
  ///
  /// The snapshot is marked stale either way, so the next visit to the map re-syncs with the server
  /// rather than trusting a list assembled by arithmetic.
  void handleSessionEnded(bool accountDeleted) {
    if (accountDeleted && _myShops.isNotEmpty) {
      final deletedIds = {for (final shop in _myShops) shop.id};
      _stores = [for (final s in _stores) if (!deletedIds.contains(s.id)) s];
    }

    _myShops = [];
    _myShopsError = null;
    _isLoadingMyShops = false;
    _storesFetchedAt = null;

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
