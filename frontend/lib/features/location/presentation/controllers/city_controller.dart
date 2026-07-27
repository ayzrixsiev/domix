import 'package:flutter/material.dart';

/// Which city the user is browsing, as chosen from the map picker behind the home header's pill.
///
/// Lives in its own feature rather than inside `features/home` because the city is not a property
/// of the home screen - it is a property of the session. The pill is just the first thing to show
/// it; filtering shops and sorting "nearby" by city are the obvious next readers.
///
/// Deliberately holds no coordinates. The picker returns them, but nothing displays or filters on
/// them yet, and a field nothing reads is a field that quietly goes stale.
class CityController extends ChangeNotifier {
  String? _city;

  /// null until the user picks a location. The header falls back to the localized default
  /// (`AppLocalizations.cityName`) in that case, so the pill is never blank.
  ///
  /// Note this is a concrete place name once set, so it stops following the app's language: pick a
  /// city in Russian and the pill keeps saying "Ташкент" after switching to Uzbek. Re-picking fixes
  /// it, and the picker asks Nominatim for names in the current language (see
  /// `GeocodingService.reverseGeocodeDetailed`).
  String? get city => _city;

  /// Applies a city resolved from a map pick.
  ///
  /// Two cases deliberately do nothing:
  ///  * [picked] is null/blank - Nominatim could not name a city for that point, and blanking the
  ///    pill would be worse than leaving the last known one.
  ///  * [picked] names the city already shown - the user moved the pin to another street inside the
  ///    same city, which is not a change of city. Skipping `notifyListeners` here is the whole
  ///    point: no listener rebuilds for a move that changes nothing on screen.
  void selectCity(String? picked) {
    final next = picked?.trim();
    if (next == null || next.isEmpty) return;
    if (_isSameCity(next, _city)) return;

    _city = next;
    notifyListeners();
  }

  // case-insensitive because nominatim is not guaranteed to capitalize a name the same way twice,
  // and a pill flickering between "Toshkent" and "toshkent" would be a change the user never made
  static bool _isSameCity(String a, String? b) {
    if (b == null) return false;
    return a.toLowerCase() == b.toLowerCase();
  }
}
