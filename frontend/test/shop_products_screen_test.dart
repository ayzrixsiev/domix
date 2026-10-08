// The owner's «Товары»: "Добавить товар" is pinned to the bottom of the screen rather than being the
// last cell of a hundred-tile grid, where it had to be scrolled to.

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/data/product_section.dart';
import 'package:frontend/features/products/data/products_repository.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/products/presentation/screens/shop_products_screen.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

class _FakeProductsRepository implements ProductsRepository {
  _FakeProductsRepository(this.products);

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

final _shop = Shop(
  id: 1,
  name: 'Стройбаза',
  contactPhone: '+998901112233',
  address: 'ул. Навои 12',
  category: ShopCategory.universal,
  latitude: 41.3,
  longitude: 69.2,
  priceTier: PriceTier.cheaper,
  priceDifferencePercent: 4,
  basketPrice: 4850000,
);

Product _product(int id, {bool template = true, ProductSection? section}) => Product(
  id: id,
  shopId: 1,
  name: 'Товар $id',
  specs: 'Описание $id',
  category: 'tools',
  unit: 'шт',
  price: null,
  availability: ProductAvailability.inStock,
  isTemplate: template,
  nameEditable: !template,
  section: section,
);

Future<void> _pump(WidgetTester tester, List<Product> products) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(
          create: (_) => ProductsController(repository: _FakeProductsRepository(products)),
        ),
      ],
      child: MaterialApp(home: ShopProductsScreen(shop: _shop)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final strings = AppLocalizations(AppLanguage.ru);

  testWidgets('the add button sits outside the scrolling grid, always on screen', (tester) async {
    await _pump(tester, [for (var i = 0; i < 40; i++) _product(i)]);

    expect(find.text(strings.addProductButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.text(strings.addProductButton),
      ),
      findsNothing,
      reason: 'it is pinned over the list, not a cell at the end of it',
    );

    // and it is still there after the list has been scrolled a long way
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text(strings.addProductButton), findsOneWidget);
  });

  testWidgets('a spent allowance greys the button out and says so on it', (tester) async {
    await _pump(tester, [
      _product(1),
      for (var i = 0; i < kMaxCustomProducts; i++) _product(100 + i, template: false),
    ]);

    expect(find.text(strings.addProductButton), findsNothing);
    expect(
      find.text(strings.ownProductsUsedLabel(kMaxCustomProducts, kMaxCustomProducts)),
      findsOneWidget,
    );
  });

  testWidgets('the header says what the screen is', (tester) async {
    await _pump(tester, [_product(1), _product(2)]);

    expect(find.text(strings.productsScreenTitle), findsOneWidget);
    expect(find.text(strings.productsScreenSubtitle), findsOneWidget);
  });

  testWidgets('two sections put the sections disc beside the search field', (tester) async {
    await _pump(tester, [
      _product(1, section: ProductSection.electricalLighting),
      _product(2, section: ProductSection.fastenersMounting),
    ]);

    expect(find.byIcon(LucideIcons.sliders_horizontal), findsOneWidget);

    // and it opens the sheet the chips used to duplicate
    await tester.tap(find.byIcon(LucideIcons.sliders_horizontal));
    await tester.pumpAndSettle();
    expect(find.text(strings.sectionsButton), findsOneWidget);
    expect(find.text(strings.sectionAll), findsOneWidget);
  });

  testWidgets('one section is nothing to choose between, so there is no disc', (tester) async {
    await _pump(tester, [_product(1, section: ProductSection.electricalLighting)]);

    expect(find.byIcon(LucideIcons.sliders_horizontal), findsNothing);
    // the field stays: searching a catalogue has nothing to do with how many sections it has
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the field on the page filters by name and description', (tester) async {
    await _pump(tester, [_product(1), _product(2)]);

    await tester.enterText(find.byType(TextField), 'Описание 2');
    await tester.pumpAndSettle();

    expect(find.text('Товар 2'), findsOneWidget);
    expect(find.text('Товар 1'), findsNothing);

    // clearing it puts the whole catalogue back
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    expect(find.text('Товар 1'), findsOneWidget);
  });
}
