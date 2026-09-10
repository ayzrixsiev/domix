import 'dart:async';

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
/// **Five cards, always, sold or not** - an unsold slot is what tells an owner scrolling past that a
/// place is available, so it is drawn as the real card with its values missing.
///
/// **The loop**: `PageView.builder` is unbounded *forwards* only, so it starts deep inside a virtual
/// range and maps the index onto the real list with a modulo. The starting page is a multiple of the
/// slot count **plus the centre offset**, and Dart's `%` is Euclidean.
///
/// **It advances on its own**, forwards, into that unbounded range - see [autoAdvanceEvery]. Every
/// placement in the section gets shown to somebody who never touches the strip, and a finger on it
/// always outranks the clock.
class VipShopsCarousel extends StatefulWidget {
  const VipShopsCarousel({super.key, required this.slots, this.onShopTap});

  /// **Mirrors `vipShopsLimit` in the Go handler** - units of a thing that is sold, not a page size.
  /// The app draws whichever is larger, this or what actually arrived, so the two disagreeing can
  /// never hide a placement somebody paid for.
  static const int slotCount = 5;

  /// The ring from [vipSlotRing], arranged centre-outwards. The empty guard at the top of [build] is
  /// real, not defensive padding: `index % 0` below is a division by zero.
  final List<HomeShopPreview?> slots;

  /// Card + peek: the page is this fraction of the screen and the leftover is split between the two
  /// neighbours, so an edge of the previous and next slot is always visible.
  ///
  /// **The peek and the card width are one dial pulled in opposite directions** - what a reader sees is
  ///
  ///     W × (1 − viewportFraction) / 2   −   cardGap   −   (viewportFraction × W × scaleDrop) / 2
  ///
  /// ~13px on a 360dp phone. Widening further means finding those pixels in the recede.
  static const double viewportFraction = 0.87;

  /// part of the peek arithmetic above rather than free spacing - every point of it comes off the
  /// sliver of the neighbour that is visible
  static const double cardGap = 4;

  /// Fixed, because a `PageView` needs a bounded height. **A `Column` inside a fixed-height card
  /// fails by overflowing, not by scrolling** - silent in release - so adding a line means raising
  /// this number. **The empty card is built to exactly the same height.**
  static const double cardHeight = 232;

  /// How long a card holds the centre before the strip moves on by itself. **The section is an advert
  /// and it has five slots, so a strip that only ever shows its first card is four fifths unsold** -
  /// this is what puts the other placements in front of a customer who never swipes.
  static const Duration autoAdvanceEvery = Duration(seconds: 3);

  /// Opens the shop card. **A paid placement that does nothing when it is tapped is the worst card on
  /// the screen to have that bug.** An empty slot is not tappable, which is why the handler is wired
  /// per card rather than around the whole strip.
  final ValueChanged<Shop>? onShopTap;

  @override
  State<VipShopsCarousel> createState() => _VipShopsCarouselState();
}

class _VipShopsCarouselState extends State<VipShopsCarousel> {
  /// how many full cycles sit behind the opening page
  static const int _loopOrigin = 5000;

  /// How far an off-centre card recedes. **The same dial as [VipShopsCarousel.viewportFraction],
  /// pulled the other way**: shrink about the centre eats into the neighbour's visible sliver, so 0.04
  /// is what paid for the wider card, and wanting the recede back means narrowing it again.
  static const double _offCentreScaleDrop = 0.04;

  /// Slower than a flung swipe, deliberately: nobody asked for this movement, so it has to read as
  /// the strip drifting rather than as the screen changing under the finger.
  static const Duration _autoAdvanceGlide = Duration(milliseconds: 480);

  late final PageController _controller;
  late final int _initialPage;

  /// Runs for the life of the widget; the pointer handlers in [build] are the only thing that stops
  /// it. **Null means a finger is on the strip** - or that this is disposed.
  Timer? _autoAdvance;

  @override
  void initState() {
    super.initState();
    // an exact multiple of the ring size, offset to the middle position: `vipSlotRing` fills from there
    // outwards, so this is what makes the first sold placement the card the customer is looking at -
    // and ListVipShops orders on basket price, so that card is the cheapest of the placements.
    // the max(1, ...) only covers a caller passing an empty list, where build returns early anyway.
    final size = widget.slots.isEmpty ? 1 : widget.slots.length;
    _initialPage = _loopOrigin * size + size ~/ 2;
    _controller = PageController(
      viewportFraction: VipShopsCarousel.viewportFraction,
      initialPage: _initialPage,
    );
    _startAutoAdvance();
  }

  @override
  void dispose() {
    // before the controller, not after: a tick that fired against a disposed PageController would
    // throw from a timer callback, where nothing on screen would say which widget it came from
    _stopAutoAdvance();
    _controller.dispose();
    super.dispose();
  }

  /// (Re)starts the dwell clock, which is why it cancels first: a swipe that ends 2.9s into a tick
  /// leaves the card it landed on a whole dwell rather than the 100ms that were left of the last one.
  void _startAutoAdvance() {
    _autoAdvance?.cancel();
    _autoAdvance = Timer.periodic(VipShopsCarousel.autoAdvanceEvery, (_) {
      // there is no page to advance from until the first layout, and `nextPage` asserts on that
      if (!_controller.hasClients || !_controller.position.hasContentDimensions) return;
      // forwards forever - the virtual range is unbounded in exactly this direction
      _controller.nextPage(duration: _autoAdvanceGlide, curve: Curves.easeInOut);
    });
  }

  void _stopAutoAdvance() {
    _autoAdvance?.cancel();
    _autoAdvance = null;
  }

  /// Reading `.page` before the first layout throws, so this falls back to the starting page.
  double get _currentPage {
    if (_controller.hasClients && _controller.position.hasContentDimensions) {
      return _controller.page ?? _initialPage.toDouble();
    }
    return _initialPage.toDouble();
  }

  /// Null when there is nothing to open - an unsold slot, or no handler - which leaves the card inert
  VoidCallback? _tapHandlerFor(HomeShopPreview? preview) {
    final onShopTap = widget.onShopTap;
    if (preview == null || onShopTap == null) return null;
    return () => onShopTap(preview.shop);
  }

  @override
  Widget build(BuildContext context) {
    // nothing to loop over: `index % 0` below is a division by zero
    if (widget.slots.isEmpty) return const SizedBox.shrink();

    final strings = Provider.of<LanguageProvider>(context).strings;

    return SizedBox(
      height: VipShopsCarousel.cardHeight,
      // **a Listener, not a GestureDetector**: this only wants to know that a finger is down, and
      // claiming the gesture would take the swipe away from the PageView underneath it. touching
      // pauses the clock and letting go restarts it, so a tick can never fire mid-drag and animate
      // the page out from under the finger holding it. a touch that lands *during* a glide needs
      // nothing here - a Scrollable holds its own driven animation the moment a pointer arrives.
      child: Listener(
        onPointerDown: (_) => _stopAutoAdvance(),
        onPointerUp: (_) => _startAutoAdvance(),
        onPointerCancel: (_) => _startAutoAdvance(),
        child: PageView.builder(
          controller: _controller,
          // unbounded: the builder is asked for whatever page the user swipes to, forever
          itemCount: null,
          padEnds: true,
          // the viewport is exactly [cardHeight] tall, so its default hard edge would cut the shadow off at
          // the card's own bottom edge. Clip.none lets the 30px ambient blur spill into the whitespace above
          // and below the strip, which is where a lift lives.
          clipBehavior: Clip.none,
          itemBuilder: (context, index) {
            final slot = widget.slots[index % widget.slots.length];

            // rebuilds on every scroll tick, so the off-centre cards settle back as the swipe moves
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // 0 for the card the viewport is centred on, 1 for anything a full page away, fractional mid-drag
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
                  // PressableScale rather than an ink ripple: a ripple is a faint wash inside a 232px card that never
                  // moves. its onTapCancel matters here - the PageView claims the gesture the moment a swipe starts,
                  // and without it the card would stay shrunk after every failed tap.
                  onTap: _tapHandlerFor(slot),
                  child: slot == null
                      ? _EmptySlotCard(strings: strings)
                      : _VipShopCard(shop: slot, strings: strings),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


// ── the cards: a sold slot and an unsold one are **the same card**, and only their text differs.
// the unsold one was drawn recessed for a while and rejected on sight - four faded frames around one
// real card made the strip look broken rather than available. ──

/// The chrome every card wears, sold or not. One `const` rather than two identical `BoxDecoration`s,
/// because the moment they are two, one of them grows a different shadow. `floating` with no border:
/// an outline round an already-lifted shape flattens it again.
const BoxDecoration _cardSurface = BoxDecoration(
  color: AppColors.surfaceWhite,
  borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
  boxShadow: AppShadows.floating,
);

/// 14 all round, 16 at the bottom: the badge is the last thing on the card and has to sit clear of
/// the edge rather than tucked against it.
const EdgeInsets _cardContentPadding = EdgeInsets.fromLTRB(14, 12, 14, 16);

// white, with the shop's identity carried by a soft branded banner rather than by an inverted
// colour scheme - and that banner is where a real shop photo will go once upload exists
class _VipShopCard extends StatelessWidget {
  const _VipShopCard({required this.shop, required this.strings});

  final HomeShopPreview shop;
  final AppLocalizations strings;

  /// moves with [VipShopsCarousel.cardHeight] rather than independently - it is the largest element
  /// on the card, so leaving it alone would read as the proportions shifting
  static const double bannerHeight = 120;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _cardSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the shop's name lives on the banner, opposite its rating. it used to head the content block, so
          // the tallest, boldest thing on the card sat *under* a large empty image - this pairs the two facts
          // that identify a shop and leaves the block one job: what it costs.
          _Banner(
            name: shop.name,
            // hidden entirely until there are reviews - with no reviews table every shop reads 0.0
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

                  // real gaps rather than `spaceBetween`: distributed slack changed the spacing with the content, so
                  // the block read as compressed at the top and stranded at the bottom
                  const SizedBox(height: 12),

                  // **a card here can legitimately have no price**: ListVipShops left-joins the basket index, so a
                  // shop that has not finished pricing shows its name, its address and no comparison. it used to
                  // inner-join, which meant somebody paid for a placement and saw nothing.
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

                  // soaks up the leftover, so the block stays top-aligned and the bottom padding is the real distance
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

/// An unsold placement: the real card, with field names where its values would be.
///
/// **A piece of the product, not a loading state** - a skeleton says "wait", a faded frame says
/// "broken", and this has to say "this space is for sale". **No invented shop anywhere in it**; the
/// rating is the one exception ([kSlotRating], a fixed 5) and describes the field.
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
            // shown in full here, unlike a real card: on this one the pill is part of what is being described,
            // and a gap where it goes would leave the layout half-explained
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
                  // sits where the basket total does, at the same size and weight - that is the point being made.
                  // `textGrey` is the only difference, so it reads as the name of a figure rather than as a figure.
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

/// shared, so the empty card's caption sits on exactly the same baseline as the figure it replaces
const TextStyle _priceStyle = TextStyle(
  color: AppColors.textDark,
  fontSize: 17,
  height: 1.15,
  letterSpacing: -0.4,
  fontWeight: FontWeight.w700,
);

/// shared, so the two cards cannot end up with different gaps or a different icon size
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

/// The card's cover: a placeholder where a shop photo will go, the name at top-left and the rating
/// at top-right. **Sold and unsold slots share this widget outright**, which is what makes the two
/// line up pixel for pixel as the carousel snaps.
///
/// The name is brand orange with no scrim - over a pale peach placeholder there is nothing to
/// protect text from. When photo upload lands, the fix is the white pill the rating badge uses.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.name,
    required this.ratingLabel,
    this.isPlaceholder = false,
  });

  final String name;

  /// Already formatted by the caller, and **null when there is nothing to show** - which drops the
  /// whole pill rather than just its number, since an empty white badge reads as a failed load.
  final String? ratingLabel;

  /// Draws the name as a field label rather than as an identity, so «Название магазина» cannot be
  /// mistaken for a shop actually called that. Brand orange is reserved for a real name.
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

            // identity on the left, quality on the right, the way a listing card is read
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
