import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/product_model.dart';
import '../../data/products_repository.dart';

// viewmodel behind the two screens that show a shop's catalogue. keyed by shop id rather than a
// single list, because a customer taps three pins in a row and a single slot would make every reopen
// a fresh round trip. a session cache: nothing is persisted, and prices are re-read only when the app
// is opened again (see markAllStale) - construction prices do not move while somebody scrolls.
class ProductsController extends ChangeNotifier {
  final ProductsRepository _repo;

  ProductsController({ProductsRepository? repository})
    : _repo = repository ?? ProductsRepository();

  final Map<int, List<Product>> _byShop = {};

  /// Cached catalogues to re-read on the next open - see [markAllStale]. The old rows stay on screen
  /// until the new ones land, so nothing blinks.
  final Set<int> _stale = {};

  final Set<int> _loadingShopIds = {};

  /// The shops whose last catalogue load failed. **A set of ids, not a map of messages** - the
  /// screens read it as "did this shop's catalogue fail" and draw a written sentence of their own.
  final Set<int> _failedLoads = {};

  // one busy flag rather than one per product: only one edit sheet is ever open at a time, and the
  // screen disables its save and delete buttons together
  bool _isSaving = false;
  ProductMutationException? _saveError;

  // the photo has its own pair, deliberately not [_isSaving]/[_saveError]: it starts on pick rather
  // than on «Сохранить», takes seconds, and fails for reasons the form's error card would report as a
  // failed save - and sharing the flags would grey out save for the length of an upload.
  bool _isPhotoBusy = false;
  ProductMutationException? _photoError;

  /// The app came back to the foreground: prices are re-read the next time a shop is opened, and never
  /// while somebody is browsing. Called from AppShellScreen.
  void markAllStale() => _stale.addAll(_byShop.keys);

  /// `const []` and not a new list each call, so a rebuilding widget does not allocate and does not
  /// get a mutable view of nothing that it might try to add to
  List<Product> productsFor(int shopId) => _byShop[shopId] ?? const [];

  bool isLoadingFor(int shopId) => _loadingShopIds.contains(shopId);
  bool loadFailedFor(int shopId) => _failedLoads.contains(shopId);
  bool hasLoaded(int shopId) => _byShop.containsKey(shopId);

  bool get isSaving => _isSaving;
  ProductMutationException? get saveError => _saveError;

  bool get isPhotoBusy => _isPhotoBusy;
  ProductMutationException? get photoError => _photoError;

  /// the backend enforces the cap; this is only for showing "12 / 20" and greying the add tile out
  /// before a doomed round trip
  int customCountFor(int shopId) =>
      productsFor(shopId).where((p) => !p.isTemplate).length;

  /// How many of the shop's *basket* rows have a price. Basket rows only, and that is not a detail: the
  /// index counts a shop only once every basket row is priced, and neither the owner's own products
  /// nor a template row outside the basket is part of it - counting either would put 100% at the
  /// wrong moment.
  (int priced, int total) templatePricingProgressFor(int shopId) {
    var priced = 0;
    var total = 0;
    for (final product in productsFor(shopId)) {
      // **basket rows, not template rows**: the comparison asks for a price on exactly these, and a
      // product added to the template later starts outside it - counting it would tell an owner who
      // is in the comparison that they are one price short of it
      if (!product.isTemplate || !product.inBasket) continue;
      total++;
      if (product.hasPrice) priced++;
    }
    return (priced, total);
  }

  /// [force] re-fetches a shop already in the cache, which is what a pull-to-refresh wants.
  Future<void> loadProducts(int shopId, {bool force = false}) async {
    // a second call while one is in flight is a no-op
    if (_loadingShopIds.contains(shopId)) return;
    if (!force && _byShop.containsKey(shopId) && !_stale.contains(shopId)) {
      return;
    }

    _loadingShopIds.add(shopId);
    _failedLoads.remove(shopId);
    notifyListeners();

    try {
      _byShop[shopId] = await _repo.fetchShopProducts(shopId);
      _stale.remove(shopId);
    } catch (e) {
      _failedLoads.add(shopId);
      debugPrint('loadProducts failed for shop $shopId: $e');
    }

    _loadingShopIds.remove(shopId);
    notifyListeners();
  }

  /// returns the saved product on success, null on failure ([saveError] then holds the reason) -
  /// which is what lets the caller pop back to a grid that is already correct instead of re-fetching
  Future<Product?> addProduct({
    required int shopId,
    required Product draft,
  }) async {
    return _mutate(() async {
      final created = await _repo.createProduct(shopId: shopId, draft: draft);
      // appended, not re-fetched: the backend orders template rows first and the owner's own after, so a
      // new custom product belongs exactly at the end - the one place the local list can be updated
      // without guessing at the server's ordering
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

  /// Attaches a photo to a product that already exists. [filePath] is what `image_picker` handed
  /// back - a file in the app's own cache, already re-encoded to jpeg at the size asked for.
  Future<Product?> uploadProductPhoto({
    required Product product,
    required String filePath,
  }) {
    return _mutatePhoto(
      () => _repo.uploadProductImage(productId: product.id, filePath: filePath),
    );
  }

  /// Removes it again. The product comes back carrying whatever photo it *should* have now, which for
  /// a template row is the catalogue's own shot - so this is not always "the tile goes blank".
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

  /// Swap one product in the cache for the version the server just returned. The grid, the map sheet
  /// and the edit screen all read the same list, so a product is replaced in one place.
  void _replaceInCache(Product saved) {
    _byShop[saved.shopId] = [
      for (final p in productsFor(saved.shopId)) p.id == saved.id ? saved : p,
    ];
  }

  // the same shape as _mutate below, against the photo's own flags. six duplicated lines rather than
  // a parameter, because the two sets of state exist precisely so a photo failing and a save failing
  // are two different things on screen.
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
      _photoError = ProductMutationException(
        code: 'timeout',
        message: e.toString(),
      );
    } catch (e) {
      // the real exception goes to the log rather than into a `message` field nothing renders
      debugPrint(
        'ProductsController: unexpected error during a photo upload: $e',
      );
      _photoError = ProductMutationException(
        code: 'server_error',
        message: e.toString(),
      );
    }

    _isPhotoBusy = false;
    notifyListeners();
    return result;
  }

  // the three mutations differ only in the request they make and how they patch the local list;
  // everything around that is identical, so it lives here once
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
      // its own code: "did not come back in ten seconds" is nearly always transient and the advice is to
      // press save again, which is the opposite of what a generic failure message suggests
      _saveError = ProductMutationException(
        code: 'timeout',
        message: e.toString(),
      );
    } catch (e) {
      // **the real exception used to end here and go no further** - stored in `message`, which nothing
      // renders, while the ui printed the switch's default and blamed the user's connection. logging it
      // is what makes the next one ten minutes of `adb logcat`.
      debugPrint('ProductsController: unexpected error during mutation: $e');
      _saveError = ProductMutationException(
        code: 'server_error',
        message: e.toString(),
      );
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  /// called by the edit screen as it opens, so a failure from a previous visit does not paint an error
  /// over a form nothing has been submitted from. silent: notifying mid-build trips the build guard.
  void resetSaveState() {
    _isSaving = false;
    _saveError = null;
    _isPhotoBusy = false;
    _photoError = null;
  }

  /// drop a deleted shop's catalogue - otherwise an id postgres reuses later would serve its rows to
  /// the wrong shop
  void forgetShop(int shopId) {
    _byShop.remove(shopId);
    _stale.remove(shopId);
    _failedLoads.remove(shopId);
  }
}
