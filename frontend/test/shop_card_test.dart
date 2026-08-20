// One shop card, reached from three places.
//
// Before it existed only the map could open a shop, as a sheet built inside `map_screen.dart` - so a
// VIP card the founder had been paid to place, and every row of Лучшие предложения, was a tap that
// did nothing. That is a failure with no error anywhere: the app looks finished and simply ignores
// the finger. These pin the two routes into it, and the one row that must *not* open one.
//
// The empty-slot case is the subtle one. Both home sections draw a fixed number of places whether or
// not shops have filled them, so the feed is full of card-shaped things that are not shops - and an
// unsold VIP slot must stay inert rather than opening a card about a business that does not exist.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_repository.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/location/presentation/controllers/city_controller.dart';
import 'package:frontend/features/products/data/product_category.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/data/products_repository.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/screens/shop_card_screen.dart';

/// Stands in for the network. `implements` rather than a subclass, so the fake cannot accidentally
/// inherit a real http call the day one is added to the repository.
class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({required this.content});

  final HomeContent content;

  @override
  Future<HomeContent> fetchHomeContent() async => content;

  @override
  Future<List<CategoryProduct>> fetchProductsByCategory(ProductCategory category) async => const [];

  @override
  Future<List<CategoryProduct>> searchProducts(String query) async => const [];
}

class _FakeProductsRepository implements ProductsRepository {
  _FakeProductsRepository({this.products = const []});

  final List<Product> products;

  @override
  Future<List<Product>> fetchShopProducts(int shopId) async => products;

  @override
  Future<Product> createProduct({required int shopId, required Product draft}) async => draft;

  @override
  Future<Product> updateProduct(Product product) async => product;

  @override
  Future<void> deleteProduct(int productId) async {}

  @override
  Future<Product> uploadProductImage({required int productId, required String filePath}) async =>
      products.firstWhere((p) => p.id == productId);

  @override
  Future<Product> removeProductImage(int productId) async =>
      products.firstWhere((p) => p.id == productId);
}

Shop _shop({required int id, required String name, bool isVip = false}) {
  return Shop(
    id: id,
    name: name,
    contactPhone: '+998901112233',
    address: 'ул. Навои 12',
    category: ShopCategory.universal,
    latitude: 41.3,
    longitude: 69.2,
    rating: 0,
    priceTier: PriceTier.cheaper,
    priceDifferencePercent: 4,
    basketPrice: 4850000,
    isVip: isVip,
  );
}

Product _product({required int id, required String name, int? price}) {
  return Product(
    id: id,
    shopId: 1,
    name: name,
    category: 'tools',
    unit: 'шт',
    price: price,
    availability: ProductAvailability.inStock,
    isTemplate: true,
    nameEditable: false,
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required HomeContent content,
  List<Product> products = const [],
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => CityController()),
        ChangeNotifierProvider(
          create: (_) => HomeController(repository: _FakeHomeRepository(content: content)),
        ),
        ChangeNotifierProvider(
          create: (_) => ProductsController(
            repository: _FakeProductsRepository(products: products),
          ),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  // the feed loads from a post-frame callback, so one pump builds the frame and the settle lets the
  // future land
  await tester.pumpAndSettle();
}

HomeContent _content({List<Shop> vip = const [], List<Shop> offers = const []}) {
  return HomeContent(
    vipShops: [for (final s in vip) HomeShopPreview.fromShop(s)],
    bestOffers: [
      if (offers.isNotEmpty)
        CategoryOffers(
          category: ShopCategory.universal,
          shops: [for (final s in offers) HomeShopPreview.fromShop(s)],
        ),
    ],
  );
}

void main() {
  testWidgets('a VIP card opens the shop card', (tester) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'ВИП Стройбаза', isVip: true)]),
    );

    expect(find.byType(ShopCardScreen), findsNothing);

    // `.hitTestable()`, not `.first`: the carousel is an endless PageView, so with one shop the
    // same card is also built as the page either side of the viewport. `.first` picks one of those,
    // at a negative offset, and taps nothing.
    await tester.tap(find.text('ВИП Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();

    expect(find.byType(ShopCardScreen), findsOneWidget);
    // the two facts the sheet used to be opened for, and the reason a card exists at all
    expect(find.text('+998901112233'), findsOneWidget);
    expect(find.text('ул. Навои 12'), findsWidgets);
  });

  testWidgets('a Лучшие предложения row opens the same card', (tester) async {
    await _pumpHome(
      tester,
      content: _content(offers: [_shop(id: 2, name: 'Дешёвый Склад')]),
    );

    // scrolled to first: the VIP carousel is five permanent places now, so Лучшие предложения starts
    // below the fold and `tap` on an off-screen widget lands nowhere
    await tester.ensureVisible(find.text('Дешёвый Склад').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Дешёвый Склад').first);
    await tester.pumpAndSettle();

    expect(find.byType(ShopCardScreen), findsOneWidget);
    expect(find.text('Дешёвый Склад'), findsWidgets);
  });

  // an unsold VIP place is drawn as a card and is not one. tapping it must do nothing at all -
  // there is no shop behind it, and a route into an address nobody is at is worse than an inert card.
  testWidgets('an empty VIP slot opens nothing', (tester) async {
    final strings = AppLocalizations(AppLanguage.ru);
    await _pumpHome(tester, content: _content());

    // the label where a real card would carry the shop's name
    await tester.tap(find.text(strings.slotShopNameLabel).hitTestable().first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(ShopCardScreen), findsNothing);
  });

  // the customer-facing rule: an unpriced row is the *owner's* to-do list and answers nothing for a
  // buyer, so it is not on their card at all
  testWidgets('the card lists only the products that carry a price', (tester) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: [
        _product(id: 10, name: 'Цемент М400', price: 55000),
        _product(id: 11, name: 'Гипсокартон'),
      ],
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();

    expect(find.text('Цемент М400'), findsOneWidget);
    expect(find.text('Гипсокартон'), findsNothing);
    expect(find.byType(ProductTile), findsOneWidget);
  });
}
