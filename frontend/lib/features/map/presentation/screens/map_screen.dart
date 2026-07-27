import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/constants/app_colors.dart';
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShopBanner(imageUrl: shop.imageFullUrl),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shop.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(CupertinoIcons.star_fill, color: AppColors.starYellow, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        shop.rating.toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(CupertinoIcons.location_solid, color: AppColors.accentBlue, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      shop.address,
                      style: const TextStyle(color: AppColors.textGrey, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              if (shop.averagePaycheck > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.cardGrey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${strings.averageCheck} ${strings.somAmount(shop.averagePaycheck)}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => launchUrl(Uri.parse('tel:${shop.contactPhone}')),
                  icon: const Icon(CupertinoIcons.phone_fill, color: Colors.white, size: 18),
                  label: Text(
                    shop.contactPhone,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

          if (controller.isLoading && controller.stores.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (controller.loadError != null && controller.stores.isEmpty)
            _MapMessageBanner(message: strings.mapLoadError)
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

class _MapMessageBanner extends StatelessWidget {
  const _MapMessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// shown at the top of a shop's details sheet: the shop's real photo once that feature exists,
// or - for now, since shops don't have photos yet - a plain default banner instead
class ShopBanner extends StatelessWidget {
  const ShopBanner({super.key, required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: imageUrl != null
          ? Image.network(
              imageUrl!,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const _DefaultBanner(),
            )
          : const _DefaultBanner(),
    );
  }
}

class _DefaultBanner extends StatelessWidget {
  const _DefaultBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryOrange, Color(0xFFE65D00)],
        ),
      ),
      child: const Center(
        child: Icon(CupertinoIcons.building_2_fill, color: Colors.white, size: 44),
      ),
    );
  }
}
