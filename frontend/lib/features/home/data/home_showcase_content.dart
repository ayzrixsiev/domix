// Fake shops, shown only while the real database has none.
//
// **This whole file is temporary.** It exists so the home screen has something to look like during
// development and demos - an app whose first screen is three empty states does not demo. Going to
// production is meant to be: flip [kShowcaseFallbackEnabled] to false, confirm the screen still
// works, then delete this file and the two imports of it. Nothing else references these rows, and
// no widget knows they exist - the controller substitutes them behind [HomeShopPreview], which is
// the same type real shops arrive as.
//
// The rule the controller follows is deliberately all-or-nothing: showcase rows appear only when a
// section is *completely* empty. Two real shops padded out with three invented ones would be the
// worst of both, because nothing on screen would say which was which.
//
// This replaced `home_placeholder_content.dart`, which held the same data but was read directly by
// the widgets - so there was no path for real data to reach them at all.

import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/data/product_category.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// The one switch. False makes the home screen show exactly what the backend returns, empty
/// sections included, which is what production wants.
const bool kShowcaseFallbackEnabled = true;

/// how many shops "Лучшие предложения" shows. Mirrors `bestOffersLimit` in the Go handler - it is
/// only used to trim the showcase list, since the real list arrives already trimmed by the server.
const int kBestOffersLimit = 10;

// The shops. VIP is a flag on the shop rather than a separate list, exactly as it is in the
// database, so the carousel is a filter over one catalogue rather than a second catalogue that
// could disagree with the first.
//
// Each carries a *basket price* and no index, because the index is not a property of one shop -
// it is that shop's basket divided by the market's average basket, so it cannot exist until all
// eleven are known. It is computed below by the same three steps the SQL view performs, which is
// what keeps the showcase a demonstration of the real mechanism rather than a picture of it.

const _stroymaster = HomeShopPreview(
  name: 'СтройМастер',
  address: 'Юнусабадский р-н, ул. Амира Темура, 45',
  rating: 4.9,
  basketPrice: 5200000,
  isVip: true,
);

const _megastroy = HomeShopPreview(
  name: 'МегаСтрой',
  address: 'Мирзо-Улугбекский р-н, ул. Буюк Ипак Йули',
  rating: 4.8,
  basketPrice: 4750000,
  isVip: true,
);

const _domstroy = HomeShopPreview(
  name: 'ДомСтрой',
  address: 'Алмазарский р-н, пр. Бунёдкор, 12',
  rating: 4.7,
  basketPrice: 4900000,
  isVip: true,
);

const _remontplus = HomeShopPreview(
  name: 'РемонтПлюс',
  address: 'Чиланзар, ул. Шахрисабз, 7',
  rating: 4.6,
  basketPrice: 5050000,
  isVip: true,
);

const _profilGroup = HomeShopPreview(
  name: 'Профиль Групп',
  address: 'Сергелийский р-н, ул. Янги Сергели, 3',
  rating: 4.8,
  basketPrice: 5400000,
  isVip: true,
);

const _santehopt = HomeShopPreview(
  name: 'СантехОпт',
  address: 'ул. Мукими',
  rating: 4.7,
  basketPrice: 4300000,
);

const _elektromir = HomeShopPreview(
  name: 'ЭлектроМир',
  address: 'ул. Катартал',
  rating: 4.9,
  basketPrice: 5600000,
);

const _krovlyaPlus = HomeShopPreview(
  name: 'Кровля Плюс',
  address: 'Чиланзар-2',
  rating: 4.6,
  basketPrice: 4600000,
);

const _cementCentre = HomeShopPreview(
  name: 'ЦементЦентр',
  address: 'ул. Чапаната',
  rating: 4.8,
  basketPrice: 4450000,
);

const _prorabMarket = HomeShopPreview(
  name: 'Прораб Маркет',
  address: 'Актепа',
  rating: 5.0,
  basketPrice: 5900000,
);

const _instrumenty24 = HomeShopPreview(
  name: 'Инструменты24',
  address: 'проспект Bunyodkor',
  rating: 4.5,
  basketPrice: 4850000,
);

/// Which showcase shops sell what.
///
/// One map rather than a hand-written count per tile *and* a hand-written list per category: the
/// tile's number is this map's list length, so the two can never disagree. That is the same
/// relationship the real data has - the backend counts the shops it would return - so the showcase
/// behaves like the thing it stands in for rather than merely looking like it.
const Map<ProductCategory, List<HomeShopPreview>> _showcaseCatalogue = {
  ProductCategory.mixes: [_cementCentre, _stroymaster, _megastroy, _prorabMarket],
  ProductCategory.blocks: [_cementCentre, _stroymaster, _domstroy],
  ProductCategory.lumber: [_domstroy, _prorabMarket],
  ProductCategory.metal: [_profilGroup, _megastroy, _prorabMarket],
  ProductCategory.fasteners: [_instrumenty24, _stroymaster, _megastroy, _prorabMarket],
  ProductCategory.roofing: [_krovlyaPlus, _profilGroup],
  ProductCategory.insulation: [_krovlyaPlus, _megastroy],
  ProductCategory.electrical: [_elektromir, _stroymaster],
  ProductCategory.plumbing: [_santehopt, _remontplus, _megastroy],
  ProductCategory.paints: [_remontplus, _stroymaster],
  ProductCategory.finishing: [_remontplus, _domstroy, _stroymaster],
  ProductCategory.tools: [_instrumenty24, _prorabMarket],
};

/// How many items a showcase basket holds - the size of the Универсальный template. Only used to
/// turn a basket total back into a plausible per-item price for the category drill-down.
const int _showcaseBasketItems = 100;

/// Which shop category each showcase shop belongs to - the tabs of "Лучшие предложения".
///
/// Deliberately uneven, so the strip demonstrates more than one shape: four shops in one tab, two
/// in another. Each tab is its own market, and a shop is compared only against the others in its
/// own list.
const Map<ShopCategory, List<HomeShopPreview>> _showcaseByShopCategory = {
  ShopCategory.universal: [_stroymaster, _megastroy, _domstroy, _prorabMarket],
  ShopCategory.plumbing: [_santehopt, _remontplus, _elektromir],
  ShopCategory.wood: [_profilGroup, _instrumenty24],
  ShopCategory.wallpaper: [_krovlyaPlus, _cementCentre],
};

/// Every showcase shop, deduplicated - the product catalogue above lists most of them several
/// times.
///
/// Deduplication works by identity: `_stroymaster` appearing in four category lists is the same
/// `const` object four times, and `Set` falls back to identity where a type has no `==`. That is
/// also why the tier has to be attached *after* this step - mapping first would produce four
/// distinct objects and dedup nothing.
///
/// `final` and not `const`: a Set built at runtime is not a compile-time constant. It is computed
/// once when the library loads, not per rebuild.
final List<HomeShopPreview> _allShowcaseShops = {
  for (final shops in _showcaseCatalogue.values) ...shops,
}.toList(growable: false);

/// Every shop with its tier attached, keyed by name so the derived lists below can look one up from
/// the bare `const` they hold.
///
/// This runs the same three steps the SQL view runs, per shop category: total each basket, average
/// the totals across that category, divide. The showcase behaves like the mechanism it stands in
/// for rather than like a picture of it, which is what stops a hand-typed badge from disagreeing
/// with the basket printed next to it.
final Map<String, HomeShopPreview> _ranked = {
  for (final entry in _showcaseByShopCategory.entries)
    for (final shop in entry.value) shop.name: _withTier(shop, entry.value),
};

HomeShopPreview _withTier(HomeShopPreview shop, List<HomeShopPreview> market) {
  final average = market
          .map((s) => s.basketPrice!)
          .reduce((total, basket) => total + basket) /
      market.length;
  final index = (shop.basketPrice! / average * 100).round();

  return HomeShopPreview(
    name: shop.name,
    address: shop.address,
    rating: shop.rating,
    basketPrice: shop.basketPrice,
    priceTier: _tierFor(index),
    priceDifferencePercent: (index - 100).abs(),
    isVip: shop.isVip,
  );
}

/// The same band as `internal/pricing`: below 98 cheap, above 102 dear, the rest average.
PriceTier _tierFor(int index) {
  if (index < 98) return PriceTier.cheaper;
  if (index > 102) return PriceTier.dearer;
  return PriceTier.average;
}

HomeShopPreview _indexed(HomeShopPreview shop) => _ranked[shop.name]!;

/// The VIP carousel's showcase rows - a filter over the one catalogue, mirroring
/// `WHERE vip_until > now()` in `ListVipShops`.
final List<HomeShopPreview> kShowcaseVipShops = _allShowcaseShops
    .where((shop) => shop.isVip)
    .map(_indexed)
    .toList(growable: false);

/// "Лучшие предложения", one tab per shop category, each ranked cheapest first - the client-side
/// twin of calling `ListBestOffersInCategory` once per category.
final List<CategoryOffers> kShowcaseBestOffers = [
  for (final entry in _showcaseByShopCategory.entries)
    CategoryOffers(
      category: entry.key,
      shops: _cheapestFirst(
        entry.value.map(_indexed).toList(),
        (shop) => shop.basketPrice,
        kBestOffersLimit,
      ),
    ),
];

/// Two plausible product names per category, so a tapped tile opens onto something that looks like
/// a catalogue rather than one lonely tile.
///
/// Crossed with the shops that "sell" each category below, which is what keeps the drill-down
/// consistent with `_showcaseCatalogue` - the same relationship the real data has, where the
/// products a category query returns belong to the shops that stock it.
const Map<ProductCategory, List<String>> _showcaseProductNames = {
  ProductCategory.mixes: ['Цемент М400, 50 кг', 'Плиточный клей, 25 кг'],
  ProductCategory.blocks: ['Кирпич керамический', 'Газоблок 600x300x200'],
  ProductCategory.lumber: ['Доска обрезная 50x150', 'Фанера ФК 10 мм'],
  ProductCategory.metal: ['Арматура 12 мм', 'Профнастил С8'],
  ProductCategory.fasteners: ['Саморезы 4x50, 1 кг', 'Анкер клиновой 10x100'],
  ProductCategory.roofing: ['Металлочерепица', 'Ондулин лист'],
  ProductCategory.insulation: ['Минвата 50 мм', 'Пенопласт ППС-15'],
  ProductCategory.electrical: ['Кабель ВВГ 3x2.5', 'Автомат 16А'],
  ProductCategory.plumbing: ['Труба ПВХ 20 мм', 'Смеситель для кухни'],
  ProductCategory.paints: ['Краска водоэмульсионная 10 л', 'Грунтовка глубокого проникновения'],
  ProductCategory.finishing: ['Гипсокартон 12.5 мм', 'Плинтус напольный'],
  ProductCategory.tools: ['Перфоратор 800 Вт', 'Шуруповёрт аккумуляторный'],
};

/// The showcase drill-down: the products a category tile opens onto, cheapest first.
///
/// Prices are derived from the shop's basket rather than invented per product, so a shop that is
/// cheap on the home screen is also cheap here. A showcase whose two screens disagreed about which
/// shop is cheapest would be teaching the reader something untrue about the app.
List<CategoryProduct> showcaseProductsForCategory(ProductCategory category) {
  final shops = _showcaseCatalogue[category] ?? const <HomeShopPreview>[];
  final names = _showcaseProductNames[category] ?? const <String>[];

  final products = <CategoryProduct>[];
  var id = 1;
  for (final shop in shops) {
    for (var i = 0; i < names.length; i++) {
      // the shop's per-item average, nudged so the two products of one shop are not identical
      final unit = shop.basketPrice! ~/ _showcaseBasketItems;
      products.add(
        CategoryProduct(
          shopName: shop.name,
          product: Product(
            id: id++,
            shopId: 0,
            name: names[i],
            category: category.code,
            unit: i.isEven ? 'шт' : 'упак',
            price: unit + i * (unit ~/ 4),
            availability: ProductAvailability.inStock,
            isTemplate: true,
            // none of the showcase categories are обои, so no showcase row is a slot
            nameEditable: false,
          ),
        ),
      );
    }
  }

  products.sort((a, b) => a.product.price!.compareTo(b.product.price!));
  return products;
}

/// Ranks by whichever number the caller's screen actually shows, ascending.
///
/// The comparison is passed in rather than hardcoded because the two lists rank on different
/// quantities - a basket total within one shop category for the home screen, a per-item price for
/// the drill-down - and a function that guessed which one to use from whichever field happened to
/// be non-null would silently pick the wrong one the moment a row carried both.
///
/// Ranking a tab by its basket totals rather than by the index is not a shortcut: within one shop
/// category every basket holds the same items, so the two orderings are identical. Across
/// categories they are not, which is exactly why the section is tabbed.
List<HomeShopPreview> _cheapestFirst(
  List<HomeShopPreview> shops,
  int? Function(HomeShopPreview) rankBy,
  int limit,
) {
  // sorts a copy - `sort` mutates in place, and sorting the source would reorder the list every
  // other reader shares
  final ranked = [...shops]..sort((a, b) {
      // a shop with nothing to rank on sorts last rather than first. none of the showcase rows are
      // in that state, but the real list is filtered server-side and this keeps the two orderings
      // meaning the same thing.
      final left = rankBy(a);
      final right = rankBy(b);
      if (left == null) return right == null ? 0 : 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
  return ranked.take(limit).toList(growable: false);
}
