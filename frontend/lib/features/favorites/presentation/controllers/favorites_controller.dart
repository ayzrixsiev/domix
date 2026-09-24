import 'package:flutter/foundation.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/favorites/data/favorites_repository.dart';
import 'package:frontend/features/home/data/category_product.dart';

/// The saved products, and the set of ids every grid paints its hearts from.
///
/// **One list serves both.** A per-product "is this saved" field on the API would make every product
/// response depend on who is asking, which would take the browsing reads out of the backend's cache -
/// so the app holds the answer instead and asks once per session.
class FavoritesController extends ChangeNotifier {
  FavoritesController({FavoritesRepository? repository})
      : _repository = repository ?? FavoritesRepository();

  final FavoritesRepository _repository;

  List<CategoryProduct> _items = const [];
  Set<int> _ids = const {};
  bool _loading = false;
  LoadFailure? _failure;

  List<CategoryProduct> get items => _items;
  bool get isLoading => _loading;
  LoadFailure? get failure => _failure;

  bool contains(int productId) => _ids.contains(productId);

  Future<void> load() async {
    _loading = true;
    _failure = null;
    notifyListeners();

    try {
      _items = await _repository.fetchFavorites();
      _ids = {for (final item in _items) item.product.id};
    } catch (error) {
      debugPrint('favorites: load failed ($error)');
      _failure = LoadFailure.of(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// **The heart moves first and the request follows.** A tap that waited for a round trip would feel
  /// broken on a slow connection; a tap that lied would be worse, so a refused request puts it back.
  ///
  /// The saved *card* only appears in the list on the next [load] - adding one here would mean
  /// carrying a product this controller was never given.
  Future<void> toggle(CategoryProduct item) async {
    final id = item.product.id;
    final saving = !_ids.contains(id);

    _apply(id, saving, item);
    notifyListeners();

    try {
      await _repository.setFavorite(id, saved: saving);
    } catch (error) {
      debugPrint('favorites: toggle failed ($error)');
      _apply(id, !saving, item);
      notifyListeners();
    }
  }

  void _apply(int id, bool saving, CategoryProduct item) {
    final ids = Set<int>.of(_ids);
    if (saving) {
      ids.add(id);
      _items = [item, ..._items.where((existing) => existing.product.id != id)];
    } else {
      ids.remove(id);
      _items = [for (final existing in _items) if (existing.product.id != id) existing];
    }
    _ids = ids;
  }

  /// Signing out or deleting the account: these are somebody's saved products, and the next person
  /// on this phone must not be handed them.
  void handleSessionEnded() {
    if (_items.isEmpty && _ids.isEmpty) return;
    _items = const [];
    _ids = const {};
    _failure = null;
    notifyListeners();
  }
}
