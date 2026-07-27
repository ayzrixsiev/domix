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
    this.distanceKm,
  });

  final String name;
  final String address;
  final double rating;

  /// in so'm - formatted for display by `AppLocalizations.somAmount`, so the currency word follows
  /// the selected language instead of being baked into the string
  final int averagePaycheck;

  /// only the "nearby" list has a distance; the popular carousel leaves it null
  final double? distanceKm;
}

/// A construction category tile on the home grid.
///
/// The label is *not* stored here: it's resolved per-language from `AppLocalizations`, because
/// these were previously hardcoded Russian strings and stayed Russian when the app switched to
/// Uzbek. The enum is what the widget switches over to pick both the label and the icon/tint.
enum HomeCategory { concrete, cement, brick, rebar, foamBlock, roofing, paint, insulation }

const List<HomeShopPreview> kPopularShops = [
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
];

const List<HomeShopPreview> kNearbyShops = [
  HomeShopPreview(
    name: 'СантехОпт',
    address: 'ул. Мукими',
    rating: 4.7,
    averagePaycheck: 500000,
    distanceKm: 0.5,
  ),
  HomeShopPreview(
    name: 'ЭлектроМир',
    address: 'ул. Катартал',
    rating: 4.9,
    averagePaycheck: 1200000,
    distanceKm: 1.2,
  ),
  HomeShopPreview(
    name: 'Кровля Плюс',
    address: 'Чиланзар-2',
    rating: 4.6,
    averagePaycheck: 4500000,
    distanceKm: 1.8,
  ),
  HomeShopPreview(
    name: 'ЦементЦентр',
    address: 'ул. Чапаната',
    rating: 4.8,
    averagePaycheck: 900000,
    distanceKm: 2.1,
  ),
  HomeShopPreview(
    name: 'Прораб Маркет',
    address: 'Актепа',
    rating: 5.0,
    averagePaycheck: 2100000,
    distanceKm: 2.4,
  ),
  HomeShopPreview(
    name: 'Инструменты24',
    address: 'проспект Bunyodkor',
    rating: 4.5,
    averagePaycheck: 650000,
    distanceKm: 3.0,
  ),
];
