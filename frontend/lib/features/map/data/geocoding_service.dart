import 'dart:convert';

import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/profile/data/auth_service.dart';

/// A place with its point: a row of a submitted search, or a tapped suggestion once resolved.
class GeocodeResult {
  const GeocodeResult({
    required this.title,
    required this.subtitle,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  /// the part a person recognises - «проспект Амира Темура, 39»
  final String title;

  /// where it is - «Мирабадский район, Ташкент, Узбекистан»
  final String subtitle;

  /// the whole line, what the field takes once the row is picked
  final String address;
  final double latitude;
  final double longitude;

  factory GeocodeResult.fromJson(Map<String, dynamic> json) => GeocodeResult(
    title: json['title'] as String,
    subtitle: json['subtitle'] as String,
    address: json['address'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
  );
}

/// A line under the field while it is typed. It has no point yet: [GeocodingService.resolve] makes one.
class AddressSuggestion {
  const AddressSuggestion({
    required this.title,
    required this.subtitle,
    required this.uri,
  });

  final String title;
  final String subtitle;
  final String uri;

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) =>
      AddressSuggestion(
        title: json['title'] as String,
        subtitle: json['subtitle'] as String,
        uri: json['uri'] as String,
      );
}

// kept apart because callers want different halves: the add-store form stores the address on
// `shops.address`, the home header's city pill only the city
class ReverseGeocodeResult {
  const ReverseGeocodeResult({required this.address, this.city});

  /// the short form the server picks, «проспект Амира Темура, 39», or the whole line where Yandex
  /// names none
  final String address;

  /// null when Yandex names no city there - callers keep whatever city they were showing
  final String? city;
}

/// Address search, through our own `/api/geo/*`: Yandex's keys stay on the server, which caches every
/// answer for everybody and holds the daily budget all copies of the app share.
///
/// **Throws when the lookup itself fails** (an [ApiException] carrying the status) rather than answering
/// with nothing: "no such address" and "could not ask" are different sentences on screen.
class GeocodingService {
  GeocodingService({AuthService? authService})
    : _authService = authService ?? AuthService();

  final AuthService _authService;

  /// mirrors `geo.MinQueryRunes`: below it the server answers nothing without asking Yandex
  static const minQueryLength = 3;

  /// Answers already fetched this session - a backspace or a retyped letter costs no request. Static,
  /// so every screen that searches shares them.
  static final Map<String, List<AddressSuggestion>> _suggestCache = {};
  static final Map<String, List<GeocodeResult>> _searchCache = {};

  /// a session's worth of searches is a few dozen; this only stops a very long one growing forever
  static const _cacheSize = 50;

  Future<List<AddressSuggestion>> suggest(
    String query, {
    required String languageCode,
  }) => _cached(_suggestCache, query, languageCode, () async {
    final data = await _get('suggest', {'q': query, 'lang': languageCode});
    return [
      for (final item in data as List<dynamic>)
        AddressSuggestion.fromJson(item as Map<String, dynamic>),
    ];
  });

  /// A submitted search - the keyboard's search key or the picker's button.
  Future<List<GeocodeResult>> search(
    String query, {
    required String languageCode,
  }) => _cached(_searchCache, query, languageCode, () async {
    final data = await _get('search', {'q': query, 'lang': languageCode});
    return [
      for (final item in data as List<dynamic>)
        GeocodeResult.fromJson(item as Map<String, dynamic>),
    ];
  });

  /// The point of a tapped suggestion. Null when Yandex no longer knows it.
  Future<GeocodeResult?> resolve(
    AddressSuggestion suggestion, {
    required String languageCode,
  }) async {
    final data = await _get('place', {
      'uri': suggestion.uri,
      'lang': languageCode,
    }, notFoundIsNull: true);
    return data == null
        ? null
        : GeocodeResult.fromJson(data as Map<String, dynamic>);
  }

  /// A pin's address and city. Null when nothing at all is there.
  Future<ReverseGeocodeResult?> reverseGeocode(
    double latitude,
    double longitude, {
    required String languageCode,
  }) async {
    final data = await _get('reverse', {
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'lang': languageCode,
    }, notFoundIsNull: true);
    if (data == null) return null;

    final json = data as Map<String, dynamic>;
    return ReverseGeocodeResult(
      address: json['address'] as String,
      city: json['city'] as String?,
    );
  }

  static Future<List<T>> _cached<T>(
    Map<String, List<T>> cache,
    String query,
    String languageCode,
    Future<List<T>> Function() fetch,
  ) async {
    final key = '$languageCode|${query.trim().toLowerCase()}';
    final cached = cache[key];
    if (cached != null) return cached;

    final results = await fetch();
    // a map keeps insertion order, so the first key is the oldest answer
    if (cache.length >= _cacheSize) cache.remove(cache.keys.first);
    cache[key] = results;
    return results;
  }

  /// **The token goes along when there is one**: the server meters a signed-in caller by account and
  /// everyone else by address, and a carrier puts thousands of people behind one address.
  Future<Object?> _get(
    String endpoint,
    Map<String, String> query, {
    bool notFoundIsNull = false,
  }) async {
    final token = await _authService.getToken();
    final uri = Uri.parse(
      '${ApiConfig.serverRoot}/api/geo/$endpoint',
    ).replace(queryParameters: query);

    final response = await apiGet(
      uri,
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      timeout: const Duration(seconds: 15),
    );

    if (notFoundIsNull && response.statusCode == 404) return null;
    if (response.statusCode != 200) throw ApiException(response.statusCode);
    return jsonDecode(response.body);
  }
}
