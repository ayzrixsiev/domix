import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/product_model.dart';
import '../../data/products_repository.dart';

// viewmodel behind the two screens that show a shop's catalogue: the owner's management grid
// (ShopProductsScreen) and the customer-facing grid on ShopCardScreen.
//
// the cache is keyed by shop id rather than being a single list, because those two screens are
// about *different* shops much of the time - a customer taps three pins in a row - and a single
// slot would make every reopen a fresh network round trip and a visible spinner. it is a session
// cache: nothing here is persisted, so a restart reloads.
class ProductsController extends ChangeNotifier {
  final ProductsRepository _repo;

  ProductsController({ProductsRepository? repository})
      : _repo = repository ?? ProductsRepository();

  final Map<int, List<Product>> _byShop = {};
  final Set<int> _loadingShopIds = {};
  /// The shops whose last catalogue load failed. **A set of ids, not a map of messages** - the
  /// screens read it as "did this shop's catalogue fail", draw a written sentence of their own, and
  /// the exception goes to `debugPrint` in [loadProducts]. It held `e.toString()` per shop, which is
  /// one `subtitle: controller.loadErrorFor(id)` away from a customer reading a stack of Dart.
  final Set<int> _failedLoads = {};

  // the add/edit/delete form on ShopProductsScreen. one busy flag rather than one per product: only
  // one edit sheet is ever open at a time, and the screen disables its save/delete buttons together.
  bool _isSaving = false;
  ProductMutationException? _saveError;

  // the photo has its own pair, deliberately not [_isSaving]/[_saveError].
  //
  // It is a separate action on the same screen: it starts when the owner picks an image rather than
  // when they press «Сохранить», it takes seconds rather than milliseconds, and it fails for reasons
  // of its own ("that file is not a photo") that the form's error card would report as a failure to
  // save a product. Sharing the flags would also grey out the save button for the length of an
  // upload, which is the one moment the rest of the form is perfectly usable.
  bool _isPhotoBusy = false;
  ProductMutationException? _photoError;

  /// the shop's catalogue, or an empty list if it has never been loaded. `const []` and not a new
  /// list each call, so a widget rebuilding doesn't allocate and doesn't get a mutable view of
  /// nothing that it might try to add to.
  List<Product> productsFor(int shopId) => _byShop[shopId] ?? const [];

  bool isLoadingFor(int shopId) => _loadingShopIds.contains(shopId);
  bool loadFailedFor(int shopId) => _failedLoads.contains(shopId);
  bool hasLoaded(int shopId) => _byShop.containsKey(shopId);

  bool get isSaving => _isSaving;
  ProductMutationException? get saveError => _saveError;

  bool get isPhotoBusy => _isPhotoBusy;
  ProductMutationException? get photoError => _photoError;

  /// how many products in this shop the owner added themselves. the backend enforces the cap; this
  /// is only for showing "12 / 20" and greying the add tile out before a doomed round trip.
  int customCountFor(int shopId) =>
      productsFor(shopId).where((p) => !p.isTemplate).length;

  /// how many of the *category template's* rows have a price, out of how many there are - the pair
  /// an owner is working through after creating a shop, since every template product arrives without
  /// a price.
  ///
  /// template rows only, and that is not a detail. the basket price index counts a shop only once
  /// every template row is priced (migration 000013), and the owner's own added products are not
  /// part of the shared basket at all - so a progress bar that counted them would reach 100% at the
  /// wrong moment in one direction and refuse to reach it in the other, on a bar whose completion
  /// now means "your shop is in the comparison".
  (int priced, int total) templatePricingProgressFor(int shopId) {
    var priced = 0;
    var total = 0;
    for (final product in productsFor(shopId)) {
      if (!product.isTemplate) continue;
      total++;
      if (product.hasPrice) priced++;
    }
    return (priced, total);
  }

  /// [force] re-fetches a shop already in the cache, which is what a pull-to-refresh wants. without
  /// it, a screen opening on a shop it has seen before shows the cached list immediately.
  Future<void> loadProducts(int shopId, {bool force = false}) async {
    if (_loadingShopIds.contains(shopId)) return; // a second call while one is in flight is a no-op
    if (!force && _byShop.containsKey(shopId)) return;

    _loadingShopIds.add(shopId);
    _failedLoads.remove(shopId);
    notifyListeners();

    try {
      _byShop[shopId] = await _repo.fetchShopProducts(shopId);
    } catch (e) {
      _failedLoads.add(shopId);
      debugPrint('loadProducts failed for shop $shopId: $e');
    }

    _loadingShopIds.remove(shopId);
    notifyListeners();
  }

  /// returns the saved product on success, null on failure (saveError then holds the reason).
  /// returning the product rather than a bool is what lets the caller pop back to a grid that is
  /// already correct instead of waiting for a re-fetch.
  Future<Product?> addProduct({required int shopId, required Product draft}) async {
    return _mutate(() async {
      final created = await _repo.createProduct(shopId: shopId, draft: draft);
      // appended, not re-fetched: the backend orders template rows first and the owner's own after,
      // so a new custom product belongs exactly at the end - the one place the local list can be
      // updated without guessing at the server's ordering
      _byShop[shopId] = [...productsFor(shopId), created];
      return created;
    });
  }

  Future<Product?> updateProduct(Product product) async {
    return _mutate(() async {
      final saved = await _repo.updateProduct(product);
      _replaceInCache(saved);
      return saved;
    });
  }

  /// Attaches a photo to a product that already exists, returning the saved product or null on
  /// failure ([photoError] then holds the reason).
  ///
  /// [filePath] is what `image_picker` handed back - a file in the app's own cache directory, which
  /// the plugin has already re-encoded to jpeg at the size asked for.
  Future<Product?> uploadProductPhoto({required Product product, required String filePath}) {
    return _mutatePhoto(() => _repo.uploadProductImage(productId: product.id, filePath: filePath));
  }

  /// Removes it again. The product comes back carrying whatever photo it *should* have now, which
  /// for a template row is the catalogue's own shot - so this is not always "the tile goes blank",
  /// and the app does not have to know which case it is in.
  Future<Product?> removeProductPhoto(Product product) {
    return _mutatePhoto(() => _repo.removeProductImage(product.id));
  }

  /// returns true on success, so the edit screen knows it can pop
  Future<bool> deleteProduct(Product product) async {
    final result = await _mutate(() async {
      await _repo.deleteProduct(product.id);
      _byShop[product.shopId] = [
        for (final p in productsFor(product.shopId))
          if (p.id != product.id) p,
      ];
      return product;
    });
    return result != null;
  }

  /// Swap one product in the cache for the version the server just returned. The grid, the map
  /// sheet and the edit screen all read the same list, so a product is replaced in one place.
  void _replaceInCache(Product saved) {
    _byShop[saved.shopId] = [
      for (final p in productsFor(saved.shopId)) p.id == saved.id ? saved : p,
    ];
  }

  // the same shape as _mutate below, against the photo's own flags. it is a copy of six lines
  // rather than a parameter on _mutate because the two sets of state exist precisely so that a
  // photo failing and a save failing are two different things on screen.
  Future<Product?> _mutatePhoto(Future<Product> Function() action) async {
    _isPhotoBusy = true;
    _photoError = null;
    notifyListeners();

    Product? result;
    try {
      result = await action();
      _replaceInCache(result);
    } on ProductMutationException catch (e) {
      _photoError = e;
    } on TimeoutException catch (e) {
      _photoError = ProductMutationException(code: 'timeout', message: e.toString());
    } catch (e) {
      // the real exception goes to the log rather than into a `message` field nothing renders -
      // see the note in _mutate
      debugPrint('ProductsController: unexpected error during a photo upload: $e');
      _photoError = ProductMutationException(code: 'server_error', message: e.toString());
    }

    _isPhotoBusy = false;
    notifyListeners();
    return result;
  }

  // the three mutations differ only in the request they make and how they patch the local list;
  // everything around that - the busy flag, clearing the previous error, turning an unexpected
  // exception into one the ui can localize, notifying - is identical, so it lives here once.
  Future<Product?> _mutate(Future<Product> Function() action) async {
    _isSaving = true;
    _saveError = null;
    notifyListeners();

    Product? result;
    try {
      result = await action();
    } on ProductMutationException catch (e) {
      _saveError = e;
    } on TimeoutException catch (e) {
      // its own code, because "the request did not come back in ten seconds" and "the server said
      // no" need different words. this one is nearly always transient and the right advice is to
      // press save again, which is the opposite of what a generic failure message suggests.
      _saveError = ProductMutationException(code: 'timeout', message: e.toString());
    } catch (e) {
      // **the real exception used to end here and go no further.** it was stored in `message`,
      // which nothing renders, while the ui printed the switch's default - a sentence blaming the
      // user's connection for whatever this actually was. logging it is what makes the next one
      // ten minutes of `adb logcat` instead of an afternoon.
      debugPrint('ProductsController: unexpected error during mutation: $e');
      _saveError = ProductMutationException(code: 'server_error', message: e.toString());
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  /// called by the edit screen as it opens, so a failure from a previous visit doesn't paint an
  /// error over a form nothing has been submitted from yet. deliberately silent: no widget is
  /// displaying this state at that point, and notifying mid-build trips flutter's build guard -
  /// the same reason StoresController.resetSaveState is silent.
  void resetSaveState() {
    _isSaving = false;
    _saveError = null;
    _isPhotoBusy = false;
    _photoError = null;
  }

  /// drop a deleted shop's catalogue. without it the cache would hold rows for a shop that no
  /// longer exists, and an id reused by postgres later would serve them to the wrong shop.
  void forgetShop(int shopId) {
    _byShop.remove(shopId);
    _failedLoads.remove(shopId);
  }
}
