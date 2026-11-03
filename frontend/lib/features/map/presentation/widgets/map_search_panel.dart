import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/pill_search_field.dart';
import 'package:frontend/features/map/data/geocoding_service.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

// The map's search field and its results panel. **Shops** are already in memory and match on every
// keystroke; **addresses** come from Photon over HTTP, debounced - a service built for search as you
// type, unlike Nominatim, whose policy forbids it (see GeocodingService). The debounce, the
// three-letter floor and the session cache are what "be fair" means for it.
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
    this.shopsFailed = false,
    this.leading,
    this.action,
  });

  /// the shops currently plotted on the map - searched locally, never re-fetched
  final List<Shop> shops;

  /// the map's shop list failed to load, so "no shop matched" would be a claim nobody checked
  final bool shopsFailed;

  /// The way out of the full-screen map, on the field's line and to the left of it. Null where
  /// there is nothing to leave - a MapScreen opened on its own still has a route to pop.
  final Widget? leading;

  /// A control on the field's line, to the right of it - the category strip's fold-away button.
  /// Named `action` and not `trailing`, which is already the clear button *inside* the field.
  final Widget? action;

  final AppLocalizations strings;
  final ValueChanged<Shop> onShopSelected;
  final ValueChanged<GeocodeResult> onPlaceSelected;

  @override
  State<MapSearchPanel> createState() => _MapSearchPanelState();
}

class _MapSearchPanelState extends State<MapSearchPanel> {
  /// below this, a query matches half of Tashkent and is not worth a network round trip
  static const _minRemoteQueryLength = 3;

  /// keeps the dropdown from covering the whole map on a long result list
  static const _maxPanelHeight = 296.0;

  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _geocoding = GeocodingService();

  static const _debounceDelay = Duration(milliseconds: 450);

  Timer? _debounce;
  String _query = '';

  /// The text the addresses on screen were looked up for: typing on retires them, so the list never
  /// contradicts the field.
  String? _placesQuery;
  List<GeocodeResult> _places = const [];
  bool _isSearchingPlaces = false;

  /// **a flag, not the exception** - the card draws one written sentence, the reason goes to the log
  bool _placesFailed = false;

  /// a typed lookup that gave up, as opposed to a submitted one: the first has a way forward - press
  /// search - and the sentence on the card says so
  bool _placesFailedWhileTyping = false;

  @override
  void initState() {
    super.initState();
    // the panel shows only while the field has focus, so a focus change has to trigger a rebuild
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    final lookUp = trimmed.length >= _minRemoteQueryLength;

    setState(() {
      _query = value;
      if (trimmed != _placesQuery) _forgetPlaces();
      // the spinner starts with the typing, not with the request the timer will make
      if (lookUp) _isSearchingPlaces = true;
    });

    if (lookUp) _debounce = Timer(_debounceDelay, () => _searchPlaces(trimmed));
  }

  /// called from inside a setState
  void _forgetPlaces() {
    _placesQuery = null;
    _places = const [];
    _placesFailed = false;
    _placesFailedWhileTyping = false;
    _isSearchingPlaces = false;
  }

  /// Repeats cost nothing: GeocodingService answers them from its cache. [submitted] is the keyboard's
  /// search key, which is what lets a lookup that timed out while typing go to the fallback.
  Future<void> _searchPlaces(String raw, {bool submitted = false}) async {
    final query = raw.trim();
    if (query.length < _minRemoteQueryLength) return;
    if (query == _placesQuery && !_placesFailed) return;

    setState(() {
      _placesQuery = query;
      _places = const [];
      _placesFailed = false;
      _isSearchingPlaces = true;
    });

    var results = const <GeocodeResult>[];
    var failed = false;
    try {
      results = await _geocoding.search(query, submitted: submitted);
    } catch (e) {
      debugPrint('MapSearchPanel: address lookup failed: $e');
      failed = true;
    }

    // the user may have typed on while the request was in flight; its answer is for a query the field
    // no longer holds
    if (!mounted || _textController.text.trim() != query) return;

    setState(() {
      _places = results;
      _placesFailed = failed;
      _placesFailedWhileTyping = failed && !submitted;
      _isSearchingPlaces = false;
    });
  }

  /// the keyboard's search key: the lookup runs now instead of after the pause, and as a submit
  void _onSubmitted(String value) {
    _debounce?.cancel();
    _searchPlaces(value, submitted: true);
  }

  /// case-insensitive match on name or address, capped so the dropdown stays a shortlist. ё is read as
  /// е on both sides, as the product search does: customers rarely type it, owners sometimes do.
  List<Shop> get _matchingShops {
    final needle = _fold(_query.trim());
    if (needle.isEmpty) return const [];

    return widget.shops
        .where(
          (shop) =>
              _fold(shop.name).contains(needle) ||
              _fold(shop.address).contains(needle),
        )
        .take(4)
        .toList();
  }

  static String _fold(String text) => text.toLowerCase().replaceAll('ё', 'е');

  void _clear() {
    _debounce?.cancel();
    _textController.clear();
    setState(() {
      _query = '';
      _forgetPlaces();
    });
  }

  /// A row was picked: the field takes its text, and the results that led to it are done with.
  void _select(String text) {
    _debounce?.cancel();
    _textController.text = text;
    setState(() {
      _query = text;
      _forgetPlaces();
    });
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
        Row(
          children: [
            if (widget.leading case final leading?) ...[
              leading,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: PillSearchField(
                controller: _textController,
                focusNode: _focusNode,
                floating: true,
                hint: widget.strings.mapSearchHint,
                onChanged: _onQueryChanged,
                onSubmitted: _onSubmitted,
                // the panel's own clear: it drops the results list with the text
                onClear: _clear,
                clearTooltip: widget.strings.searchClear,
              ),
            ),
            if (widget.action case final action?) ...[
              const SizedBox(width: 8),
              action,
            ],
          ],
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
                    shopsFailed: widget.shopsFailed,
                    places: _places,
                    isSearchingPlaces: _isSearchingPlaces,
                    placesFailed: _placesFailed,
                    placesFailedWhileTyping: _placesFailedWhileTyping,
                    strings: widget.strings,
                    onShopTap: (shop) {
                      _select(shop.name);
                      widget.onShopSelected(shop);
                    },
                    onPlaceTap: (place) {
                      _select(place.displayName);
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

/// One of the two squares flanking the search field: the way out on the left, the category strip's
/// fold-away on the right.
///
/// **A disc at the field's height, not [CircleIconButton].** The app's one round control is sized
/// for a header, where it sits alone on a page; here three controls form a single bar over a map,
/// and a 40px disc beside a 50px capsule reads as a different kind of object dropped next to it.
class MapBarButton extends StatelessWidget {
  const MapBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.turns = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Turns the glyph in place - half a turn flips the fold-away's chevron over. One arrow turning is
  /// what says the strip is folding away; two glyphs swapped would read as a different button.
  final double turns;

  /// the search field's height, so the row has one line and not three
  static const double size = 50;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.floating,
          ),
          child: AnimatedRotation(
            turns: turns,
            duration: AppMotion.base,
            curve: AppMotion.easing,
            child: Icon(icon, color: AppColors.textDark, size: 20),
          ),
        ),
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({
    required this.maxHeight,
    required this.shops,
    required this.shopsFailed,
    required this.places,
    required this.isSearchingPlaces,
    required this.placesFailed,
    required this.placesFailedWhileTyping,
    required this.strings,
    required this.onShopTap,
    required this.onPlaceTap,
  });

  final double maxHeight;
  final List<Shop> shops;
  final bool shopsFailed;
  final List<GeocodeResult> places;
  final bool isSearchingPlaces;
  final bool placesFailed;
  final bool placesFailedWhileTyping;

  final AppLocalizations strings;
  final ValueChanged<Shop> onShopTap;
  final ValueChanged<GeocodeResult> onPlaceTap;

  @override
  Widget build(BuildContext context) {
    // a failed shop list keeps its section, with a line saying so: "nothing matched" would be a claim
    // about shops nobody could check
    final showShops = shops.isNotEmpty || shopsFailed;
    final showPlaces = places.isNotEmpty || isSearchingPlaces || placesFailed;

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
        child: !showShops && !showPlaces
            ? _NoticeRow(label: strings.searchNoResults)
            : ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                children: [
                  if (showShops) ...[
                    _SectionLabel(strings.searchSectionShops),
                    if (shops.isEmpty)
                      _NoticeRow(
                        label: strings.mapShopsUnavailable,
                        icon: CupertinoIcons.exclamationmark_circle,
                        isError: true,
                      )
                    else
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
                  if (showPlaces) ...[
                    _SectionLabel(strings.searchSectionPlaces),
                    if (isSearchingPlaces)
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
                    else if (placesFailed)
                      _NoticeRow(
                        label: placesFailedWhileTyping
                            ? strings.mapPlacesSearchSlow
                            : strings.mapPlacesSearchFailed,
                        icon: CupertinoIcons.wifi_exclamationmark,
                        isError: true,
                      )
                    else ...[
                      for (final place in places)
                        _ResultRow(
                          icon: CupertinoIcons.location_solid,
                          iconColor: AppColors.textGrey,
                          iconBackground: AppColors.surfaceMuted,
                          title: _shortPlaceName(place.displayName),
                          subtitle: place.displayName,
                          onTap: () => onPlaceTap(place),
                        ),
                      const _OsmAttribution(),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  // the result is the whole address, most specific first; the first segment is the part a person
  // actually recognises, so it becomes the title and the full string stays underneath as context
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

// one line standing in for results: nothing matched, a lookup failed, or how to start one
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.label,
    this.icon = CupertinoIcons.search,
    this.isError = false,
  });

  final String label;
  final IconData icon;

  /// danger-coloured: a failure must not read as a friendly "nothing here"
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Row(
        children: [
          Icon(
            icon,
            color: isError ? AppColors.danger : AppColors.textFaint,
            size: 16,
          ),
          const SizedBox(width: 10),
          // Expanded: the prompt and the failure are whole sentences and would overflow the row
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isError ? AppColors.danger : AppColors.textGrey,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// the addresses are OpenStreetMap data, and its licence asks for the credit wherever they are
// shown. the map underneath is Yandex's and credits only Yandex, so this line under the results is the
// one place it can go.
class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Text(
        '© OpenStreetMap contributors',
        textAlign: TextAlign.right,
        style: TextStyle(
          color: AppColors.textFaint,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
