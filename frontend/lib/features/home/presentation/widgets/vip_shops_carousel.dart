import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

/// The five VIP slots, as a page-snapping carousel that loops endlessly in both directions.
///
/// **Five cards, always, whether or not anybody has bought one.** VIP placement is a product with a
/// fixed number of units, and an unsold slot is not a gap to hide - it is what tells a shop owner
/// scrolling past that a place is still available. So the empty card is drawn as the real card with
/// its values missing rather than as a skeleton or a "coming soon" tile: an owner sees the shape of
/// what they would be buying. See [_EmptySlotCard].
///
/// **How the loop works.** `PageView.builder` with a null `itemCount` is unbounded *forwards* only:
/// the underlying `SliverChildBuilderDelegate` has no concept of a negative index, so there is no
/// built-in way to scroll backwards forever. The standard solution, and the one every carousel
/// package uses, is to start deep inside a very large virtual range instead: the item index is
/// mapped onto the real list with a modulo, so page 25 000 and page 25 005 both render slot 0.
/// Swiping forward never ends, and backwards there are [_loopOrigin] × [slotCount] pages to burn
/// through before index 0 is reachable - about twenty-five thousand swipes.
///
/// Two details make that safe rather than a trick:
///  * The starting page is an exact multiple of the slot count **plus the centre offset**, so the
///    carousel opens parked on the middle slot - which is where [vipSlotRing] puts the first shop.
///  * Dart's `%` is Euclidean - `-1 % 5` is `4`, not `-1` - so the mapping stays correct even if an
///    index below the origin is ever built.
///
/// **The old `initialPage` trap is designed out rather than worked around.** A `PageController`'s
/// `initialPage` cannot change once it is built, and the opening page used to depend on how many VIP
/// shops had arrived - a number that lands *after* the first frame - so the home screen had to key
/// this widget on that count to force a fresh `State`. The slot count is a constant, so the opening
/// page is one too; the key stays (on `slots.length`) only for the case where a future backend sends
/// more placements than this build expects and the ring grows to hold them.
class VipShopsCarousel extends StatefulWidget {
  const VipShopsCarousel({super.key, required this.slots, this.onShopTap});

  /// How many placements exist. **Mirrors `vipShopsLimit` in the Go handler**, which is the number of
  /// units of a thing that is sold rather than a page size - see the note on that constant. The app
  /// draws whichever is larger, this or what actually arrived, so the two disagreeing can never hide
  /// a placement somebody paid for.
  static const int slotCount = 5;

  /// The ring, from [vipSlotRing]: a real shop or `null` per position, arranged centre-outwards so
  /// the first sold placement is the card on screen when the section scrolls into view.
  ///
  /// May be empty only if a caller builds it that way - the guard at the top of [build] is real, not
  /// defensive padding: `index % 0` below is a division by zero, not an empty carousel.
  final List<HomeShopPreview?> slots;

  /// Card + peek. The page is this fraction of the screen; the leftover is split between the two
  /// neighbours, so an edge of the previous and next slot is always visible and the strip reads as
  /// continuous rather than as a single card.
  ///
  /// **0.87, widened from 0.84, and the sliver of the neighbours was held constant while doing it.**
  /// The two are one dial pulled in opposite directions, so the arithmetic is worth writing down.
  /// How much of the next card a reader actually sees is
  ///
  ///     W × (1 − viewportFraction) / 2   −   cardGap   −   (viewportFraction × W × scaleDrop) / 2
  ///     └─ the page's own overhang ─┘        └ padding ┘   └─ what the off-centre shrink eats ─┘
  ///
  /// On a 360dp phone that was `28.8 − 5 − 10.6 ≈ 13px` at 0.84 with a 0.07 drop. Widening alone
  /// would have taken it to ~8px, which is where the strip stops reading as "there are more of
  /// these" and starts looking like one card alone on the page. Paying for the width out of
  /// [_offCentreScaleDrop] (0.07 → 0.04) and the gap (5 → 4) gives `23.4 − 4 − 6.3 ≈ 13px` - the
  /// same peek on a card 13dp wider.
  ///
  /// **Widening further means finding those pixels somewhere**, and there is nowhere left except the
  /// recede, which is already soft.
  static const double viewportFraction = 0.87;

  /// The gap between one card and the next, applied as horizontal padding inside each page. Part of
  /// the peek arithmetic above rather than free spacing - every point of it comes off the sliver of
  /// the neighbour that is visible.
  static const double cardGap = 4;

  /// Fixed, because a `PageView` needs a bounded height and a carousel whose cards changed height
  /// per shop would jolt as it snapped.
  ///
  /// 252, up from 232 - the section is the one the eye should land on first and it was reading small
  /// beside a full-width row. The extra 20 is split 12 into the banner and 8 into the content block,
  /// so the proportions are unchanged and every line keeps the slack it had.
  ///
  /// **A `Column` inside a fixed-height card fails by overflowing, not by scrolling** - silent in
  /// release, a 12px striped bar in debug - so adding a line here means raising this number. Growing
  /// it is always safe; shrinking it is what needs checking. **The empty card is built to exactly the
  /// same height**, or the section would change height as placements were sold.
  static const double cardHeight = 252;

  /// Opens the shop card. **A paid placement that does nothing when it is tapped is the worst card
  /// on the screen to have that bug**, which is what this carousel had until the shop card became a
  /// route: only the map could open a shop.
  ///
  /// An empty slot is not tappable - there is nothing behind it - which is why the handler is wired
  /// per card rather than around the whole strip.
  final ValueChanged<Shop>? onShopTap;

  @override
  State<VipShopsCarousel> createState() => _VipShopsCarouselState();
}

class _VipShopsCarouselState extends State<VipShopsCarousel> {
  /// how many full cycles sit behind the opening page
  static const int _loopOrigin = 5000;

  /// How far an off-centre card recedes, as a fraction of its size. Scale and nothing else.
  ///
  /// **This is the same dial as [VipShopsCarousel.viewportFraction], pulled the other way.** A card
  /// scales about its own centre, so every point of shrink slides its inner edge *away* from the
  /// screen and eats directly into the neighbour's visible sliver - see the arithmetic on that
  /// constant.
  ///
  /// 0.12 plus a 28% fade was tried on 2026-08-18 and reverted the same day: the recede was very
  /// visible and the neighbours had all but vanished, which is the wrong trade - the peek is what
  /// says "there are more of these".
  ///
  /// **0.04 now, down from 0.07, and that reduction is what paid for the wider card.** The recede is
  /// subtle at this value, which is the accepted cost: asked to choose, the founder wanted a bigger
  /// card with the neighbours still showing. Wanting the recede back means narrowing the card again.
  static const double _offCentreScaleDrop = 0.04;

  late final PageController _controller;
  late final int _initialPage;

  @override
  void initState() {
    super.initState();
    // an exact multiple of the ring size, offset to the middle position. `vipSlotRing` fills from
    // that position outwards, so this is what makes the first sold placement the card the customer
    // is looking at rather than something two swipes away past empty ones.
    //
    // the `max(1, ...)` only covers a caller passing an empty list, where build returns early anyway.
    final size = widget.slots.isEmpty ? 1 : widget.slots.length;
    _initialPage = _loopOrigin * size + size ~/ 2;
    _controller = PageController(
      viewportFraction: VipShopsCarousel.viewportFraction,
      initialPage: _initialPage,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The page the viewport is centred on, as a fraction. Reading `.page` before the first layout
  /// throws, so this falls back to the starting page until the controller is attached.
  double get _currentPage {
    if (_controller.hasClients && _controller.position.hasContentDimensions) {
      return _controller.page ?? _initialPage.toDouble();
    }
    return _initialPage.toDouble();
  }

  /// Null when there is nothing to open - an unsold slot, or no handler - which is what leaves the
  /// card inert rather than animating a press that leads nowhere.
  VoidCallback? _tapHandlerFor(HomeShopPreview? preview) {
    final onShopTap = widget.onShopTap;
    if (preview == null || onShopTap == null) return null;
    return () => onShopTap(preview.shop);
  }

  @override
  Widget build(BuildContext context) {
    // nothing to loop over: `index % 0` below is a division by zero. unreachable from the home
    // screen, which always passes a full ring.
    if (widget.slots.isEmpty) return const SizedBox.shrink();

    final strings = Provider.of<LanguageProvider>(context).strings;

    return SizedBox(
      height: VipShopsCarousel.cardHeight,
      child: PageView.builder(
        controller: _controller,
        // unbounded: the builder is asked for whatever page the user swipes to, forever
        itemCount: null,
        padEnds: true,
        itemBuilder: (context, index) {
          final slot = widget.slots[index % widget.slots.length];

          // rebuilds on every scroll tick so the off-centre cards can settle back. it is what
          // makes the swipe feel like cards moving through a viewport rather than a filmstrip
          // sliding sideways.
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // 0 for the card the viewport is centred on, 1 for anything a full page away or
              // further, and everything between while a drag is in flight
              final distance = (_currentPage - index).abs().clamp(0.0, 1.0);

              return Transform.scale(
                scale: 1 - distance * _offCentreScaleDrop,
                child: child,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VipShopsCarousel.cardGap,
              ),
              child: PressableScale(
                // PressableScale rather than an ink ripple, for the reason it exists: a ripple
                // spreads *inside* the shape, so on a 232px bordered card it is a faint grey wash
                // in a box that never moves. its onTapCancel also matters here specifically - the
                // PageView claims the gesture the moment a swipe starts, and without that the card
                // would stay shrunk after every failed tap.
                onTap: _tapHandlerFor(slot),
                child: slot == null
                    ? _EmptySlotCard(strings: strings)
                    : _VipShopCard(shop: slot, strings: strings),
              ),
            ),
          );
        },
      ),
    );
  }
}


// ─────────────────────────────── the cards ───────────────────────────────
//
// A sold slot and an unsold one are **the same card**, and only their text differs.
//
// The unsold one was drawn recessed for a while - page-coloured, outlined, no shadow - on the
// reasoning that a well cut into the page reads as "empty" before a word of it is read. That was
// rejected on sight: this is the section the eye lands on first, and four faded frames around one
// real card made the whole strip look broken rather than look available. **An unsold slot is a
// product being advertised, and an advertisement has to be as handsome as the thing it is selling.**
//
// So the surface, the border, the shadow and the branded banner are shared literally - the same
// `_cardSurface` object and the same `_Banner` widget - and what says "unsold" is that the fields
// carry their own names instead of a shop's values, in muted type. See [_EmptySlotCard].

/// The chrome every card in this carousel wears, sold or not.
///
/// One `const` rather than two identical `BoxDecoration`s, because the moment they are two, one of
/// them grows a different shadow. `raised` and not `card`: this is the section the eye should land on
/// first, and it is the one surface here big enough that a barely-there shadow just looks like a
/// rendering artefact rather than depth.
const BoxDecoration _cardSurface = BoxDecoration(
  color: AppColors.surfaceWhite,
  borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
  // `Border.fromBorderSide`, not `Border.all` - the latter is a factory and cannot be const
  border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
  boxShadow: AppShadows.raised,
);

/// The padding around a card's content block. 14 all round, and 16 at the bottom: the badge is the
/// last thing on the card and needs to sit clear of the edge rather than tucked against it.
const EdgeInsets _cardContentPadding = EdgeInsets.fromLTRB(14, 12, 14, 16);

// these cards were a near-black gradient, which put the single darkest object in the app right at
// the top of its brightest screen. they are white now, with the shop's identity carried by a soft
// branded banner instead of by an inverted colour scheme - and that banner is where a real shop
// photo will go once photo upload exists, so the layout will not need rethinking then.
class _VipShopCard extends StatelessWidget {
  const _VipShopCard({required this.shop, required this.strings});

  final HomeShopPreview shop;
  final AppLocalizations strings;

  /// 132, up from 120 with the card's own height. The cover is the largest single element here, so it
  /// takes most of the extra rather than leaving a taller card with the same picture in it.
  static const double bannerHeight = 132;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _cardSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the shop's name lives on the banner, opposite its rating. it used to head the content
          // block below, which meant the tallest, boldest thing on the card sat *under* a large
          // empty image - the eye landed on the placeholder first and the identity second. moving
          // it up pairs the two facts that identify a shop on one line and leaves the content block
          // to do one job: what it costs.
          _Banner(
            name: shop.name,
            // hidden entirely until there are reviews - with no reviews table every shop reads 0.0,
            // and "⭐ 0.0" says the opposite of what is true. See Shop.hasRating.
            ratingLabel: shop.hasRating ? shop.rating.toStringAsFixed(1) : null,
          ),
          Expanded(
            child: Padding(
              padding: _cardContentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AddressLine(
                    text: shop.address,
                    color: AppColors.textGrey,
                  ),

                  // the three below are separated by real gaps rather than by `spaceBetween`. the
                  // old card distributed its slack, so the spacing changed with the content and the
                  // block read as compressed at the top and stranded at the bottom; fixed gaps make
                  // the rhythm the same on every card, and the Spacer takes the leftover.
                  const SizedBox(height: 12),

                  // **a card here can now legitimately have no price.** ListVipShops used to inner-
                  // join the basket index, so a placement did not appear at all until its owner had
                  // priced every template row - which meant somebody paid and saw nothing. it left-
                  // joins now (§5), so a shop that has not finished shows its name, its address and
                  // no comparison, which is the truth about it.
                  //
                  // the price is the largest thing in the content block on purpose: it is what the
                  // section is for, and the address above it is context, not the point.
                  if (shop.basketPrice case final basket?)
                    Text(
                      strings.somAmount(basket),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _priceStyle,
                    ),

                  if (shop.priceTier case final tier?) ...[
                    const SizedBox(height: 10),
                    PriceTierBadge(
                      tier: tier,
                      differencePercent: shop.priceDifferencePercent,
                      strings: strings,
                    ),
                  ],

                  // soaks up whatever is left, so the block stays top-aligned and the bottom
                  // padding above is the real distance to the card's edge
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An unsold placement: the real card, with the field names where its values would be.
///
/// **This is a piece of the product, not a loading state**, and the difference decides how it looks.
/// A skeleton says "wait"; a faded frame says "broken". What this has to say is "this space is for
/// sale and here is exactly what you would get", to a shop owner scrolling the home screen of their
/// own app - which is the cheapest advertising channel Domix has. So it is drawn at full strength:
/// the same white surface, the same shadow, the same branded banner.
///
/// What separates it from a sold slot is the *text*. Every field carries its own name in muted type
/// instead of a shop's value, and **no invented shop is written anywhere in it** - not a name, not a
/// street, not a price, not a percentage. A plausible-looking fake in the one section that is sold is
/// how a demo turns into a complaint. The rating is the single exception ([kSlotRating], a fixed 5),
/// and it describes the field rather than claiming anything about anybody.
class _EmptySlotCard extends StatelessWidget {
  const _EmptySlotCard({required this.strings});

  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _cardSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Banner(
            name: strings.slotShopNameLabel,
            // shown in full here, unlike on a real card where the pill is hidden until there are
            // reviews: on this card the pill is part of what is being described, and a gap where it
            // goes would leave the layout half-explained.
            ratingLabel: kSlotRating,
            isPlaceholder: true,
          ),
          Expanded(
            child: Padding(
              padding: _cardContentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AddressLine(
                    text: strings.slotAddressLabel,
                    color: AppColors.textFaint,
                  ),
                  const SizedBox(height: 12),
                  // sits where the basket total does, at the same size and weight - that is the
                  // point being made. `textGrey` rather than `textDark` is the only difference, so
                  // it reads as the name of a figure rather than as a figure.
                  Text(
                    strings.slotBasketLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _priceStyle.copyWith(color: AppColors.textGrey),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    strings.slotComparisonLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The basket total's type, shared so the empty card's caption sits on exactly the same baseline as
/// the figure it stands in for.
const TextStyle _priceStyle = TextStyle(
  color: AppColors.textDark,
  fontSize: 17,
  height: 1.15,
  letterSpacing: -0.4,
  fontWeight: FontWeight.w700,
);

/// A pin glyph and one line of text - the address on a sold card, the word «Адрес» on an unsold one.
/// Shared so the two cannot end up with different gaps or a different icon size.
class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(CupertinoIcons.location_solid, color: AppColors.textFaint, size: 11),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

/// The card's cover area: a placeholder where a shop photo will go, with the shop's name at the
/// top-left and its rating at the top-right, on one line.
///
/// **Sold and unsold slots share this widget outright**, which is what guarantees the two line up
/// pixel for pixel as the carousel snaps between them. [isPlaceholder] changes the name's colour and
/// weight and nothing else.
///
/// **The name is brand orange on the bare placeholder, with no scrim behind it.** A dark gradient
/// across the top was tried and removed: over a pale peach placeholder there is nothing to protect
/// text from, so all it did was put a grey smear across the top third of every card.
///
/// That leaves a real problem for the day photo upload lands - orange text on an arbitrary
/// photograph will not always be legible. The fix then is the treatment already on this card: a
/// white pill, the same as the rating badge on the right, which works over any image and keeps the
/// two ends of the line symmetrical. Adding it now would be solving a problem that does not exist
/// yet against a placeholder that will be deleted.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.name,
    required this.ratingLabel,
    this.isPlaceholder = false,
  });

  final String name;

  /// Already formatted by the caller - `"4.8"` for a rated shop, [kSlotRating] on an unsold slot, and
  /// **null when there is nothing to show**, which drops the whole pill rather than just its number.
  /// An empty white badge beside the name would read as a card that failed to load something.
  ///
  /// A `String?` rather than a `double?` so the two callers can differ without this widget having to
  /// know which of them it is drawing for.
  final String? ratingLabel;

  /// Draws the name as a field label rather than as an identity: `textGrey` and one weight down, so
  /// «Название магазина» cannot be mistaken for a shop actually called that. Brand orange is
  /// reserved for a real name.
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md - 1)),
      child: Container(
        height: _VipShopCard.bannerHeight,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primarySoft, AppColors.surfaceMuted],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                CupertinoIcons.building_2_fill,
                color: AppColors.primaryOrange.withValues(alpha: 0.38),
                size: 34,
              ),
            ),

            // name and rating on one line: identity on the left, quality on the right, the way a
            // listing card is read.
            Positioned(
              top: 10,
              left: 12,
              right: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isPlaceholder ? AppColors.textGrey : AppColors.primaryOrange,
                        fontSize: 16,
                        height: 1.2,
                        letterSpacing: -0.2,
                        fontWeight: isPlaceholder ? FontWeight.w600 : FontWeight.w700,
                      ),
                    ),
                  ),
                  if (ratingLabel case final rating?) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        boxShadow: AppShadows.card,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.star_fill, color: AppColors.starYellow, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            rating,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
