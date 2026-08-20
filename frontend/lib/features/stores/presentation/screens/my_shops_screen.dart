import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'add_store_screen.dart';
import 'shop_settings_screen.dart';
import '../controllers/stores_controller.dart';

// lists the shops the current owner themselves own - opened from Profile > Управление
// магазинами > Настройка магазинов. tapping a shop opens ShopSettingsScreen for it.
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
      MaterialPageRoute(builder: (_) => ShopSettingsScreen(shop: shop)),
    );
    // an upload changes the product count shown on this shop's row, and an edit changes its name or
    // address. both already write through to the controller's list, so this is only re-syncing with
    // whatever else moved server-side while the owner was in there.
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
      return EmptyStateView(
        icon: CupertinoIcons.wifi_exclamationmark,
        // the only place this state is coloured differently: the layout is the same designed empty
        // state, but a failure should not look like a friendly "nothing here yet"
        iconColor: AppColors.danger,
        iconBackground: AppColors.dangerSoft,
        title: strings.myShopsLoadError,
        action: PrimaryActionButton(
          label: strings.retryButtonShort,
          onTap: () => controller.loadMyShops(),
        ),
      );
    }

    if (controller.myShops.isEmpty) {
      return EmptyStateView(
        icon: CupertinoIcons.bag,
        title: strings.noOwnedShopsYet,
        subtitle: strings.noOwnedShopsHint,
        // unlike the permanently-empty tabs, this one has somewhere to go
        action: PrimaryActionButton(
          label: strings.addStore,
          icon: CupertinoIcons.add,
          onTap: _openAddStore,
        ),
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
        // the owner's own view of what a customer sees. worth showing even though it is a
        // customer-facing comparison: "your basket is 6% above the market" is the single most
        // actionable thing this screen can tell a shop owner.
        //
        // nothing at all when the shop has no index, which since migration 000013 means it has not
        // priced its whole template. there is no half-state to render here: a basket price without a
        // tier used to mean "priced, but no market to compare within" and the view can no longer
        // produce that combination. the reason, and the count of what is left, live one tap away on
        // ShopProductsScreen, where the prices themselves are.
        if (shop.priceTier case final tier?)
          Flexible(
            child: PriceTierBadge(
              tier: tier,
              differencePercent: shop.priceDifferencePercent,
              strings: strings,
              size: PriceTierBadgeSize.compact,
            ),
          ),
      ],
    );
  }
}

// sized to its label instead of stretching edge to edge: a full-width slab of orange under a short
// piece of centred text was the heaviest thing on an otherwise empty screen.
