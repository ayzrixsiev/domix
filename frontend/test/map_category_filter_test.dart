// the map's filter has no «Все» segment: the way back to every shop is a second tap on the segment
// already lit up. that is invisible without the cross, so the cross is what this covers.
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/features/map/presentation/widgets/map_category_bar.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

void main() {
  final strings = AppLocalizations(AppLanguage.ru);

  // the bar holds no state of its own - the map owns the selection, so the harness does too
  Future<void> pump(WidgetTester tester, ValueNotifier<ShopCategory?> selected) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<ShopCategory?>(
            valueListenable: selected,
            builder: (context, value, _) => MapCategoryBar(
              selected: value,
              strings: strings,
              onSelected: (category) => selected.value = category,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the cross appears on the picked category and a second tap clears it', (tester) async {
    final selected = ValueNotifier<ShopCategory?>(null);
    await pump(tester, selected);

    // nothing picked: four plain segments
    expect(find.byIcon(LucideIcons.x), findsNothing);

    await tester.tap(find.text(strings.shopCategoryWood));
    await tester.pumpAndSettle();

    expect(selected.value, ShopCategory.wood);
    // one cross, and it is on the segment that was picked
    expect(find.byIcon(LucideIcons.x), findsOneWidget);

    await tester.tap(find.text(strings.shopCategoryWood));
    await tester.pumpAndSettle();

    // back to every shop on the map
    expect(selected.value, isNull);
    expect(find.byIcon(LucideIcons.x), findsNothing);
  });

  testWidgets('only one category at a time', (tester) async {
    final selected = ValueNotifier<ShopCategory?>(ShopCategory.wood);
    await pump(tester, selected);

    await tester.tap(find.text(strings.shopCategoryUniversal));
    await tester.pumpAndSettle();

    expect(selected.value, ShopCategory.universal);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
  });
}
