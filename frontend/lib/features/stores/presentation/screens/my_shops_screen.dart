import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'add_store_screen.dart';
import 'shop_settings_screen.dart';
import '../controllers/stores_controller.dart';

// the shops the current owner owns, opened from Profile > Управление магазинами. tapping one opens
// ShopSettingsScreen for it.
class MyShopsScreen extends StatefulWidget {
  const MyShopsScreen({super.key});

  @override
  State<MyShopsScreen> createState() => _MyShopsScreenState();
}

class _MyShopsScreenState extends State<MyShopsScreen> {
  @override
  void initState() {
    super.initState();
    // deferred past the first frame: loadMyShops() notifies before its first await, which from
    // initState trips flutter's "called during build" guard. this screen is push-based, so a fresh
    // instance always reloads rather than checking "already loaded" first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StoresController>().loadMyShops();
    });
  }

  Future<void> _openAddStore() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddStoreScreen()),
    );
    // createShop already inserts into myShops locally; this only picks up what changed server-side
    // while the form was open
    if (mounted) context.read<StoresController>().loadMyShops();
  }

  Future<void> _openShop(Shop shop) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ShopSettingsScreen(shop: shop)),
    );
    // an upload changes this shop's product count and an edit changes its name - both already write
    // through to the controller, so this is only re-syncing with whatever else moved server-side
    if (mounted) context.read<StoresController>().loadMyShops();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<StoresController>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppPageHeader(
        title: strings.myShopsScreenTitle,
        // the count used to be a line of grey text above the first card, which is a row of the list
        // that is not a shop. on the header it is what the title is *about*, and it costs no space.
        subtitle: controller.myShops.isEmpty
            ? null
            : strings.shopsCountLabel(controller.myShops.length),
        // reachable straight from here, so adding a second shop does not mean backing out to profile.
        // orange only on the glyph: the disc is the same white one the back button wears, so the two
        // ends of the header are the same control at the same weight.
        action: CircleIconButton(
          icon: CupertinoIcons.add,
          iconColor: AppColors.primaryOrange,
          tooltip: strings.addStore,
          onTap: _openAddStore,
        ),
      ),
      body: SafeArea(child: _buildBody(controller, strings)),
    );
  }

  Widget _buildBody(StoresController controller, AppLocalizations strings) {
    if (controller.isLoadingMyShops && controller.myShops.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }

    if (controller.myShopsFailed && controller.myShops.isEmpty) {
      return EmptyStateView(
        icon: CupertinoIcons.wifi_exclamationmark,
        // the only place this state is coloured differently: same layout as the designed empty state, but
        // a failure should not look like a friendly "nothing here yet"
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
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        itemCount: controller.myShops.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final shop = controller.myShops[index];
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
                    // flat tint instead of a gradient - a 44px avatar is too small for a gradient to read as anything
                    // but noise
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

// quiet text rather than colour-filled pills, which carried no meaning the numbers did not already
// carry. colour is reserved for the one actionable case: a shop with an empty catalogue.
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
        // the owner's own view of what a customer sees - "your basket is 6% above the market" is the single
        // most actionable thing this screen can tell them. nothing at all when the shop has no index, which
        // since migration 000013 means it has not priced its whole template; the count of what is left
        // lives on ShopProductsScreen, with the prices.
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
// piece of centred text was the heaviest thing on an otherwise empty screen
