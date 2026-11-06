import 'package:flutter/material.dart';

/// Which city the user is browsing, chosen from the map picker behind the home header's pill. Its
/// own feature because the city is a property of the session, not of that screen. Holds no
/// coordinates: nothing reads them yet, and a field nothing reads goes stale.
class CityController extends ChangeNotifier {
  String? _city;

  /// null until the user picks one; the header falls back to the localized default, so the pill is
  /// never blank. Once set it is a concrete place name and stops following the app's language -
  /// re-picking fixes it.
  String? get city => _city;

  /// Two cases deliberately do nothing: a blank [picked] (Yandex could not name that point, and
  /// blanking the pill is worse than keeping the last one), and one naming the city already shown -
  /// skipping `notifyListeners` there is the point, since nothing on screen changed.
  void selectCity(String? picked) {
    final next = picked?.trim();
    if (next == null || next.isEmpty) return;
    if (_isSameCity(next, _city)) return;

    _city = next;
    notifyListeners();
  }

  // case-insensitive: a geocoder does not promise the same capitalization twice, and a pill
  // flickering between "Toshkent" and "toshkent" is a change the user never made
  static bool _isSameCity(String a, String? b) {
    if (b == null) return false;
    return a.toLowerCase() == b.toLowerCase();
  }
}
