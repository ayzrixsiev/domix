// The location picker's address field, tested for what it spends: geosuggest is its own 1000 calls a
// day for the whole app, and nothing on screen says when a change starts asking once per keystroke.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/map/data/geocoding_service.dart';
import 'package:frontend/features/map/presentation/screens/location_picker_screen.dart';

/// Stands in for our api, and keeps the log of what was asked for - most of these tests are about a
/// request that was *not* made.
class _FakeGeocoding implements GeocodingService {
  final List<String> suggested = [];
  final List<String> resolved = [];

  @override
  Future<List<AddressSuggestion>> suggest(
    String query, {
    required String languageCode,
  }) async {
    suggested.add(query);
    return const [
      AddressSuggestion(
        title: 'проспект Амира Темура, 39',
        subtitle: 'Мирабадский район, Ташкент',
        uri: 'ymapsbm1://geo?data=temura39',
      ),
    ];
  }

  @override
  Future<List<GeocodeResult>> search(
    String query, {
    required String languageCode,
  }) async => const [];

  @override
  Future<GeocodeResult?> resolve(
    AddressSuggestion suggestion, {
    required String languageCode,
  }) async {
    resolved.add(suggestion.uri);
    return const GeocodeResult(
      title: 'проспект Амира Темура, 39',
      subtitle: 'Мирабадский район, Ташкент, Узбекистан',
      address:
          'Узбекистан, Ташкент, Мирабадский район, проспект Амира Темура, 39',
      latitude: 41.3005,
      longitude: 69.2819,
    );
  }

  @override
  Future<ReverseGeocodeResult?> reverseGeocode(
    double latitude,
    double longitude, {
    required String languageCode,
  }) async => const ReverseGeocodeResult(address: 'проспект Амира Темура, 39');
}

Future<_FakeGeocoding> _pumpPicker(WidgetTester tester) async {
  final geocoding = _FakeGeocoding();
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: MaterialApp(home: LocationPickerScreen(geocoding: geocoding)),
    ),
  );
  // the pin's own reverse lookup waits out its debounce
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pumpAndSettle();
  return geocoding;
}

Finder get _field => find.byType(TextField);

void main() {
  testWidgets('typing a word asks for suggestions once, after the pause', (
    tester,
  ) async {
    final geocoding = await _pumpPicker(tester);

    for (final text in ['Ам', 'Ами', 'Амир', 'Амира']) {
      await tester.enterText(_field, text);
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(geocoding.suggested, isEmpty);

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(geocoding.suggested, ['Амира']);
    expect(find.text('Мирабадский район, Ташкент'), findsOneWidget);
    // a drawn row has no point yet, and getting one is a geocoder call
    expect(geocoding.resolved, isEmpty);
  });

  testWidgets('under three letters nothing is asked and nothing is claimed', (
    tester,
  ) async {
    final geocoding = await _pumpPicker(tester);

    await tester.enterText(_field, 'Ам');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(geocoding.suggested, isEmpty);
    expect(find.text('Ничего не найдено'), findsNothing);
  });

  testWidgets('only the tapped row is resolved', (tester) async {
    final geocoding = await _pumpPicker(tester);

    await tester.enterText(_field, 'Амира');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мирабадский район, Ташкент'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(geocoding.resolved, ['ymapsbm1://geo?data=temura39']);
  });
}
