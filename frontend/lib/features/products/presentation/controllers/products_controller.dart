import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/product_model.dart';
import '../../data/products_repository.dart';

// viewmodel behind the two screens that show a shop's catalogue: the owner's management grid
// (ShopProductsScreen) and the customer-facing grid inside the map's shop sheet.
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
  final Map<int, String> _loadErrors = {};

  // the add/edit/delete form on ShopProductsScreen. one busy flag rather than one per product: only
  // one edit sheet is ever open at a time, and the screen disables its save/delete buttons together.
  bool _isSaving = false;
  ProductMutationException? _saveError;

  /// the shop's catalogue, or an empty list if it has never been loaded. `const []` and not a new
  /// list each call, so a widget rebuilding doesn't allocate and doesn't get a mutable view of
  /// nothing that it might try to add to.
  List<Product> productsFor(int shopId) => _byShop[shopId] ?? const [];

  bool isLoadingFor(int shopId) => _loadingShopIds.contains(shopId);
  String? loadErrorFor(int shopId) => _loadErrors[shopId];
  bool hasLoaded(int shopId) => _byShop.containsKey(shopId);

  bool get isSaving => _isSaving;
  ProductMutationException? get saveError => _saveError;

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
    _loadErrors.remove(shopId);
    notifyListeners();

    try {
      _byShop[shopId] = await _repo.fetchShopProducts(shopId);
    } catch (e) {
      _loadErrors[shopId] = e.toString();
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
      _byShop[product.shopId] = [
        for (final p in productsFor(product.shopId)) p.id == saved.id ? saved : p,
      ];
      return saved;
    });
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
  }

  /// drop a deleted shop's catalogue. without it the cache would hold rows for a shop that no
  /// longer exists, and an id reused by postgres later would serve them to the wrong shop.
  void forgetShop(int shopId) {
    _byShop.remove(shopId);
    _loadErrors.remove(shopId);
  }
}
