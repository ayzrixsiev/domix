// Placeholder content for the home screen, gathered in one file so the eventual swap to real
// backend data is a single-file change instead of a hunt through widget build methods.
//
// This used to live inline in each widget as `List<Map<String, dynamic>>` with casts like
// `cat['icon'] as IconData` at the read site. That shape has no compile-time safety at all: a
// mistyped key or a wrong type is a crash at runtime rather than an error in the editor. Typed
// models below cost a few lines and remove that entire class of bug.

/// A shop as the home screen previews it.
///
/// Deliberately separate from `features/stores`' `Shop`, which is the real backend model - these
/// have no id, no coordinates and are never sent anywhere. Keeping them a distinct type stops
/// placeholder rows from being passed to code that expects a persisted shop.
class HomeShopPreview {
  const HomeShopPreview({
    required this.name,
    required this.address,
    required this.rating,
    required this.averagePaycheck,
  });

  final String name;
  final String address;
  final double rating;

  /// in so'm - formatted for display by `AppLocalizations.somAmount`, so the currency word follows
  /// the selected language instead of being baked into the string
  final int averagePaycheck;
}

/// A construction category tile on the home grid.
///
/// The label is *not* stored here: it's resolved per-language from `AppLocalizations`, because
/// these were previously hardcoded Russian strings and stayed Russian when the app switched to
/// Uzbek. The enum is what the widget switches over to pick both the label and the icon/tint.
enum HomeCategory { mixes, blocks, fasteners, roofing, electrical, plumbing, paints, tools }

/// The paid/featured placement tier behind the "VIP Магазины" carousel.
///
/// Curated, never derived: which shops are VIP is a commercial decision, so unlike [kBestOffers]
/// below there is no rule that could compute this list.
const List<HomeShopPreview> kVipShops = [
  HomeShopPreview(
    name: 'СтройМастер',
    address: 'Юнусабадский р-н, ул. Амира Темура, 45',
    rating: 4.9,
    averagePaycheck: 1500000,
  ),
  HomeShopPreview(
    name: 'МегаСтрой',
    address: 'Мирзо-Улугбекский р-н, ул. Буюк Ипак Йули',
    rating: 4.8,
    averagePaycheck: 850000,
  ),
  HomeShopPreview(
    name: 'ДомСтрой',
    address: 'Алмазарский р-н, пр. Бунёдкор, 12',
    rating: 4.7,
    averagePaycheck: 720000,
  ),
  HomeShopPreview(
    name: 'РемонтПлюс',
    address: 'Чиланзар, ул. Шахрисабз, 7',
    rating: 4.6,
    averagePaycheck: 950000,
  ),
  HomeShopPreview(
    name: 'Профиль Групп',
    address: 'Сергелийский р-н, ул. Янги Сергели, 3',
    rating: 4.8,
    averagePaycheck: 1150000,
  ),
];

/// Everything else the catalogue knows about, i.e. the non-VIP shops.
///
/// Private because no screen shows "the shops that aren't VIP" - it exists only to be folded into
/// [kAllShops] below.
const List<HomeShopPreview> _standardShops = [
  HomeShopPreview(
    name: 'СантехОпт',
    address: 'ул. Мукими',
    rating: 4.7,
    averagePaycheck: 500000,
  ),
  HomeShopPreview(
    name: 'ЭлектроМир',
    address: 'ул. Катартал',
    rating: 4.9,
    averagePaycheck: 1200000,
  ),
  HomeShopPreview(
    name: 'Кровля Плюс',
    address: 'Чиланзар-2',
    rating: 4.6,
    averagePaycheck: 4500000,
  ),
  HomeShopPreview(
    name: 'ЦементЦентр',
    address: 'ул. Чапаната',
    rating: 4.8,
    averagePaycheck: 900000,
  ),
  HomeShopPreview(
    name: 'Прораб Маркет',
    address: 'Актепа',
    rating: 5.0,
    averagePaycheck: 2100000,
  ),
  HomeShopPreview(
    name: 'Инструменты24',
    address: 'проспект Bunyodkor',
    rating: 4.5,
    averagePaycheck: 650000,
  ),
];

/// Every shop the app knows about. VIP is a placement tier, not a separate catalogue, so VIP shops
/// are in here too and can win a spot in [kBestOffers] on price like anyone else.
const List<HomeShopPreview> kAllShops = [...kVipShops, ..._standardShops];

/// how many shops the "Лучшие предложения" section shows
const int kBestOffersLimit = 10;

/// The cheapest shops in the catalogue, cheapest first.
///
/// This replaced a hand-written "shops near you" list, and the difference matters: that one was a
/// fixed list ordered by distance, this one is *derived* from every shop by average check. There is
/// no location input at all - a shop qualifies on price, wherever it is.
///
/// `final`, not `const`: the sort runs at startup, and a sorted list is not a compile-time constant.
/// It is computed once when the library loads rather than per rebuild.
final List<HomeShopPreview> kBestOffers = _cheapestFirst(kAllShops, kBestOffersLimit);

List<HomeShopPreview> _cheapestFirst(List<HomeShopPreview> shops, int limit) {
  // sort a copy - `sort` mutates in place, and sorting kAllShops itself would reorder the source
  // list every other reader shares
  final ranked = [...shops]
    ..sort((a, b) => a.averagePaycheck.compareTo(b.averagePaycheck));
  return ranked.take(limit).toList(growable: false);
}
