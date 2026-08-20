import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/products/presentation/widgets/product_grid.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

/// One shop, in full: who they are, what their basket costs, how to reach them, and what they sell.
///
/// **There is one of these and every route into a shop ends here** - a pin on the map, a card in the
/// VIP carousel, a row in Лучшие предложения. Before this screen existed only the map could open a
/// shop, as a modal sheet, so the same object was a destination from one place in the app and
/// unreachable from three others: tapping a VIP card the founder had paid to place did nothing at
/// all.
///
/// **A pushed route rather than the bottom sheet it replaces.** Three reasons, in order of weight:
///
///  * It is now reached from lists as well as from the map, and a list opening a modal sheet on top
///    of itself is not a pattern the rest of this app uses anywhere.
///  * It can be a [CustomScrollView], so the product catalogue is a **sliver**. The sheet's grid was
///    `shrinkWrap: true`, which lays out every child to measure itself - a hundred tiles mounted at
///    once, each firing an `Image.network` the moment it mounts. That is the bug documented in
///    CLAUDE.md §8 whose symptom is not slow images but a *failed price save*, and the note there
///    says to fix it here before a shop prices its whole catalogue. This is that fix.
///  * A sheet's height is a compromise between covering the map and having room; a route has the
///    whole screen, which is what let the contacts and the catalogue stop competing for it.
///
/// The cost, and it is real: from the map a tap now replaces the map rather than half-covering it,
/// so comparing three nearby shops is three pushes and three pops. Back returns to the same camera.
class ShopCardScreen extends StatefulWidget {
  const ShopCardScreen({super.key, required this.shop});

  /// The whole shop, never an id to look up.
  ///
  /// Everything on this screen except the catalogue is already in hand at every entry point: the map
  /// holds the list it drew its pins from, and `GET /api/home` sends full shop rows that
  /// [HomeShopPreview] simply projects down for the feed. So the card paints complete on its first
  /// frame, with no spinner and no second round trip for facts the app already had.
  final Shop shop;

  @override
  State<ShopCardScreen> createState() => _ShopCardScreenState();
}

class _ShopCardScreenState extends State<ShopCardScreen> {
  @override
  void initState() {
    super.initState();
    // deferred past the first frame: loadProducts sets its busy flag and notifies *before* its first
    // await, and notifying while this element is still being mounted is flutter's "setState() called
    // during build". the same reason MapScreen and MessagesScreen defer theirs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductsController>().loadProducts(widget.shop.id);
    });
  }

  /// Pull-to-refresh re-reads the catalogue, which is the only thing on this screen that changes
  /// while it is open - an owner pricing products in another session, most obviously.
  Future<void> _refresh() {
    return context.read<ProductsController>().loadProducts(widget.shop.id, force: true);
  }

  Future<void> _dial() => _open(Uri.parse('tel:${widget.shop.contactPhone}'));

  /// Hands the coordinates to whatever maps the phone has.
  ///
  /// An `https` yandex.uz url rather than a `yandexmaps://` scheme: it is an ordinary link, so
  /// Yandex Maps claims it as an App Link when installed and a browser shows the same route when it
  /// is not - and it needs no new `<queries>` entry, since the manifest already declares VIEW+https
  /// for the Telegram login link (CLAUDE.md §8).
  ///
  /// `rtext=~lat,lng` is "from wherever I am, to here", which is the question someone looking at a
  /// building-materials shop is actually asking.
  Future<void> _route() {
    final shop = widget.shop;
    return _open(Uri.parse(
      'https://yandex.uz/maps/?rtext=~${shop.latitude},${shop.longitude}&rtt=auto',
    ));
  }

  /// **The return value of `launchUrl` is the signal, not `canLaunchUrl`.** Android 11 package
  /// visibility makes `canLaunchUrl` answer false for perfectly launchable links unless every scheme
  /// is declared, which is how the login flow once reported "Telegram is not installed" on a phone
  /// with Telegram open - see CLAUDE.md §8.
  Future<void> _open(Uri uri) async {
    final strings = Provider.of<LanguageProvider>(context, listen: false).strings;
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('ShopCardScreen: could not open $uri: $e');
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.couldNotOpenExternalApp),
          backgroundColor: AppColors.textDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final shop = widget.shop;

    // gutter, and the same 20 the rest of the app's detail screens use
    const gutter = EdgeInsets.symmetric(horizontal: 20);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        // the name only appears in the bar once the identity card has scrolled under it, which is
        // what `scrolledUnder` gives for free - the card below is the title until then
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        iconTheme: const IconThemeData(color: AppColors.textDark, size: 22),
        title: Text(
          shop.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 17,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryOrange,
        onRefresh: _refresh,
        // a CustomScrollView is a scrollable, so this is the one shape RefreshIndicator works with
        // out of the box - see the trap in CLAUDE.md §8 about a shrink-wrapping child
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _IdentityCard(shop: shop, strings: strings),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _BasketPriceCard(shop: shop, strings: strings),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: strings.callButton,
                        icon: CupertinoIcons.phone_fill,
                        onTap: _dial,
                        isPrimary: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        label: strings.routeButton,
                        icon: CupertinoIcons.location_north_line_fill,
                        onTap: _route,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _ContactsCard(shop: shop, strings: strings, onCallTap: _dial),
              ),
            ),
            SliverPadding(
              padding: gutter.add(const EdgeInsets.only(top: 26, bottom: 12)),
              sliver: SliverToBoxAdapter(
                child: _ProductsHeading(shopId: shop.id, strings: strings),
              ),
            ),
            _ProductsSliver(shopId: shop.id, strings: strings),
            // a tail so the last row of tiles is not flush against the bottom of the screen, plus
            // whatever the gesture bar takes. this route is pushed over the shell, so the floating
            // nav bar is not in the way - only the system inset is.
            SliverToBoxAdapter(
              child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who the shop is: the category glyph, the name, the secondary line, and the placement badge.
///
/// **The glyph is the same one its pin draws** (`ShopCategory.icon`), and the line under the name
/// says in words what that glyph meant. Someone arriving here from the map has just tapped a
/// teardrop with a wrench in it; this is the only place in the app that translates it.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShopAvatar(shop: shop),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        shop.name,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 19,
                          height: 1.2,
                          letterSpacing: -0.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (shop.isVip) ...[
                      const SizedBox(width: 10),
                      const Padding(padding: EdgeInsets.only(top: 2), child: _VipPill()),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                _MetaLine(shop: shop, strings: strings),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(CupertinoIcons.location_solid, color: AppColors.textFaint, size: 12),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        shop.address,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The shop's photo, or the category glyph standing in for it.
///
/// **A 52px tile rather than the full-width cover band a marketplace usually opens with**, and that is
/// about what is in the database rather than about taste: nothing writes `shops.image_url`, so a cover
/// would be 200px of placeholder on every shop in the market - the exact mistake the old sheet's
/// saturated orange banner was. The photo branch is written anyway because the column is real and the
/// feature is only deferred; the day something writes it, this tile fills in on its own.
class _ShopAvatar extends StatelessWidget {
  const _ShopAvatar({required this.shop});

  final Shop shop;

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primarySoft, AppColors.surfaceMuted],
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch (shop.imageFullUrl) {
        // `cover` here and not the `contain` a product tile uses: a shop photo is a storefront or a
        // logo, not a catalogue shot of one object on white, and a small square wants filling
        final String url => Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: (_size * 3).round(),
            // the glyph is what a failed load falls back to, so a dead url is a shop that looks
            // like a shop without a photo rather than a broken image icon
            errorBuilder: (_, _, _) => _CategoryGlyph(shop: shop),
          ),
        _ => _CategoryGlyph(shop: shop),
      },
    );
  }
}

class _CategoryGlyph extends StatelessWidget {
  const _CategoryGlyph({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    return Icon(shop.category.icon, color: AppColors.primaryOrange, size: 22);
  }
}

// rating and category on one line. the rating block only exists when there is a rating - see
// Shop.hasRating, which is false for every shop until a reviews table exists, and "⭐ 0.0" says the
// opposite of what is true.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (shop.hasRating) ...[
          const Icon(CupertinoIcons.star_fill, color: AppColors.starYellow, size: 13),
          const SizedBox(width: 4),
          Text(
            shop.rating.toStringAsFixed(1),
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Container(
            width: 3,
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(color: AppColors.textFaint, shape: BoxShape.circle),
          ),
        ],
        Icon(shop.category.icon, color: AppColors.textFaint, size: 13),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            shop.category.label(strings),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _VipPill extends StatelessWidget {
  const _VipPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.primaryTint),
      ),
      child: const Text(
        'VIP',
        style: TextStyle(
          color: AppColors.primaryOrange,
          fontSize: 10.5,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// What the shared basket costs here, and how that compares to this shop's own market.
///
/// The two facts are drawn from one condition rather than one each: since migration 000013 a shop is
/// in the index only with its whole template priced, so `basketPrice` and `priceTier` are both
/// present or both absent, and branching on them separately would be writing code for a state the
/// database cannot produce.
///
/// **The empty case is a sentence, not a blank.** One unpriced row keeps a shop out, so this is the
/// common case early on - and a customer who tapped a pin and found nothing where a price should be
/// reads that as the app failing, where a line about the shop's own prices reads as the shop's state.
class _BasketPriceCard extends StatelessWidget {
  const _BasketPriceCard({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final basket = shop.basketPrice;
    final tier = shop.priceTier;

    if (basket == null || tier == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(CupertinoIcons.clock, color: AppColors.textFaint, size: 14),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                strings.basketPriceIncomplete,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.basketPrice,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 11.5,
              height: 1.2,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            strings.somAmount(basket),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 24,
              height: 1.15,
              letterSpacing: -0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 11),
          // the full sentence rather than the compact form: this is where someone who tapped a pin
          // reading "−4%" finds out what those four characters meant
          Align(
            alignment: Alignment.centerLeft,
            child: PriceTierBadge(
              tier: tier,
              differencePercent: shop.priceDifferencePercent,
              strings: strings,
            ),
          ),
        ],
      ),
    );
  }
}

/// Address and phone, as a grouped list - and the phone row is a control, not a caption.
class _ContactsCard extends StatelessWidget {
  const _ContactsCard({required this.shop, required this.strings, required this.onCallTap});

  final Shop shop;
  final AppLocalizations strings;
  final VoidCallback onCallTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text(
              strings.shopContactsTitle,
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 11.5,
                letterSpacing: 0.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _DetailRow(
            icon: CupertinoIcons.location_solid,
            label: strings.addressLabel,
            value: shop.address,
          ),
          // indented to line up with the text column, the way grouped ios lists separate rows
          const Padding(
            padding: EdgeInsets.only(left: _DetailRow.textInset),
            child: SizedBox(height: 1, child: ColoredBox(color: AppColors.hairline)),
          ),
          _DetailRow(
            icon: CupertinoIcons.phone_fill,
            label: strings.phoneLabel,
            value: shop.contactPhone,
            onTap: onCallTap,
          ),
        ],
      ),
    );
  }
}

// label above value, with a muted icon in the gutter. the label being small and faint is what lets
// the value stay readable at a normal weight instead of needing bold to stand out.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;

  /// null for a row that is only information. the phone row passes one, and gets a chevron with it -
  /// a row that dials without looking any different from the one above it is a row nobody taps.
  final VoidCallback? onTap;

  /// left padding + icon width + gap - where the text column starts
  static const double textInset = 16 + 16 + 12;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 16, child: Icon(icon, color: AppColors.textFaint, size: 15)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11.5,
                    height: 1.2,
                    letterSpacing: 0.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: onTap == null ? AppColors.textDark : AppColors.primaryOrange,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 8),
              child: Icon(CupertinoIcons.chevron_right, color: AppColors.textFaint, size: 14),
            ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

// the two things somebody who opened a shop wants to do. one filled, one outlined: they are not
// peers - a phone number is the reason most of these cards are opened at all.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final foreground = isPrimary ? Colors.white : AppColors.textDark;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        // the coloured glow is the one place brand orange bleeds outside its own shape, and it is
        // reserved for a primary action - see AppShadows.accent
        boxShadow: isPrimary ? AppShadows.accent(AppColors.primaryOrange) : AppShadows.card,
      ),
      child: Material(
        color: isPrimary ? AppColors.primaryOrange : AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: isPrimary ? null : Border.all(color: AppColors.hairline),
            ),
            child: SizedBox(
              height: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
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
      ),
    );
  }
}

// "Товары" plus how many, matching the section headings on the home feed
class _ProductsHeading extends StatelessWidget {
  const _ProductsHeading({required this.shopId, required this.strings});

  final int shopId;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final count = context.select<ProductsController, int>(
      (c) => c.productsFor(shopId).where((p) => p.hasPrice).length,
    );

    return Row(
      children: [
        Text(
          strings.shopProductsSectionTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 17,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// The catalogue, as a sliver.
///
/// **Only priced products.** An unpriced row is useful to the *owner*, which is why their own grid
/// shows it, but to a customer it is a tile that answers no question - and on a fresh shop there
/// would be a hundred of them burying the handful that are priced.
///
/// A shop with nothing priced gets a line saying so rather than a hidden section: a missing section
/// reads as "this app has no products area", which is a different and wrong message.
class _ProductsSliver extends StatelessWidget {
  const _ProductsSliver({required this.shopId, required this.strings});

  final int shopId;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ProductsController>(context);

    final priced = [
      for (final product in controller.productsFor(shopId))
        if (product.hasPrice) product,
    ];

    if (controller.isLoadingFor(shopId) && !controller.hasLoaded(shopId)) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 34),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryOrange),
            ),
          ),
        ),
      );
    }

    if (priced.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.hairline),
            ),
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
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // a sliver grid, so a hundred-product catalogue builds one screenful of tiles and fires one
      // screenful of image requests - see the class comment on ShopCardScreen
      sliver: ProductSliverGrid(
        tiles: [
          for (final Product product in priced)
            ProductTile(product: product, strings: strings),
        ],
      ),
    );
  }
}
