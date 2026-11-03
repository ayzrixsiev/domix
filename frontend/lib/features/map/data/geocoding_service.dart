import 'dart:convert';

import 'package:flutter/foundation.dart';

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

// two free openstreetmap services, one per direction, because each one's terms fit one job.
//
// **typed text -> places is Photon** (photon.komoot.io), built for search-as-you-type: Nominatim's
// policy forbids that at any volume, and a block there lands on every copy of the app at once, since
// they block by User-Agent. Photon asks only to "be fair", hence the debounce, the three-letter floor
// and the session cache. it needs no russian `lang`: the default answers in local names and still
// matches a cyrillic query against `name:ru`.
//
// **a picked point -> an address stays on Nominatim**: one request per pin drop is inside its
// one-a-second rule, and its `addressdetails` splits out the city the home header shows.
//
// both are OpenStreetMap data, so one credit line covers both.
class GeocodingService {
  static const _userAgent = 'DomixApp/1.0 (domix.support@gmail.com)';
  static const _photonUrl = 'https://photon.komoot.io/api/';
  static const _baseUrl = 'https://nominatim.openstreetmap.org';

  /// Uzbekistan as min lon, min lat, max lon, max lat. **A hard filter, not a bias**: unbounded,
  /// «Амира Темура» comes back from Kyrgyzstan before it comes back from Tashkent.
  static const _uzbekistanBox = '55.9,37.1,73.2,45.6';

  /// Tashkent, where most shops are: ranks the nearer of two same-named streets first inside the box
  static const _biasLat = '41.31';
  static const _biasLon = '69.28';

  /// Answers already fetched this session, by query - the reason running the same search twice
  /// costs no second request. Static, so every screen that searches shares the one cache.
  static final Map<String, List<GeocodeResult>> _searchCache = {};

  /// a session's worth of searches is a few dozen; this only stops a very long one growing forever
  static const _searchCacheSize = 50;

  /// Places matching a query. [submitted] is true when the person pressed search rather than paused
  /// in typing.
  ///
  /// **Photon first, and Nominatim only on a submit.** the public Photon instance promises no speed -
  /// measured once at twenty seconds - so a typed lookup gives up quickly and says so, and a submitted
  /// one asks Nominatim, whose policy allows exactly that.
  ///
  /// **Throws when the lookup itself fails** rather than answering with an empty list: "no such
  /// address" and "could not ask" are different sentences on screen.
  Future<List<GeocodeResult>> search(
    String query, {
    bool submitted = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final key = trimmed.toLowerCase();
    final cached = _searchCache[key];
    if (cached != null) return cached;

    List<GeocodeResult> results;
    try {
      results = await _searchPhoton(trimmed);
    } catch (e) {
      if (!submitted) rethrow;
      debugPrint(
        'GeocodingService: photon failed ($e), asking nominatim for a submitted search',
      );
      results = await _searchNominatim(trimmed);
    }

    // a map keeps insertion order, so the first key is the oldest answer
    if (_searchCache.length >= _searchCacheSize)
      _searchCache.remove(_searchCache.keys.first);
    _searchCache[key] = results;
    return results;
  }

  /// a typed lookup that has not answered in this long is not going to be useful as a suggestion
  static const _photonTimeout = Duration(seconds: 4);

  Future<List<GeocodeResult>> _searchPhoton(String query) async {
    final uri = Uri.parse(_photonUrl).replace(
      queryParameters: {
        'q': query,
        'limit': '5',
        'bbox': _uzbekistanBox,
        'lat': _biasLat,
        'lon': _biasLon,
      },
    );

    final response = await appHttpClient
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(_photonTimeout);

    if (response.statusCode != 200) throw ApiException(response.statusCode);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return <GeocodeResult>[
      for (final feature in (data['features'] as List<dynamic>? ?? const []))
        ?_fromPhoton(feature),
    ];
  }

  /// the fallback for a submitted search only - see [search]
  Future<List<GeocodeResult>> _searchNominatim(String query) async {
    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {
        'q': query,
        'format': 'json',
        'limit': '5',
        'countrycodes': 'uz',
      },
    );

    final response = await appHttpClient
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) throw ApiException(response.statusCode);

    final data = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final item in data)
        GeocodeResult(
          displayName: item['display_name'] as String,
          latitude: double.parse(item['lat'] as String),
          longitude: double.parse(item['lon'] as String),
        ),
    ];
  }

  /// One GeoJSON feature as a result. Photon sends the address in parts rather than as one string, so
  /// this joins them most-specific first - the panel titles a row with the first part and shows the
  /// whole line under it, exactly as it did with Nominatim's `display_name`.
  static GeocodeResult? _fromPhoton(dynamic feature) {
    if (feature is! Map<String, dynamic>) return null;
    final coordinates =
        (feature['geometry'] as Map<String, dynamic>?)?['coordinates']
            as List<dynamic>?;
    final props = feature['properties'] as Map<String, dynamic>? ?? const {};
    if (coordinates == null || coordinates.length < 2) return null;

    String? part(String key) {
      final value = props[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final street = part('street');
    final house = part('housenumber');
    final parts = <String>[];
    for (final value in [
      part('name'),
      if (street != null) house == null ? street : '$street, $house',
      part('district'),
      part('city') ?? part('county'),
      part('state'),
    ]) {
      // a street's own name and its "street" field are the same words; saying them twice reads as a bug
      if (value != null && !parts.contains(value)) parts.add(value);
    }
    if (parts.isEmpty) return null;

    return GeocodeResult(
      displayName: parts.join(', '),
      // GeoJSON order: longitude first
      longitude: (coordinates[0] as num).toDouble(),
      latitude: (coordinates[1] as num).toDouble(),
    );
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
    final uri = Uri.parse('$_baseUrl/reverse').replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'format': 'json',
        'addressdetails': '1',
        // null-aware map value: the entry is dropped entirely rather than sending "accept-language=null"
        'accept-language': ?languageCode,
      },
    );

    final fallback = ReverseGeocodeResult(
      address: _fallbackAddress(latitude, longitude),
    );

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
