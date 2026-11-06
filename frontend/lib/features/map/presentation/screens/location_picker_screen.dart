import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/localization/language_provider.dart';
import '../../data/geocoding_service.dart';
import '../widgets/domix_map.dart';
import '../widgets/shop_marker.dart';
import 'package:frontend/core/widgets/pill_search_field.dart';
import '../widgets/map_search_panel.dart';

// what the caller gets back once the user confirms a location
class LocationPickResult {
  const LocationPickResult({
    required this.latitude,
    required this.longitude,
    required this.address,
    this.city,
  });

  final double latitude;
  final double longitude;
  final String address;

  /// the city containing the picked point, when Yandex names one
  final String? city;
}

// lets a shop owner find their shop's location: search by address, drag the map to fine-tune
// (the pin stays fixed at the center - you move the map underneath it), then confirm.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  // tashkent, since that's where domix currently operates - a sensible default center
  static const _defaultLatitude = 41.2995;
  static const _defaultLongitude = 69.2401;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  DomixMapController? _map;
  final _geocodingService = GeocodingService();
  final _searchController = TextEditingController();

  double _centerLatitude = LocationPickerScreen._defaultLatitude;
  double _centerLongitude = LocationPickerScreen._defaultLongitude;
  String? _resolvedAddress;
  String? _resolvedCity;
  bool _isResolvingAddress = false;
  List<GeocodeResult> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _resolveAddressForCurrentCenter();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // debounced: every pin that comes to rest is a lookup from the budget the whole app shares, so a
  // burst of drags settles into one
  void _resolveAddressForCurrentCenter() {
    _debounce?.cancel();
    setState(() => _isResolvingAddress = true);

    // read synchronously, before the timer: the callback runs after an await gap, by which time this
    // screen may already be gone
    final languageCode = context.read<LanguageProvider>().language.code;

    _debounce = Timer(const Duration(milliseconds: 700), () async {
      final latitude = _centerLatitude;
      final longitude = _centerLongitude;

      ReverseGeocodeResult? result;
      try {
        result = await _geocodingService.reverseGeocode(
          latitude,
          longitude,
          languageCode: languageCode,
        );
      } catch (e) {
        debugPrint('LocationPickerScreen: reverse geocode failed: $e');
      }

      // an answer for a spot the pin has already left would name the wrong place
      if (!mounted ||
          latitude != _centerLatitude ||
          longitude != _centerLongitude) {
        return;
      }
      // a failure or an empty spot keeps the coordinates, so a hiccup never blocks the add-store flow
      setState(() {
        _resolvedAddress = result?.address ?? _coordinates(latitude, longitude);
        _resolvedCity = result?.city;
        _isResolvingAddress = false;
      });
    });
  }

  static String _coordinates(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSearching = true);

    final strings = context.read<LanguageProvider>().strings;
    var results = const <GeocodeResult>[];
    String? notice;
    try {
      results = await _geocodingService.search(
        query,
        languageCode: strings.language.code,
      );
      if (results.isEmpty) notice = strings.searchNoResults;
    } catch (e) {
      debugPrint('LocationPickerScreen: address search failed: $e');
      notice = LoadFailure.of(e) == LoadFailure.network
          ? strings.mapPlacesSearchFailed
          : strings.mapPlacesSearchUnavailable;
    }

    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
    // the picker has its own way out - drag the map onto the spot - so a line is enough
    if (notice != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  void _selectSearchResult(GeocodeResult result) {
    _map?.flyTo(result.latitude, result.longitude, zoom: 16);
    setState(() {
      _centerLatitude = result.latitude;
      _centerLongitude = result.longitude;
      _searchResults = [];
      _searchController.text = result.address;
    });
    _resolveAddressForCurrentCenter();
  }

  void _confirm() {
    Navigator.of(context).pop(
      LocationPickResult(
        latitude: _centerLatitude,
        longitude: _centerLongitude,
        address:
            _resolvedAddress ?? _coordinates(_centerLatitude, _centerLongitude),
        city: _resolvedCity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Scaffold(
      body: Stack(
        children: [
          DomixMap(
            initialLatitude: LocationPickerScreen._defaultLatitude,
            initialLongitude: LocationPickerScreen._defaultLongitude,
            initialZoom: 15,
            onControllerReady: (controller) => _map = controller,
            // fires only once the camera has come to rest. DomixMap does the filtering, so a user drag and a
            // programmatic move both re-resolve, and the 700ms debounce absorbs a burst.
            onCenterChanged: (latitude, longitude) {
              _centerLatitude = latitude;
              _centerLongitude = longitude;
              _resolveAddressForCurrentCenter();
            },
          ),

          // the pin stays fixed at the exact screen center; the map moves underneath it instead of
          // the pin itself - the same "move the map, not the pin" pattern used by uber/careem/etc
          const IgnorePointer(
            child: Center(
              child: FractionalTranslation(
                translation: Offset(0, -0.5),
                child: MapPinIcon(size: 48),
              ),
            ),
          ),

          // back button + search bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      // **MapBarButton, not the page's round control**: three things form one bar
                      // over the map here, and a 40 disc beside the 50 floating field is the odd
                      // one out - the same reason the full-screen map's exit is this button
                      MapBarButton(
                        icon: LucideIcons.chevron_left,
                        tooltip: strings.stepBackButton,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PillSearchField(
                          controller: _searchController,
                          floating: true,
                          hint: strings.searchLocationHint,
                          onSubmitted: _performSearch,
                          trailing: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(13),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    CupertinoIcons.arrow_right_circle_fill,
                                  ),
                                  color: AppColors.primaryOrange,
                                  onPressed: () =>
                                      _performSearch(_searchController.text),
                                ),
                        ),
                      ),
                    ],
                  ),
                  if (_searchResults.isNotEmpty)
                    _SearchResultsList(
                      results: _searchResults,
                      onSelected: _selectSearchResult,
                    ),
                ],
              ),
            ),
          ),

          // resolved address + confirm button
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AddressPreviewCard(
                    isResolving: _isResolvingAddress,
                    address: _resolvedAddress,
                    resolvingLabel: strings.resolvingAddress,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isResolvingAddress ? null : _confirm,
                      child: Text(
                        strings.confirmLocationButton,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({required this.results, required this.onSelected});

  final List<GeocodeResult> results;
  final ValueChanged<GeocodeResult> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: results.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final result = results[index];
          return ListTile(
            dense: true,
            leading: const Icon(
              CupertinoIcons.location_solid,
              color: AppColors.primaryOrange,
              size: 20,
            ),
            title: Text(
              result.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => onSelected(result),
          );
        },
      ),
    );
  }
}

class _AddressPreviewCard extends StatelessWidget {
  const _AddressPreviewCard({
    required this.isResolving,
    required this.address,
    required this.resolvingLabel,
  });

  final bool isResolving;
  final String? address;
  final String resolvingLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.location_solid,
            color: AppColors.primaryOrange,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: isResolving
                ? Text(
                    resolvingLabel,
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Text(
                    address ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
