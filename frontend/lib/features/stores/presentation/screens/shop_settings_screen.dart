import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/products/presentation/screens/shop_products_screen.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/widgets/store_form_fields.dart';
import 'edit_store_screen.dart';
import '../controllers/stores_controller.dart';

// the per-shop hub, opened by tapping a shop in MyShopsScreen. it owns no shop functionality itself
// - it is a menu of sections, each of which opens its own screen:
//
//   Товары             -> ShopProductsScreen (the catalogue grid: prices, stock, own products)
//   Данные магазина     -> EditStoreScreen    (name/phone/address, and delete)
//
// stacking those on one page was the alternative and is what this deliberately avoids: managing a
// catalogue and "rename and possibly destroy this shop" have nothing to do with each other, and a
// destructive button sharing a scroll view with a routine one is exactly how a shop gets deleted by
// accident.
//
// there was a third row here, "Загрузка из Excel", which bulk-loaded a catalogue from a spreadsheet.
// it is gone along with the endpoint behind it: it existed so an owner wouldn't have to type fifty
// products in one at a time, and picking a category at creation already leaves the catalogue
// stocked. it also wrote rows the own-products cap counted, which is how a shop ended up showing
// "30 из 20" on its add-product tile.
class ShopSettingsScreen extends StatelessWidget {
  const ShopSettingsScreen({super.key, required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<StoresController>(context);

    // read the live row out of the controller rather than trusting the copy this screen was
    // constructed with: editing the shop replaces that row, and without this the header would keep
    // showing the old name until the whole screen was popped and reopened. falls back to the
    // constructor's copy for the one frame between a delete landing and this screen popping.
    final current = controller.myShops.firstWhere(
      (s) => s.id == shop.id,
      orElse: () => shop,
    );

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
          strings.shopSettingsScreenTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            ShopIdentityCard(
              name: current.name,
              subtitle: current.address,
              trailing: _ProductCountBadge(shop: current, strings: strings),
            ),
            const SizedBox(height: 22),

            // one grouped card holding both rows, ios-settings style, rather than two separate
            // cards: they are alternatives within the same menu, and separating them with
            // whitespace would read as two unrelated things that happen to be near each other
            _SectionGroup(
              children: [
                _SectionRow(
                  icon: CupertinoIcons.cube_box_fill,
                  title: strings.sectionProductsTitle,
                  subtitle: strings.sectionProductsSubtitle,
                  onTap: () => _open(context, ShopProductsScreen(shop: current)),
                ),
                _SectionRow(
                  icon: CupertinoIcons.slider_horizontal_3,
                  title: strings.sectionDetailsTitle,
                  subtitle: strings.sectionDetailsSubtitle,
                  onTap: () => _openEdit(context, current),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Widget screen) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  // EditStoreScreen pops `true` when it deleted the shop. this screen is *about* that shop, so it
  // has nothing left to show and follows it back to the list.
  Future<void> _openEdit(BuildContext context, Shop current) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditStoreScreen(shop: current)),
    );
    if (deleted == true && context.mounted) Navigator.of(context).pop();
  }
}

// the catalogue size, sitting on the identity card: it is the single number that tells an owner
// whether their last upload actually landed, so it belongs where they land, not one screen deeper.
class _ProductCountBadge extends StatelessWidget {
  const _ProductCountBadge({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final hasProducts = shop.productCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: hasProducts ? AppColors.surfaceMuted : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        hasProducts ? strings.productsCountLabel(shop.productCount) : strings.noProductsYet,
        style: TextStyle(
          color: hasProducts ? AppColors.textGrey : AppColors.primaryOrange,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// a white card whose children are separated by inset hairlines, the grouped-list shape used across
// the app. the divider is inset to the text column so it reads as separating two rows of the same
// list instead of cutting the card in half.
class _SectionGroup extends StatelessWidget {
  const _SectionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      // the ink splash of a tapped row must not paint over the card's rounded corners
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.only(left: _SectionRow.textInset),
                child: SizedBox(height: 1, child: ColoredBox(color: AppColors.hairline)),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// left padding + icon tile + gap - where the text column starts, so a divider can line up with it
  static const double textInset = 16 + 38 + 14;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Icon(icon, color: AppColors.textDark, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        height: 1.25,
                        letterSpacing: -0.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(CupertinoIcons.chevron_forward, color: AppColors.textFaint, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}
