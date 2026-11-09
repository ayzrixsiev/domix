import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import '../../data/geocoding_service.dart';
import '../widgets/domix_map.dart';
import '../widgets/shop_marker.dart';
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

  /// the short form, «проспект Амира Темура, 39» - what the shop stores and every screen shows
  final String address;

  /// the city containing the picked point, when Yandex names one
  final String? city;
}

// lets a shop owner find their shop's location: search by address, drag the map to fine-tune
// (the pin stays fixed at the center - you move the map underneath it), then confirm.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.geocoding});

  final GeocodingService? geocoding;

  // tashkent, since that's where domix currently operates - a sensible default center
  static const _defaultLatitude = 41.2995;
  static const _defaultLongitude = 69.2401;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  DomixMapController? _map;
  late final _geocodingService = widget.geocoding ?? GeocodingService();

  double _centerLatitude = LocationPickerScreen._defaultLatitude;
  double _centerLongitude = LocationPickerScreen._defaultLongitude;
  String? _resolvedAddress;
  String? _resolvedCity;
  bool _isResolvingAddress = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _resolveAddressForCurrentCenter();
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  void _selectSearchResult(GeocodeResult result) {
    _map?.flyTo(result.latitude, result.longitude, zoom: 16);
    setState(() {
      _centerLatitude = result.latitude;
      _centerLongitude = result.longitude;
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

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: MapSearchPanel.addresses(
                  strings: strings,
                  geocoding: _geocodingService,
                  // **MapBarButton, not the page's round control**: it and the field form one bar
                  // over the map, and a 40 disc beside the 50 floating field is the odd one out -
                  // the same reason the full-screen map's exit is this button
                  leading: MapBarButton(
                    icon: LucideIcons.chevron_left,
                    tooltip: strings.stepBackButton,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  onPlaceSelected: _selectSearchResult,
                ),
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
