import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
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
        centerTitle: false,
        titleSpacing: 20,
        iconTheme: const IconThemeData(color: AppColors.textDark, size: 22),
        title: Text(
          strings.myShopsScreenTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // reachable straight from here, so adding a second shop doesn't mean backing out to
          // profile. a tinted round button rather than a bare oversized icon - it reads as an
          // affordance without another block of solid orange in the bar.
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _AppBarActionButton(
              icon: CupertinoIcons.add,
              tooltip: strings.addStore,
              onTap: _openAddStore,
            ),
          ),
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
        iconBackground: AppColors.primarySoft,
        title: strings.noOwnedShopsYet,
        subtitle: strings.noOwnedShopsHint,
        actionLabel: strings.addStore,
        actionIcon: CupertinoIcons.add,
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
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                strings.shopsCountLabel(controller.myShops.length),
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 12.5,
                  letterSpacing: 0.2,
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

class _AppBarActionButton extends StatelessWidget {
  const _AppBarActionButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.primarySoft,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: AppColors.primaryOrange, size: 19),
          ),
        ),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.card,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // flat tint instead of the previous gradient - a 44px avatar is too small for a
                    // gradient to read as anything but noise
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Icon(
                        CupertinoIcons.building_2_fill,
                        color: AppColors.primaryOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 13),
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
                              height: 1.25,
                              letterSpacing: -0.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            shop.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 12.5,
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(top: 13),
                      child: Icon(
                        CupertinoIcons.chevron_forward,
                        color: AppColors.textFaint,
                        size: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 1, child: ColoredBox(color: AppColors.hairline)),
                const SizedBox(height: 11),
                _ShopStatsRow(shop: shop, strings: strings),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// the two colour-filled pills this replaced were carrying no meaning that the numbers didn't
// already carry - so they're quiet text now, and colour is reserved for the one case that is
// actually actionable: a shop with an empty catalogue, which is exactly what this screen fixes.
class _ShopStatsRow extends StatelessWidget {
  const _ShopStatsRow({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final hasProducts = shop.productCount > 0;

    return Row(
      children: [
        if (hasProducts) ...[
          const Icon(CupertinoIcons.cube_box, color: AppColors.textFaint, size: 13),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              strings.productsCountLabel(shop.productCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ] else ...[
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primaryOrange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              strings.noProductsYet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.primaryOrange,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(width: 12),
        const Spacer(),
        if (shop.averagePaycheck > 0) ...[
          Text(
            strings.averageCheckShort,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            strings.somAmount(shop.averagePaycheck),
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

// shared shape for the "nothing to show" states: loading failed, no shops yet, and any future
// empty case - so they don't drift apart visually.
class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    this.subtitle,
    required this.actionLabel,
    this.actionIcon,
    required this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final IconData? actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // two nested layers rather than one flat circle - that's what makes an empty screen look
            // composed on purpose instead of merely unfinished. the inner tile is white and lifted
            // rather than a second tint: two tints this pale are indistinguishable from each other
            // against an off-white page, so the layering has to come from value, not hue.
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.card,
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 17,
                height: 1.3,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              // capped measure: long help text set to the full screen width is hard to read and is
              // most of why the empty state felt sparse and unbalanced
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 270),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 26),
            _PrimaryButton(label: actionLabel, icon: actionIcon, onTap: onAction),
          ],
        ),
      ),
    );
  }
}

// sized to its label instead of stretching edge to edge: a full-width slab of orange under a short
// piece of centred text was the heaviest thing on an otherwise empty screen.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 17),
                  const SizedBox(width: 8),
                ],
                // Flexible, not a bare Text: "Добавить новый магазин" and its uzbek equivalent are
                // long enough to overflow a min-sized Row on a narrow screen or at a large text
                // scale. it stays on one line whenever it fits and wraps rather than clipping.
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.25,
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
