import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/products/presentation/widgets/product_grid.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';
import '../widgets/map_search_panel.dart';
import '../widgets/shop_marker.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.showScaffold = true, this.bottomPadding = 36});

  final bool showScaffold;
  final double bottomPadding;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  // tashkent, since that's where domix currently operates - a sensible default center
  static const _defaultCenter = LatLng(41.2995, 69.2401);

  /// close enough to read street names after jumping to a search result
  static const _focusedZoom = 16.0;

  final _mapController = MapController();

  // drives the camera tween in _flyTo. flutter_map's own MapController.move() is an instant jump -
  // animating it is left to the caller (or to the third-party flutter_map_animations package), and
  // a plain AnimationController does the job here without taking on another dependency.
  late final AnimationController _cameraController;
  VoidCallback? _cameraTick;

  @override
  void initState() {
    super.initState();
    _cameraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

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

  @override
  void dispose() {
    if (_cameraTick != null) _cameraController.removeListener(_cameraTick!);
    _cameraController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // glides the camera to [target] instead of teleporting. every frame the controller ticks, we read
  // the tweens at the current progress and hand flutter_map a new centre/zoom.
  void _flyTo(LatLng target, {double zoom = _focusedZoom}) {
    final camera = _mapController.camera;
    final latTween = Tween<double>(begin: camera.center.latitude, end: target.latitude);
    final lngTween = Tween<double>(begin: camera.center.longitude, end: target.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: zoom);
    final curved = CurvedAnimation(parent: _cameraController, curve: Curves.easeInOutCubic);

    // detach the previous frame callback first. interrupting one fly-to with another would
    // otherwise leave both listeners driving the same camera, and they would fight each other.
    if (_cameraTick != null) _cameraController.removeListener(_cameraTick!);
    _cameraTick = () => _mapController.move(
      LatLng(latTween.evaluate(curved), lngTween.evaluate(curved)),
      zoomTween.evaluate(curved),
    );
    _cameraController
      ..addListener(_cameraTick!)
      ..forward(from: 0);
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

    Widget? statusBanner;
    if (controller.isLoading && controller.stores.isEmpty) {
      statusBanner = _MapMessageBanner(message: strings.loadingShops, isBusy: true);
    } else if (controller.loadError != null && controller.stores.isEmpty) {
      statusBanner = _MapMessageBanner(message: strings.mapLoadError, isError: true);
    } else if (controller.stores.isEmpty) {
      statusBanner = _MapMessageBanner(message: strings.noShopsYet);
    }

    final body = Stack(
      children: [
        // deliberately NOT inside a SafeArea. a map is a canvas: it should run edge to edge and let
        // the status bar and the dynamic island float over it, the same way apple maps does. wrapping
        // it in SafeArea (as this screen used to) padded the whole notch band away and left a dead
        // strip of background across the top. only the controls further down are inset.
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: 12,
            // north stays up, permanently. our markers are teardrop pins with a text label under
            // them, and flutter_map rotates the whole marker layer with the camera - so a two-finger
            // twist left every pin lying on its side and the price labels upside down. panning and
            // zooming stay on; only rotate is subtracted out of the default flag set.
            interactionOptions: InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              // the flag above only governs the touch gesture. desktop/web have a second, separate
              // rotation path (hold a modifier key and drag the cursor) that is on by default and
              // would otherwise still tilt the map.
              cursorKeyboardRotationOptions: CursorKeyboardRotationOptions.disabled(),
            ),
            // tapping the map itself drops the keyboard and closes the search dropdown
            onTap: (_, _) => FocusScope.of(context).unfocus(),
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
                    // `!= null` where this used to be `> 0`. the guard is the same guard - it was
                    // always asking "does this shop have a price comparison to show" - but it now
                    // asks the model instead of inferring it from a sentinel value, because
                    // priceTier is genuinely nullable rather than an int that is always 0.
                    width: shop.priceTier != null
                        ? ShopMarker.labeledMarkerWidth
                        : ShopMarker.pinWidth,
                    height: shop.priceTier != null
                        ? ShopMarker.pinHeight + ShopMarker.labelGap + ShopMarker.labelHeight
                        : ShopMarker.pinHeight,
                    alignment: Alignment.topCenter,
                    child: ShopMarker(
                      onTap: () => _showShopDetails(context, shop),
                      // omitted entirely for a shop whose owner hasn't priced enough of its
                      // catalogue yet, or whose category has too few shops to compare within -
                      // matches the details sheet below
                      priceTier: shop.priceTier,
                      priceDifferencePercent: shop.priceDifferencePercent,
                    ),
                  ),
              ],
            ),
          ],
        ),

        // openstreetmap's licence (ODbL) requires visible attribution, so this is not decoration.
        // it is lifted clear of the floating nav bar, which started covering flutter_map's built-in
        // bottom-right widget the moment the map went full-bleed.
        Positioned(
          right: 10,
          bottom: widget.bottomPadding + 10,
          child: const _MapAttribution(),
        ),

        // the controls layer - *this* is what respects the notch, not the map behind it
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MapSearchPanel(
                    shops: controller.stores,
                    strings: strings,
                    onShopSelected: (shop) {
                      _flyTo(LatLng(shop.latitude, shop.longitude));
                      _showShopDetails(context, shop);
                    },
                    onPlaceSelected: (place) =>
                        _flyTo(LatLng(place.latitude, place.longitude)),
                  ),
                  if (statusBanner != null) ...[
                    const SizedBox(height: 10),
                    statusBanner,
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );

    // the clock and battery now sit over light map tiles rather than over our own background, so
    // they have to be told to paint dark. AnnotatedRegion applies the style while this screen is
    // the one on top, and reverts when another takes over.
    final styledBody = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: body,
    );

    if (!widget.showScaffold) {
      return styledBody;
    }

    return Scaffold(backgroundColor: AppColors.background, body: styledBody);
  }
}

class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://www.openstreetmap.org/copyright'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: const Text(
          '© OpenStreetMap',
          style: TextStyle(
            color: AppColors.textGrey,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// shop details sheet
//
// laid out as a stack of independent sections separated by hairlines rather than as one block of
// text, so sections planned for later (opening hours, promotions, more actions) drop in as
// additional entries without the layout needing to be rethought. the sheet already scrolls and is
// height-capped for the same reason - which is what let the product catalogue land at the bottom of
// it without touching anything above.
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

              // the catalogue goes last, below the call button, on purpose: someone who opened a
              // pin wants to know where the shop is and how to reach it first. browsing prices is
              // the longer, scrollable part of the visit, so it goes where scrolling starts.
              const _SheetDivider(),
              _ShopProductsSection(shop: shop, strings: strings),
            ],
          ),
        ),
      ),
    );
  }
}

// the customer-facing half of the products feature: the same two-per-row grid the owner manages,
// rendered read-only.
//
// stateful only to kick off the fetch - the products themselves live in ProductsController, keyed
// by shop, so tapping the same pin twice in one session doesn't hit the network again.
class _ShopProductsSection extends StatefulWidget {
  const _ShopProductsSection({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  State<_ShopProductsSection> createState() => _ShopProductsSectionState();
}

class _ShopProductsSectionState extends State<_ShopProductsSection> {
  @override
  void initState() {
    super.initState();
    // deferred past the first frame for the same reason MapScreen defers its own load:
    // loadProducts notifies before its first await, and notifying while the tree is still building
    // trips flutter's "setState() called during build" guard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductsController>().loadProducts(widget.shop.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final controller = Provider.of<ProductsController>(context);
    final shopId = widget.shop.id;

    // only products the shop has actually priced. an unpriced row is a real product the owner
    // simply hasn't got to yet - useful to *them*, which is why their own grid shows it - but to a
    // customer it is a tile that answers no question, and fifty of them would bury the priced ones.
    final priced = [
      for (final product in controller.productsFor(shopId))
        if (product.hasPrice) product,
    ];

    final Widget content;
    if (controller.isLoadingFor(shopId) && !controller.hasLoaded(shopId)) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primaryOrange),
          ),
        ),
      );
    } else if (priced.isEmpty) {
      // a shop that hasn't priced anything gets a line saying so rather than a hidden section.
      // hiding it would make the sheet look like it simply has no products area, which is a
      // different (and wrong) message.
      content = Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          controller.loadErrorFor(shopId) != null
              ? strings.productsLoadError
              : strings.noPricedProductsYet,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    } else {
      content = ProductGrid(
        // shrink-wrapped: it is inside the sheet's own SingleChildScrollView, and two scrollables
        // fighting over one drag gesture is how a grid ends up refusing to move
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 4),
        tiles: [
          for (final product in priced)
            ProductTile(product: product, strings: strings),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                strings.shopProductsSectionTitle,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 16,
                  letterSpacing: -0.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (priced.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${priced.length}',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          content,
        ],
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
        // the sheet is where somebody who just tapped a pin reading "−4%" finds out what it meant,
        // so this is the full sentence rather than the compressed form
        if (shop.priceTier case final tier?) ...[
          const _MetaDot(),
          Flexible(
            child: PriceTierBadge(
              tier: tier,
              differencePercent: shop.priceDifferencePercent,
              strings: strings,
              compact: true,
            ),
          ),
        ] else if (shop.basketPrice case final basket?) ...[
          // a real price with no market to compare it against
          const _MetaDot(),
          Flexible(
            child: Text(
              '${strings.basketPriceShort} ${strings.somAmount(basket)}',
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
    // centred and content-sized rather than stretched edge to edge: a short line of text in a
    // full-width bar looks like a system error banner, not a status hint
    return Center(
      child: Container(
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
