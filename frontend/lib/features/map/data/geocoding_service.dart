import 'dart:convert';
import 'package:http/http.dart' as http;

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

// what a point on the map resolves to: the full street address *and* the city containing it,
// kept apart because callers want different halves. the add-store form stores the whole address
// on `shops.address`; the home header's city pill only ever shows the city.
class ReverseGeocodeResult {
  const ReverseGeocodeResult({required this.address, this.city});

  final String address;

  /// null when nominatim could not name a city for the point (open country, or the lookup failed).
  /// callers must treat that as "leave whatever city you were showing" rather than blanking it.
  final String? city;
}

// talks to openstreetmap's free nominatim api: turns a typed search query into coordinates ("search"),
// and turns a picked map point back into a human-readable address ("reverseGeocode").
//
// nominatim's usage policy requires a descriptive user-agent and caps free use at ~1 request/second, which
// is fine at our current scale. revisit this (self-hosted nominatim, or a paid provider) once traffic grows.
class GeocodingService {
  static const _userAgent = 'DomixApp/1.0 (Uzbekistan construction marketplace)';
  static const _baseUrl = 'https://nominatim.openstreetmap.org';

  Future<List<GeocodeResult>> search(String query) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'q': query,
      'format': 'json',
      'limit': '5',
      'countrycodes': 'uz', // bias results toward uzbekistan, since that's where our shops are
    });

    try {
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final List<dynamic> data = jsonDecode(response.body);
      return data
          .map((item) => GeocodeResult(
                displayName: item['display_name'] as String,
                latitude: double.parse(item['lat'] as String),
                longitude: double.parse(item['lon'] as String),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // turns a picked point into a readable address string; falls back to raw coordinates if the
  // lookup fails, so a network hiccup here never blocks the rest of the add-store flow
  Future<String> reverseGeocode(double latitude, double longitude) async {
    final result = await reverseGeocodeDetailed(latitude, longitude);
    return result.address;
  }

  // the same single request as above, but keeping the structured `address` object nominatim
  // returns instead of throwing it away. `addressdetails=1` is what asks for that object; without
  // it the response carries only the flat `display_name` string and there is no reliable way to
  // pull a city back out of it (splitting on commas breaks the moment a district name contains one).
  //
  // `languageCode` maps to nominatim's `accept-language`, so the city comes back already in the
  // app's language ("Ташкент" vs "Toshkent") rather than needing a translation table here.
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
      // null-aware map value: the whole entry is dropped when languageCode is null, so nominatim
      // falls back to its own default language rather than being sent "accept-language=null"
      'accept-language': ?languageCode,
    });

    final fallback = ReverseGeocodeResult(address: _fallbackAddress(latitude, longitude));

    try {
      final response = await http
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

  // osm has no single "city" tag - what a place is tagged as depends on its size and on whoever
  // mapped it. these keys are tried largest-settlement-first so a point in a village resolves to
  // the village rather than jumping straight to the region, and `state` is last so somewhere with
  // no settlement at all still yields something rather than null.
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
