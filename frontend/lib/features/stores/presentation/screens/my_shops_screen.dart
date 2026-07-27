import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'add_store_screen.dart';
import 'shop_upload_screen.dart';
import '../controllers/stores_controller.dart';

// lists the shops the current owner themselves own - opened from Profile > Управление
// магазинами > Настройка магазинов. tapping a shop opens ShopUploadScreen for it.
class MyShopsScreen extends StatefulWidget {
  const MyShopsScreen({super.key});

  @override
  State<MyShopsScreen> createState() => _MyShopsScreenState();
}

class _MyShopsScreenState extends State<MyShopsScreen> {
  @override
  void initState() {
    super.initState();
    // deferred past the first frame - loadMyShops() notifies before its first await, and calling
    // that synchronously from initState trips flutter's "called during build" guard (same fix as
    // map_screen.dart's initState). unlike MapScreen this screen is push-based (a fresh instance
    // each time it opens), so it always reloads rather than checking "already loaded" first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StoresController>().loadMyShops();
    });
  }

  Future<void> _openAddStore() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddStoreScreen()),
    );
    // createShop already inserts into myShops locally, so this is only here to pick up anything
    // that changed server-side while the form was open
    if (mounted) context.read<StoresController>().loadMyShops();
  }

  Future<void> _openShop(Shop shop) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ShopUploadScreen(shop: shop)),
    );
    // an upload changes the product count shown on this shop's row
    if (mounted) context.read<StoresController>().loadMyShops();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<StoresController>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        title: Text(
          strings.myShopsScreenTitle,
          style: const TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w800),
        ),
        actions: [
          // reachable straight from here, so adding a second shop doesn't mean backing out to profile
          IconButton(
            onPressed: _openAddStore,
            icon: const Icon(CupertinoIcons.add_circled_solid, color: AppColors.primaryOrange, size: 26),
            tooltip: strings.addStore,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: _buildBody(controller, strings)),
    );
  }

  Widget _buildBody(StoresController controller, AppLocalizations strings) {
    if (controller.isLoadingMyShops && controller.myShops.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }

    if (controller.myShopsError != null && controller.myShops.isEmpty) {
      return _CenteredState(
        icon: CupertinoIcons.wifi_exclamationmark,
        iconColor: AppColors.danger,
        iconBackground: AppColors.dangerSoft,
        title: strings.myShopsLoadError,
        actionLabel: strings.retryButtonShort,
        onAction: () => controller.loadMyShops(),
      );
    }

    if (controller.myShops.isEmpty) {
      return _CenteredState(
        icon: CupertinoIcons.bag,
        iconColor: AppColors.primaryOrange,
        iconBackground: const Color(0xFFFFF0E3),
        title: strings.noOwnedShopsYet,
        subtitle: strings.noOwnedShopsHint,
        actionLabel: strings.addStore,
        onAction: _openAddStore,
      );
    }

    // pull-to-refresh matters here specifically because product counts change from another screen
    return RefreshIndicator(
      color: AppColors.primaryOrange,
      onRefresh: () => controller.loadMyShops(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        itemCount: controller.myShops.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                strings.shopsCountLabel(controller.myShops.length),
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          final shop = controller.myShops[index - 1];
          return _ShopCard(
            shop: shop,
            strings: strings,
            onTap: () => _openShop(shop),
          );
        },
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop, required this.strings, required this.onTap});

  final Shop shop;
  final AppLocalizations strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasProducts = shop.productCount > 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF2F4F7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFF0E3), Color(0xFFFFE0C2)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        CupertinoIcons.building_2_fill,
                        color: AppColors.primaryOrange,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 1),
                                child: Icon(
                                  CupertinoIcons.location_solid,
                                  color: AppColors.textGrey,
                                  size: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  shop.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textGrey,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 14, left: 6),
                      child: Icon(CupertinoIcons.chevron_forward, color: Color(0xFFCBD2DA), size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFF2F4F7)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ShopChip(
                      icon: CupertinoIcons.cube_box_fill,
                      label: hasProducts
                          ? strings.productsCountLabel(shop.productCount)
                          : strings.noProductsYet,
                      // an empty catalog is the thing this screen exists to fix, so it reads as a
                      // gentle prompt rather than neutral information
                      color: hasProducts ? AppColors.accentBlue : AppColors.textGrey,
                      background: hasProducts ? const Color(0xFFEAF2FF) : const Color(0xFFF1F3F6),
                    ),
                    if (shop.averagePaycheck > 0) ...[
                      const SizedBox(width: 8),
                      _ShopChip(
                        icon: CupertinoIcons.money_dollar_circle_fill,
                        label: strings.somAmount(shop.averagePaycheck),
                        color: const Color(0xFF0F9D58),
                        background: const Color(0xFFE8F5EC),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShopChip extends StatelessWidget {
  const _ShopChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// shared shape for the three "nothing to show" states: loading failed, no shops yet, and any
// future empty case - so they don't drift apart visually
class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: onAction,
              child: Text(
                actionLabel,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
