import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import '../../data/geocoding_service.dart';
import '../widgets/shop_marker.dart';

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

  /// the city containing the picked point, when nominatim could name one. the add-store form
  /// ignores this and stores the full address; the home header's city pill uses only this.
  final String? city;
}

// lets a shop owner find their shop's location: search by address, drag the map to fine-tune
// (the pin stays fixed at the center - you move the map underneath it), then confirm.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  // tashkent, since that's where domix currently operates - a sensible default center
  static const _defaultCenter = LatLng(41.2995, 69.2401);

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapController = MapController();
  final _geocodingService = GeocodingService();
  final _searchController = TextEditingController();

  LatLng _currentCenter = LocationPickerScreen._defaultCenter;
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

  // debounced so we don't hammer nominatim's free api on every frame while the user is still dragging
  void _resolveAddressForCurrentCenter() {
    _debounce?.cancel();
    setState(() => _isResolvingAddress = true);

    // read the language synchronously, before the timer: the callback below runs after an await
    // gap, and reaching for context there could happen once this screen is already gone
    final languageCode = context.read<LanguageProvider>().language.code;

    _debounce = Timer(const Duration(milliseconds: 700), () async {
      final result = await _geocodingService.reverseGeocodeDetailed(
        _currentCenter.latitude,
        _currentCenter.longitude,
        languageCode: languageCode,
      );
      if (!mounted) return;
      setState(() {
        _resolvedAddress = result.address;
        _resolvedCity = result.city;
        _isResolvingAddress = false;
      });
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSearching = true);

    final results = await _geocodingService.search(query);

    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  void _selectSearchResult(GeocodeResult result) {
    final target = LatLng(result.latitude, result.longitude);
    _mapController.move(target, 16);
    setState(() {
      _currentCenter = target;
      _searchResults = [];
      _searchController.text = result.displayName;
    });
    _resolveAddressForCurrentCenter();
  }

  void _confirm() {
    Navigator.of(context).pop(
      LocationPickResult(
        latitude: _currentCenter.latitude,
        longitude: _currentCenter.longitude,
        address: _resolvedAddress ??
            '${_currentCenter.latitude.toStringAsFixed(5)}, ${_currentCenter.longitude.toStringAsFixed(5)}',
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
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 15,
              // matches map_screen.dart: north stays up. this screen's pin is a fixed overlay rather
              // than a map marker so it wouldn't tilt, but a picker that can end up facing an
              // arbitrary direction is disorienting, and two maps behaving differently is worse.
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                cursorKeyboardRotationOptions: CursorKeyboardRotationOptions.disabled(),
              ),
              onPositionChanged: (camera, hasGesture) {
                _currentCenter = camera.center;
                if (hasGesture) _resolveAddressForCurrentCenter();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'uz.domix.app',
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
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
                      _RoundIconButton(
                        icon: CupertinoIcons.back,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SearchField(
                          controller: _searchController,
                          hintText: strings.searchLocationHint,
                          isSearching: _isSearching,
                          onSubmitted: _performSearch,
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: AppColors.textDark, size: 20),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.isSearching,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final bool isSearching;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      elevation: 3,
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          prefixIcon: const Icon(CupertinoIcons.search, size: 20),
          suffixIcon: isSearching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(CupertinoIcons.arrow_right_circle_fill),
                  color: AppColors.primaryOrange,
                  onPressed: () => onSubmitted(controller.text),
                ),
        ),
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
            leading: const Icon(CupertinoIcons.location_solid, color: AppColors.primaryOrange, size: 20),
            title: Text(
              result.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
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
          const Icon(CupertinoIcons.location_solid, color: AppColors.primaryOrange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: isResolving
                ? Text(
                    resolvingLabel,
                    style: const TextStyle(color: AppColors.textGrey, fontSize: 13, fontWeight: FontWeight.w500),
                  )
                : Text(
                    address ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textDark, fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}
