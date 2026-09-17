import 'dart:convert';

import 'package:frontend/core/network/api_client.dart';

// a single search result: a place name/address plus its coordinates
class GeocodeResult {
  const GeocodeResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  final String displayName;
  final double latitude;
  final double longitude;
}

// kept apart because callers want different halves: the add-store form stores the whole address
// on `shops.address`, the home header's city pill only the city
class ReverseGeocodeResult {
  const ReverseGeocodeResult({required this.address, this.city});

  final String address;

  /// null when nominatim could not name a city - callers keep whatever city they were showing
  final String? city;
}

// openstreetmap's free nominatim: a typed query -> coordinates, and a picked point -> an address.
//
// **its usage policy is the contract for using it at all** (operations.osmfoundation.org/policies/
// nominatim): at most one request a second, answers cached on our side, a User-Agent naming the app,
// OpenStreetMap credited wherever the results show - and **no autocomplete**, which it forbids on the
// public api outright, whatever the volume. so a lookup runs when somebody presses search, never as
// they type (MapSearchPanel, LocationPickerScreen). they block by User-Agent, which is every copy of
// this app at once.
class GeocodingService {
  static const _userAgent = 'DomixApp/1.0 (domix.support@gmail.com)';
  static const _baseUrl = 'https://nominatim.openstreetmap.org';

  /// Answers already fetched this session, by query. **Required by the policy above**, and the reason
  /// running the same search twice costs no second request. Static, so every screen that searches
  /// shares the one cache.
  static final Map<String, List<GeocodeResult>> _searchCache = {};

  /// a session's worth of searches is a few dozen; this only stops a very long one growing forever
  static const _searchCacheSize = 50;

  /// Addresses matching a typed query.
  ///
  /// **Throws when the lookup itself fails** - no connection, or nominatim refusing - instead of
  /// answering with an empty list: "no such address" and "could not ask" are different sentences on
  /// screen, and returning `[]` for both made them the same one.
  Future<List<GeocodeResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final key = trimmed.toLowerCase();
    final cached = _searchCache[key];
    if (cached != null) return cached;

    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'q': trimmed,
      'format': 'json',
      'limit': '5',
      'countrycodes': 'uz', // bias results toward uzbekistan, since that's where our shops are
    });

    final response = await appHttpClient
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) throw ApiException(response.statusCode);

    final data = jsonDecode(response.body) as List<dynamic>;
    final results = [
      for (final item in data)
        GeocodeResult(
          displayName: item['display_name'] as String,
          latitude: double.parse(item['lat'] as String),
          longitude: double.parse(item['lon'] as String),
        ),
    ];

    // a map keeps insertion order, so the first key is the oldest answer
    if (_searchCache.length >= _searchCacheSize) _searchCache.remove(_searchCache.keys.first);
    _searchCache[key] = results;
    return results;
  }

  // falls back to raw coordinates if the lookup fails, so a hiccup never blocks the add-store flow
  Future<String> reverseGeocode(double latitude, double longitude) async {
    final result = await reverseGeocodeDetailed(latitude, longitude);
    return result.address;
  }

  // the same single request, keeping nominatim's structured `address` object: `addressdetails=1` is
  // what asks for it, and without it there is only `display_name`, which cannot be split on commas
  // reliably. `languageCode` maps to `accept-language`, so the city arrives already translated.
  Future<ReverseGeocodeResult> reverseGeocodeDetailed(
    double latitude,
    double longitude, {
    String? languageCode,
  }) async {
    final uri = Uri.parse('$_baseUrl/reverse').replace(queryParameters: {
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'format': 'json',
      'addressdetails': '1',
      // null-aware map value: the entry is dropped entirely rather than sending "accept-language=null"
      'accept-language': ?languageCode,
    });

    final fallback = ReverseGeocodeResult(address: _fallbackAddress(latitude, longitude));

    try {
      final response = await appHttpClient
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return fallback;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ReverseGeocodeResult(
        address: data['display_name'] as String? ?? fallback.address,
        city: _cityFrom(data['address']),
      );
    } catch (_) {
      return fallback;
    }
  }

  // osm has no single "city" tag. largest-settlement-first, so a point in a village resolves to the
  // village rather than the region, and `state` is last so open country still yields something.
  static const _citySearchOrder = [
    'city',
    'town',
    'village',
    'municipality',
    'county',
    'state',
  ];

  String? _cityFrom(dynamic address) {
    if (address is! Map<String, dynamic>) return null;

    for (final key in _citySearchOrder) {
      final value = address[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String _fallbackAddress(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }
}
