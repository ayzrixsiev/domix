import 'package:flutter/foundation.dart';

import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_repository.dart';
import 'package:frontend/features/home/data/home_showcase_content.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// The viewmodel behind the home screen's three sections.
///
/// **Where the showcase substitution happens, and why it happens here.** The widgets take
/// [HomeShopPreview] and have no idea whether a row came from Postgres or from
/// `home_showcase_content.dart`. That was the design goal: fallback logic spread across three
/// widgets would be three places to remember to delete, and one of them would survive into
/// production. It is one `if` in [_applyContent] instead, and removing it is what "get rid of the
/// templates" means.
class HomeController extends ChangeNotifier {
  HomeController({HomeRepository? repository}) : _repo = repository ?? HomeRepository();

  final HomeRepository _repo;

  List<HomeShopPreview> _vipShops = const [];
  List<CategoryOffers> _bestOffers = const [];

  bool _isLoading = false;
  String? _loadError;
  bool _hasLoaded = false;
  bool _isShowingShowcase = false;

  List<HomeShopPreview> get vipShops => _vipShops;
  /// One entry per shop category with ranked shops - the tabs of "Лучшие предложения". Empty
  /// categories never appear, so a strip of dead tabs is impossible by construction.
  List<CategoryOffers> get bestOffers => _bestOffers;

  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  /// True once a load has finished, successfully or not. The screen uses it to tell "still starting
  /// up" from "genuinely has nothing", which are different things to draw.
  bool get hasLoaded => _hasLoaded;

  /// True when what is on screen is invented. Nothing renders differently because of it today, but
  /// it is the flag a "демо-данные" banner would hang off, and it makes the state visible to anyone
  /// debugging why the home screen disagrees with the map.
  bool get isShowingShowcase => _isShowingShowcase;

  /// [force] re-fetches even when content is already held, which is what a pull-to-refresh wants.
  Future<void> loadHome({bool force = false}) async {
    if (_isLoading) return; // a second call while one is in flight is a no-op
    if (!force && _hasLoaded && _loadError == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      _applyContent(await _repo.fetchHomeContent());
      _loadError = null;
    } catch (e) {
      _loadError = e.toString().replaceAll('Exception: ', '');
      // an unreachable backend is the other case the showcase covers, and it is the one that shows
      // up in a demo on bad wifi. without this the screen would be three error states, which is a
      // worse answer than three plausible ones while the real cause sits in loadError.
      _applyShowcase();
    }

    _isLoading = false;
    _hasLoaded = true;
    notifyListeners();
  }

  /// The whole of the temporary behaviour, in one place.
  ///
  /// All-or-nothing on purpose: the showcase stands in only when the backend has *no* shops to
  /// rank. Topping a real list up with invented rows would put two kinds of thing in one list with
  /// nothing distinguishing them, which is how a demo turns into a bug report.
  void _applyContent(HomeContent content) {
    if (kShowcaseFallbackEnabled && content.hasNoShops) {
      _applyShowcase();
      return;
    }

    _vipShops = content.vipShops;
    _bestOffers = content.bestOffers;
    _isShowingShowcase = false;
  }

  void _applyShowcase() {
    if (!kShowcaseFallbackEnabled) {
      // production: an empty screen is the truth, and the empty states are built for it
      _vipShops = const [];
      _bestOffers = const [];
      _isShowingShowcase = false;
      return;
    }

    _vipShops = kShowcaseVipShops;
    _bestOffers = kShowcaseBestOffers;
    _isShowingShowcase = true;
  }

  /// The products behind one category tile, cheapest first.
  ///
  /// Not cached and not stored on the controller: this is a screen someone opens, reads and leaves,
  /// and caching it would mean deciding when a price is stale. It returns its result instead of
  /// setting state, so the category screen owns its own loading and error handling rather than
  /// sharing fields with the home screen - the same separation StoresController keeps between the
  /// map's list and the owner's list.
  Future<List<CategoryProduct>> productsForCategory(ProductCategory category) async {
    if (_isShowingShowcase) return showcaseProductsForCategory(category);
    return _repo.fetchProductsByCategory(category);
  }
}
