import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';
import '../widgets/shop_marker.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.showScaffold = true, this.bottomPadding = 36});

  final bool showScaffold;
  final double bottomPadding;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // tashkent, since that's where domix currently operates - a sensible default center
  static const _defaultCenter = LatLng(41.2995, 69.2401);

  @override
  void initState() {
    super.initState();
    // fire-and-forget: load once when the map tab is first built. IndexedStack keeps this screen's
    // state alive across tab switches, so this only ever runs the one time per app session.
    // deferred to after the first frame - loadStores() calls notifyListeners() before its first
    // await, and calling that synchronously from initState (while the tree is still building)
    // trips flutter's "setState()/markNeedsBuild() called during build" guard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<StoresController>();
      if (controller.stores.isEmpty && !controller.isLoading) {
        controller.loadStores();
      }
    });
  }

  void _showShopDetails(BuildContext context, Shop shop) {
    final strings = Provider.of<LanguageProvider>(context, listen: false).strings;

    showModalBottomSheet(
      context: context,
      // the sheet paints its own rounded surface, so the framework's must not sit behind it
      backgroundColor: Colors.transparent,
      // lets the sheet size past the default ~50% cap. it's content-sized today, but this is what
      // will let it keep working once products/promotions are added to it.
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => _ShopDetailsSheet(shop: shop, strings: strings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<StoresController>(context);

    final body = SafeArea(
      bottom: false,
      child: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'uz.domix.app',
              ),
              MarkerLayer(
                markers: [
                  for (final shop in controller.stores)
                    Marker(
                      point: LatLng(shop.latitude, shop.longitude),
                      width: shop.averagePaycheck > 0 ? ShopMarker.labeledMarkerWidth : ShopMarker.pinWidth,
                      height: shop.averagePaycheck > 0
                          ? ShopMarker.pinHeight + ShopMarker.labelGap + ShopMarker.labelHeight
                          : ShopMarker.pinHeight,
                      alignment: Alignment.topCenter,
                      child: ShopMarker(
                        onTap: () => _showShopDetails(context, shop),
                        // omitted entirely (not "0 сум") for a brand-new shop with no sales yet -
                        // matches the same `> 0` convention the details sheet below already uses
                        averagePaycheckLabel:
                            shop.averagePaycheck > 0 ? strings.somAmount(shop.averagePaycheck) : null,
                      ),
                    ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),

          // all three states share one floating pill anchored at the top. a bare centred spinner
          // over map tiles had nothing behind it to sit on and read as the map itself being broken.
          if (controller.isLoading && controller.stores.isEmpty)
            _MapMessageBanner(message: strings.loadingShops, isBusy: true)
          else if (controller.loadError != null && controller.stores.isEmpty)
            _MapMessageBanner(message: strings.mapLoadError, isError: true)
          else if (controller.stores.isEmpty)
            _MapMessageBanner(message: strings.noShopsYet),
        ],
      ),
    );

    if (!widget.showScaffold) {
      return body;
    }

    return Scaffold(backgroundColor: AppColors.background, body: body);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// shop details sheet
//
// laid out as a stack of independent sections separated by hairlines rather than as one block of
// text, so the sections planned for later (products, opening hours, promotions, more actions) drop
// in as additional entries without the layout needing to be rethought. the sheet already scrolls
// and is height-capped for the same reason.
// ─────────────────────────────────────────────────────────────────────────────

class _ShopDetailsSheet extends StatelessWidget {
  const _ShopDetailsSheet({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetGrabber(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ShopBanner(imageUrl: shop.imageFullUrl),
              ),
              const SizedBox(height: 16),

              // identity: name carries all the emphasis, everything else steps down a level
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      style: const TextStyle(
                        fontSize: 21,
                        height: 1.2,
                        letterSpacing: -0.3,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _ShopMetaLine(shop: shop, strings: strings),
                  ],
                ),
              ),

              const SizedBox(height: 18),
              const _SheetDivider(),
              _DetailRow(
                icon: CupertinoIcons.location_solid,
                label: strings.addressLabel,
                value: shop.address,
              ),
              // indented to line up with the text column, the way grouped ios lists separate rows
              const _SheetDivider(indent: _DetailRow.textInset),
              _DetailRow(
                icon: CupertinoIcons.phone_fill,
                label: strings.phoneLabel,
                value: shop.contactPhone,
              ),
              const _SheetDivider(),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: _CallButton(
                  label: strings.callButton,
                  onTap: () => launchUrl(Uri.parse('tel:${shop.contactPhone}')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE1E4EA),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SheetDivider extends StatelessWidget {
  const _SheetDivider({this.indent = 20});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: const SizedBox(height: 1, child: ColoredBox(color: AppColors.hairline)),
    );
  }
}

// rating and average check on one line directly under the name. previously the rating floated on
// the far right of the title row, which is why it read as detached - as secondary metadata it
// belongs next to the other secondary metadata, not opposite the heading.
class _ShopMetaLine extends StatelessWidget {
  const _ShopMetaLine({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(CupertinoIcons.star_fill, color: AppColors.starYellow, size: 13),
        const SizedBox(width: 4),
        Text(
          shop.rating.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        if (shop.averagePaycheck > 0) ...[
          const _MetaDot(),
          Flexible(
            child: Text(
              '${strings.averageCheckShort} ${strings.somAmount(shop.averagePaycheck)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textGrey,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(color: AppColors.textFaint, shape: BoxShape.circle),
    );
  }
}

// label above value, with a muted icon in the gutter. the label being small and faint is what lets
// the value itself stay readable at a normal weight instead of needing bold to stand out.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  /// left padding + icon width + gap - the x offset the text column starts at
  static const double textInset = 20 + 16 + 12;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Icon(icon, color: AppColors.textFaint, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    letterSpacing: 0.2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textFaint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.accent(AppColors.primaryOrange),
      ),
      child: Material(
        color: AppColors.primaryOrange,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.phone_fill, color: Colors.white, size: 16),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      letterSpacing: 0.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapMessageBanner extends StatelessWidget {
  const _MapMessageBanner({
    required this.message,
    this.isBusy = false,
    this.isError = false,
  });

  final String message;
  final bool isBusy;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 14,
      left: 0,
      right: 0,
      // centred and content-sized rather than stretched edge to edge: a short line of text in a
      // full-width bar looks like a system error banner, not a status hint
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.floating,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBusy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryOrange,
                  ),
                )
              else
                Icon(
                  isError
                      ? CupertinoIcons.exclamationmark_circle_fill
                      : CupertinoIcons.map_pin_slash,
                  color: isError ? AppColors.danger : AppColors.textFaint,
                  size: 15,
                ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isError ? AppColors.danger : AppColors.textGrey,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// shown at the top of a shop's details sheet: the shop's real photo once that feature exists,
// or - for now, since shops don't have photos yet - a neutral placeholder instead
class ShopBanner extends StatelessWidget {
  const ShopBanner({super.key, required this.imageUrl});

  final String? imageUrl;

  static const double height = 96;

  @override
  Widget build(BuildContext context) {
    // foreground decoration paints the outline *over* the clipped child, so the same hairline
    // frames a real photo and the placeholder alike
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: imageUrl != null
            ? Image.network(
                imageUrl!,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const _DefaultBanner(),
              )
            : const _DefaultBanner(),
      ),
    );
  }
}

// was a full-bleed saturated orange gradient, which made the loudest thing in the sheet a
// placeholder for missing content. now a near-neutral surface with the faintest warm tint, so the
// shop's name is what the eye lands on first.
class _DefaultBanner extends StatelessWidget {
  const _DefaultBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ShopBanner.height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primarySoft, AppColors.surfaceMuted],
        ),
      ),
      child: Center(
        child: Icon(
          CupertinoIcons.building_2_fill,
          color: AppColors.primaryOrange.withValues(alpha: 0.42),
          size: 30,
        ),
      ),
    );
  }
}
