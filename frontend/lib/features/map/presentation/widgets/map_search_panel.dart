import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/features/map/data/geocoding_service.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

// The map's search field and its results panel, searching two sources at once: **shops** are
// already in memory, so they match synchronously on every keystroke, while **addresses** come from
// Nominatim over HTTP and are debounced to fit their ~1 request/second free tier.
//
// It owns the text state and reports only *selections* upward, which keeps MapScreen concerned with
// the camera and the sheets rather than with text editing.
class MapSearchPanel extends StatefulWidget {
  const MapSearchPanel({
    super.key,
    required this.shops,
    required this.strings,
    required this.onShopSelected,
    required this.onPlaceSelected,
  });

  /// the shops currently plotted on the map - searched locally, never re-fetched
  final List<Shop> shops;
  final AppLocalizations strings;
  final ValueChanged<Shop> onShopSelected;
  final ValueChanged<GeocodeResult> onPlaceSelected;

  @override
  State<MapSearchPanel> createState() => _MapSearchPanelState();
}

class _MapSearchPanelState extends State<MapSearchPanel> {
  static const _debounceDelay = Duration(milliseconds: 450);

  /// below this, a query matches half of Tashkent and is not worth a network round trip
  static const _minRemoteQueryLength = 3;

  /// keeps the dropdown from covering the whole map on a long result list
  static const _maxPanelHeight = 296.0;

  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _geocoding = GeocodingService();

  Timer? _debounce;
  String _query = '';
  List<GeocodeResult> _places = const [];
  bool _isSearchingPlaces = false;

  @override
  void initState() {
    super.initState();
    // the panel shows only while the field has focus, so a focus change has to trigger a rebuild
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    // a pending timer that fires after dispose would call setState on a dead State object
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  void _onQueryChanged(String value) {
    setState(() => _query = value);

    _debounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.length < _minRemoteQueryLength) {
      // drop any in-flight results too, otherwise stale addresses from a longer query linger under
      // a query that no longer asked for them
      setState(() {
        _places = const [];
        _isSearchingPlaces = false;
      });
      return;
    }

    setState(() => _isSearchingPlaces = true);
    _debounce = Timer(_debounceDelay, () => _searchPlaces(trimmed));
  }

  Future<void> _searchPlaces(String query) async {
    final results = await _geocoding.search(query);
    if (!mounted) return;

    // the user may have typed on while the request was in flight; showing its results now would
    // contradict what is in the field
    if (_textController.text.trim() != query) return;

    setState(() {
      _places = results;
      _isSearchingPlaces = false;
    });
  }

  /// case-insensitive match on name or address, capped so the dropdown stays a shortlist
  List<Shop> get _matchingShops {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    return widget.shops
        .where((shop) =>
            shop.name.toLowerCase().contains(needle) ||
            shop.address.toLowerCase().contains(needle))
        .take(4)
        .toList();
  }

  void _clear() {
    _debounce?.cancel();
    _textController.clear();
    setState(() {
      _query = '';
      _places = const [];
      _isSearchingPlaces = false;
    });
  }

  void _dismiss() {
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final shops = _matchingShops;
    final hasQuery = _query.trim().isNotEmpty;
    final showResults = _focusNode.hasFocus && hasQuery;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchField(
          controller: _textController,
          focusNode: _focusNode,
          hint: widget.strings.mapSearchHint,
          clearTooltip: widget.strings.searchClear,
          showClear: hasQuery,
          onChanged: _onQueryChanged,
          onClear: _clear,
        ),
        // AnimatedSize keeps the dropdown from popping into existence at full height; it grows out
        // from under the field the same way the profile accordion does.
        AnimatedSize(
          duration: AppMotion.base,
          curve: AppMotion.easing,
          alignment: Alignment.topCenter,
          child: showResults
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _ResultsCard(
                    maxHeight: _maxPanelHeight,
                    shops: shops,
                    places: _places,
                    isSearchingPlaces: _isSearchingPlaces,
                    strings: widget.strings,
                    onShopTap: (shop) {
                      _textController.text = shop.name;
                      setState(() => _query = shop.name);
                      _dismiss();
                      widget.onShopSelected(shop);
                    },
                    onPlaceTap: (place) {
                      _textController.text = place.displayName;
                      setState(() => _query = place.displayName);
                      _dismiss();
                      widget.onPlaceSelected(place);
                    },
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.clearTooltip,
    required this.showClear,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final String clearTooltip;
  final bool showClear;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline),
        // it floats over a busy, coloured map rather than sitting on a page, so it needs the
        // stronger of the two elevations
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.search, color: AppColors.textFaint, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                ),
                // strips the material underline and the default 16px vertical padding, so the text
                // sits centred in our own 50px box instead of fighting it
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (showClear)
            Tooltip(
              message: clearTooltip,
              child: InkWell(
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(18),
                onTap: onClear,
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    CupertinoIcons.clear_circled_solid,
                    color: AppColors.textFaint,
                    size: 17,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({
    required this.maxHeight,
    required this.shops,
    required this.places,
    required this.isSearchingPlaces,
    required this.strings,
    required this.onShopTap,
    required this.onPlaceTap,
  });

  final double maxHeight;
  final List<Shop> shops;
  final List<GeocodeResult> places;
  final bool isSearchingPlaces;
  final AppLocalizations strings;
  final ValueChanged<Shop> onShopTap;
  final ValueChanged<GeocodeResult> onPlaceTap;

  @override
  Widget build(BuildContext context) {
    final isEmpty = shops.isEmpty && places.isEmpty && !isSearchingPlaces;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.floating,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: isEmpty
            ? _EmptyRow(label: strings.searchNoResults)
            : ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                children: [
                  if (shops.isNotEmpty) ...[
                    _SectionLabel(strings.searchSectionShops),
                    for (final shop in shops)
                      _ResultRow(
                        icon: CupertinoIcons.building_2_fill,
                        iconColor: AppColors.primaryOrange,
                        iconBackground: AppColors.primarySoft,
                        title: shop.name,
                        subtitle: shop.address,
                        onTap: () => onShopTap(shop),
                      ),
                  ],
                  if (places.isNotEmpty || isSearchingPlaces) ...[
                    _SectionLabel(strings.searchSectionPlaces),
                    if (isSearchingPlaces && places.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryOrange,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final place in places)
                        _ResultRow(
                          icon: CupertinoIcons.location_solid,
                          iconColor: AppColors.textGrey,
                          iconBackground: AppColors.surfaceMuted,
                          title: _shortPlaceName(place.displayName),
                          subtitle: place.displayName,
                          onTap: () => onPlaceTap(place),
                        ),
                  ],
                ],
              ),
      ),
    );
  }

  // nominatim returns the whole administrative chain; the first segment is the part a person actually
  // recognises, so it becomes the title and the full string stays underneath as context
  static String _shortPlaceName(String displayName) {
    final head = displayName.split(',').first.trim();
    return head.isEmpty ? displayName : head;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surfaceMuted,
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textFaint,
          fontSize: 11,
          letterSpacing: 0.3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // without this, tapping a row pulls focus off the text field, which hides the panel before
        // the tap is delivered - the row would look like it did nothing
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Row(
        children: [
          const Icon(CupertinoIcons.search, color: AppColors.textFaint, size: 16),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
