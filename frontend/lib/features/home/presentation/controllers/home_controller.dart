import 'package:flutter/foundation.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_repository.dart';
import 'package:frontend/features/products/data/product_category.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// The viewmodel behind the home screen's three sections. **There is no fallback content**: what
/// the screen shows is what the database holds, and an empty slot says so plainly.
class HomeController extends ChangeNotifier {
  HomeController({HomeRepository? repository})
    : _repo = repository ?? HomeRepository();

  final HomeRepository _repo;

  List<HomeShopPreview> _vipShops = const [];
  List<CategoryOffers> _bestOffers = const [];
  Map<ShopCategory, int> _templateSizes = const {};

  bool _isLoading = false;
  LoadFailure? _failure;
  bool _hasLoaded = false;

  /// the shops holding a live paid placement, cheapest basket first (an unpriced one last) - only
  /// ever the real ones. the carousel is what arranges them into its slots.
  List<HomeShopPreview> get vipShops => _vipShops;

  /// one entry per category with ranked shops, so a strip of dead tabs is impossible by construction
  List<CategoryOffers> get bestOffers => _bestOffers;

  /// read by the "add shop" form; kept across a failed reload, since a template size does not go stale
  /// the way a price does
  Map<ShopCategory, int> get templateSizes => _templateSizes;

  bool get isLoading => _isLoading;

  /// **the kind, not a message** - the screen owns the sentence, and the exception is a debugPrint
  LoadFailure? get failure => _failure;

  /// tells "still starting up" from "genuinely has nothing", which are different things to draw
  bool get hasLoaded => _hasLoaded;

  /// [force] re-fetches even when content is already held, which is what a pull-to-refresh wants.
  Future<void> loadHome({bool force = false}) async {
    if (_isLoading) return; // a second call while one is in flight is a no-op
    if (!force && _hasLoaded && _failure == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final content = await _repo.fetchHomeContent();
      _vipShops = content.vipShops;
      _bestOffers = content.bestOffers;
      _templateSizes = content.templateSizes;
      _failure = null;
    } catch (e) {
      // the sections are emptied as well: leaving the last successful load under a failure banner shows
      // prices from an unknown time ago as though they were current
      _vipShops = const [];
      _bestOffers = const [];
      // **the flag is the state; the exception is a log line** - it used to be the error card's subtitle,
      // which put a raw ClientException in front of a customer looking for cement
      debugPrint('HomeController: could not load home content: $e');
      _failure = LoadFailure.of(e);
    }

    _isLoading = false;
    _hasLoaded = true;
    notifyListeners();
  }

  /// The products behind one category tile, cheapest first. Not cached and not stored on the
  /// controller - caching would mean deciding when a price is stale - and it returns its result rather
  /// than setting state, so a failure cannot paint an error over the home screen.
  Future<List<CategoryProduct>> productsForCategory(ProductCategory category) {
    return _repo.fetchProductsByCategory(category);
  }

  /// what the home screen's search field submits to. uncached and unstored for the same reasons.
  Future<List<CategoryProduct>> searchProducts(String query, {int offset = 0}) {
    return _repo.searchProducts(query, offset: offset);
  }

  /// the names under that field while it is being typed. the panel owns the debounce and the one
  /// answer it keeps, so there is nothing here to hold either.
  Future<List<String>> suggestProducts(String query) {
    return _repo.suggestProducts(query);
  }
}
