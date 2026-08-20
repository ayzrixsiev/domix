import 'package:flutter/foundation.dart';

import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_repository.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// The viewmodel behind the home screen's three sections.
///
/// **There is no fallback content any more, and there is nowhere for one to hide.** This class used
/// to substitute invented shops from `home_showcase_content.dart` whenever the backend came back
/// empty or unreachable, so the app would demo. That file and its one `if` are deleted: what the home
/// screen shows is what the database holds, and an empty VIP slot or an empty category says so
/// plainly. The substitution lived here rather than in the widgets precisely so that removing it
/// would be this small.
class HomeController extends ChangeNotifier {
  HomeController({HomeRepository? repository}) : _repo = repository ?? HomeRepository();

  final HomeRepository _repo;

  List<HomeShopPreview> _vipShops = const [];
  List<CategoryOffers> _bestOffers = const [];

  bool _isLoading = false;
  String? _loadError;
  bool _hasLoaded = false;

  /// The shops holding a live paid placement, in the backend's order - longest placement first. The
  /// carousel arranges them into its slots; this list is only ever the real ones.
  List<HomeShopPreview> get vipShops => _vipShops;

  /// One entry per shop category with ranked shops - the tabs of "Лучшие предложения". Empty
  /// categories never appear, so a strip of dead tabs is impossible by construction.
  List<CategoryOffers> get bestOffers => _bestOffers;

  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  /// True once a load has finished, successfully or not. The screen uses it to tell "still starting
  /// up" from "genuinely has nothing", which are different things to draw.
  bool get hasLoaded => _hasLoaded;

  /// [force] re-fetches even when content is already held, which is what a pull-to-refresh wants.
  Future<void> loadHome({bool force = false}) async {
    if (_isLoading) return; // a second call while one is in flight is a no-op
    if (!force && _hasLoaded && _loadError == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final content = await _repo.fetchHomeContent();
      _vipShops = content.vipShops;
      _bestOffers = content.bestOffers;
      _loadError = null;
    } catch (e) {
      // the sections are emptied as well as the error being recorded. leaving the last successful
      // load on screen under a failure banner would be showing prices from an unknown time ago as
      // though they were current - and this list is what a customer decides where to drive from.
      _vipShops = const [];
      _bestOffers = const [];
      _loadError = e.toString().replaceAll('Exception: ', '');
    }

    _isLoading = false;
    _hasLoaded = true;
    notifyListeners();
  }

  /// The products behind one category tile, cheapest first.
  ///
  /// Not cached and not stored on the controller: this is a screen someone opens, reads and leaves,
  /// and caching it would mean deciding when a price is stale. It returns its result instead of
  /// setting state, so the category screen owns its own loading and error handling rather than
  /// sharing fields with the home screen - the same separation StoresController keeps between the
  /// map's list and the owner's list.
  ///
  /// **Real products or nothing.** This used to answer from the showcase catalogue whenever the home
  /// screen was showing invented shops, which meant a tapped tile opened onto plausible product names
  /// at plausible prices from businesses that do not exist. A category nobody has priced anything in
  /// now returns an empty list, and `ProductResultsView` draws the empty state that already existed
  /// for it.
  Future<List<CategoryProduct>> productsForCategory(ProductCategory category) {
    return _repo.fetchProductsByCategory(category);
  }

  /// Products matching what the customer typed into the home screen's search field. Uncached and
  /// unstored for the same reasons as [productsForCategory], and against the same database.
  Future<List<CategoryProduct>> searchProducts(String query) {
    return _repo.searchProducts(query);
  }
}
