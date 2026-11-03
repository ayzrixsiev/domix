// The heart on a product tile. Two things are worth pinning: it is painted from the controller
// rather than from local widget state, and a tap that fails puts it back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/favorites/data/favorites_repository.dart';
import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';

final _strings = AppLocalizations(AppLanguage.ru);

const _product = Product(
  id: 7,
  shopId: 1,
  name: 'Цемент М400',
  category: 'mixes',
  unit: 'мешок',
  price: 52000,
  availability: ProductAvailability.inStock,
  isTemplate: true,
  nameEditable: false,
);

final _entry = CategoryProduct(product: _product, shopName: 'Qurilish Baza');

/// Answers without a network. `fails` is the dropped-request case the optimistic paint has to undo.
class _FakeRepository implements FavoritesRepository {
  _FakeRepository({this.fails = false});

  final bool fails;
  final List<({int id, bool saved})> calls = [];

  @override
  Future<List<CategoryProduct>> fetchFavorites() async => const [];

  @override
  Future<void> setFavorite(int productId, {required bool saved}) async {
    calls.add((id: productId, saved: saved));
    if (fails) throw Exception('no connection');
  }
}

Future<FavoritesController> _pumpTile(
  WidgetTester tester, {
  required FavoritesController controller,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider<FavoritesController>.value(value: controller),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ProductTile(
              product: _product,
              strings: _strings,
              showBuyerActions: true,
              isFavorite: context.watch<FavoritesController>().contains(
                _product.id,
              ),
              onFavoriteToggle: () =>
                  context.read<FavoritesController>().toggle(_entry),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Color _heartColour(WidgetTester tester) {
  final heart = tester.widget<Icon>(
    find.descendant(
      of: find.bySemanticsLabel(_strings.addToFavouritesLabel),
      matching: find.byType(Icon),
    ),
  );
  return heart.color!;
}

void main() {
  testWidgets('tapping the heart fills it and saves the product', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = FavoritesController(repository: repository);

    await _pumpTile(tester, controller: controller);
    final unsaved = _heartColour(tester);

    await tester.tap(find.bySemanticsLabel(_strings.addToFavouritesLabel));
    await tester.pumpAndSettle();

    expect(
      _heartColour(tester),
      isNot(unsaved),
      reason: 'the heart did not change',
    );
    expect(controller.contains(_product.id), isTrue);
    expect(repository.calls, [(id: 7, saved: true)]);
  });

  // **the heart moves before the request lands**, so a refusal has to be undone or the app would be
  // showing a favourite the server never took
  testWidgets('a refused save puts the heart back', (tester) async {
    final controller = FavoritesController(
      repository: _FakeRepository(fails: true),
    );

    await _pumpTile(tester, controller: controller);
    final unsaved = _heartColour(tester);

    await tester.tap(find.bySemanticsLabel(_strings.addToFavouritesLabel));
    await tester.pumpAndSettle();

    expect(_heartColour(tester), unsaved);
    expect(controller.contains(_product.id), isFalse);
  });
}
