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
    final uri = Uri.parse('$_baseUrl/reverse').replace(queryParameters: {
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'format': 'json',
    });

    try {
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return _fallbackAddress(latitude, longitude);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['display_name'] as String? ?? _fallbackAddress(latitude, longitude);
    } catch (_) {
      return _fallbackAddress(latitude, longitude);
    }
  }

  String _fallbackAddress(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }
}
