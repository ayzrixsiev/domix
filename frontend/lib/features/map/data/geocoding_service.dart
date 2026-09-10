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

// kept apart because callers want different halves: the add-store form stores the whole address
// on `shops.address`, the home header's city pill only the city
class ReverseGeocodeResult {
  const ReverseGeocodeResult({required this.address, this.city});

  final String address;

  /// null when nominatim could not name a city - callers keep whatever city they were showing
  final String? city;
}

// openstreetmap's free nominatim: a typed query -> coordinates, and a picked point -> an address.
// their policy asks for a descriptive user-agent and ~1 request/second; revisit once traffic grows.
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
