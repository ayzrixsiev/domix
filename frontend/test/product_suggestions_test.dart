import 'dart:ui' show PointerDeviceKind;
// The as-you-type panel under the product search field, tested for the thing it exists to keep
// cheap: how many requests a typed word costs, and that an answer never contradicts the field.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_repository.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/screens/product_search_screen.dart';
import 'package:frontend/features/home/presentation/widgets/product_suggestions_panel.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// Stands in for the network, and keeps the log of what was asked for - the point of most of these
/// tests is a request that was *not* made.
class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({this.names = const []});

  final List<String> names;

  final List<String> suggested = [];
  final List<String> searched = [];

  @override
  Future<HomeContent> fetchHomeContent() async =>
      const HomeContent(vipShops: [], bestOffers: [], templateSizes: {});

  @override
  Future<List<CategoryProduct>> fetchProductsByCategory(
    ProductCategory category,
  ) async => const [];

  @override
  Future<List<CategoryProduct>> searchProducts(
    String query, {
    int offset = 0,
  }) async {
    searched.add(query);
    return const [];
  }

  @override
  Future<List<String>> suggestProducts(String query) async {
    suggested.add(query);
    return names;
  }
}

Future<_FakeHomeRepository> _pumpSearchScreen(
  WidgetTester tester,
  List<String> names,
) async {
  final repo = _FakeHomeRepository(names: names);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesController()),
        ChangeNotifierProvider(create: (_) => HomeController(repository: repo)),
      ],
      child: const MaterialApp(home: ProductSearchScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// types into the field and lets the debounce expire
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a word too short to look up costs no request', (tester) async {
    final repo = await _pumpSearchScreen(tester, ['Цемент М400']);

    await _type(tester, 'це');

    expect(repo.suggested, isEmpty);
    expect(find.byType(ProductSuggestionsPanel), findsOneWidget);
    expect(find.text('Цемент М400'), findsNothing);
  });

  testWidgets('three characters bring the names under the field', (
    tester,
  ) async {
    final repo = await _pumpSearchScreen(tester, [
      'Цемент М400',
      'Цемент М500',
    ]);

    await _type(tester, 'цем');

    expect(repo.suggested, ['цем']);
    expect(find.text('Цемент М400'), findsOneWidget);
    expect(find.text('Цемент М500'), findsOneWidget);
  });

  // the debounce is the whole cost argument: a word typed at speed must not be one request per letter
  testWidgets('a word typed in one go is a single request', (tester) async {
    final repo = await _pumpSearchScreen(tester, ['Цемент М400']);

    for (final text in ['цем', 'цеме', 'цемен', 'цемент']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repo.suggested, ['цемент']);
  });

  // typing a letter and taking it back is how people correct themselves, and it is the case the
  // remembered answers exist for
  testWidgets('a query asked once is never asked again', (tester) async {
    final repo = await _pumpSearchScreen(tester, ['Цемент М400']);

    await _type(tester, 'цем');
    await _type(tester, 'цемн');
    await _type(tester, 'цем');

    expect(repo.suggested, ['цем', 'цемн']);
  });

  testWidgets('tapping a name fills the field and runs the search', (
    tester,
  ) async {
    final repo = await _pumpSearchScreen(tester, ['Цемент М400']);

    await _type(tester, 'цем');
    await tester.tap(find.text('Цемент М400'));
    await tester.pumpAndSettle();

    expect(repo.searched, ['Цемент М400']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Цемент М400',
    );
    // the panel is gone: its names would be sitting on top of the products they led to
    expect(
      find.descendant(
        of: find.byType(ProductSuggestionsPanel),
        matching: find.text('Цемент М400'),
      ),
      findsNothing,
    );
  });

  testWidgets('a mouse click on a name runs the search', (tester) async {
    final repo = await _pumpSearchScreen(tester, ['Цемент М400']);

    await _type(tester, 'цем');
    // a mouse press outside the field drops its focus on desktop - a touch tap does not
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(tester.getCenter(find.text('Цемент М400')));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    expect(repo.searched, ['Цемент М400']);
  });

  // the search key is the other way in, and it must not leave the panel over its own results
  testWidgets('the panel closes when the search key runs the query', (
    tester,
  ) async {
    await _pumpSearchScreen(tester, ['Цемент М400']);

    await _type(tester, 'цемент м400');
    expect(find.text('Цемент М400'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Цемент М400'), findsNothing);
  });
}
