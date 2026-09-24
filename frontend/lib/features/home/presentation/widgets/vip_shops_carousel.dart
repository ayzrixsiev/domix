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
            // the position in the ring, not the virtual page: the same slot keeps the same photo
            // however many times the loop comes back round to it
            final slotIndex = index % widget.slots.length;
            final slot = widget.slots[slotIndex];

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
                  child: _SlotCard(shop: slot, slotIndex: slotIndex, strings: strings),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


// ── the card: **a sold slot and an unsold one are one widget**, and only their text and its colour
// differ. the unsold one was drawn recessed for a while and rejected on sight - four faded frames
// around one real card made the strip look broken rather than available. ──

/// One VIP slot: a photo with the paid tag on it, and a white sheet of facts riding over its bottom
/// edge.
///
/// **The sheet's top corners are round and the card's are not** - that curve is the whole separation
/// between the photo and the text, in place of a rule or a colour change, and it is what makes the
/// photo read as being *behind* the card rather than as its first row.
///
/// The facts run in the order a buyer checks them: who, where, then what the basket costs and how
/// that compares to the market - the comparison sitting on the price's own line because it only
/// means anything next to the number it qualifies.
class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.shop, required this.slotIndex, required this.strings});

  /// **Null is an unsold placement**, not missing data: the card is drawn in full with the names of
  /// its fields where the values go. Nothing here may become a plausible value - the one section of
  /// the app that is sold is the last place an invented shop belongs.
  final HomeShopPreview? shop;

  /// Which of the five photos this card wears - see [_SlotPhoto].
  final int slotIndex;

  final AppLocalizations strings;

  /// How much of the card the photo gets before the sheet starts. The sheet takes the rest exactly,
  /// so this and [VipShopsCarousel.cardHeight] are the only two numbers that decide the split -
  /// adding a line to the sheet means moving this one down, not stretching the card.
  static const double photoHeight = 132;

  /// how far the sheet's rounded shoulders climb back over the photo
  static const double sheetOverlap = 14;

  @override
  Widget build(BuildContext context) {
    final shop = this.shop;
    final isPlaceholder = shop == null;

    // **the empty slot is the only card that shows a rating.** there is no reviews table, so a real
    // shop has no rating to show - on the slot the pill is part of what a placement is being sold as.
    final ratingLabel = shop == null ? kSlotRating : null;

    return DecoratedBox(
      decoration: _cardSurface,
      // the shadow is on the DecoratedBox outside and the clip inside it: clipping a shape that casts
      // a shadow would cut the shadow off at the same edge
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
        child: Stack(
          children: [
            // the strip plus the sheet's own corner radius, not the whole card: the sheet is opaque
            // below its shoulders, so those extra points are exactly what the rounded corners cut
            // away from it - stopping at [photoHeight] would show two white notches instead of photo
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: photoHeight + AppRadius.md,
              child: _SlotPhoto(slotIndex: slotIndex),
            ),

            // the tag rides on the photo, where a paid placement announces itself before anything is read
            const Positioned(top: 12, left: 12, child: _VipTag()),

            if (ratingLabel case final rating?)
              Positioned(top: 12, right: 12, child: _RatingPill(rating: rating)),

            Positioned(
              left: 0,
              right: 0,
              top: photoHeight - sheetOverlap,
              bottom: 0,
              child: _FactsSheet(shop: shop, isPlaceholder: isPlaceholder, strings: strings),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chrome the card wears. `floating` with no border: an outline round an already-lifted shape
/// flattens it again.
const BoxDecoration _cardSurface = BoxDecoration(
  color: AppColors.surfaceWhite,
  borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
  boxShadow: AppShadows.floating,
);

/// The storefront behind the card.
///
/// **Five files, chosen by slot position rather than by shop**, because a shop has no photo of its
/// own yet: the section is what VIP is *sold as*, so it has to look like the placement a buyer is
/// paying for rather than like an empty frame. An unsold slot gets one too - its text already says
/// «Название магазина» in grey, and a photo is the part of the advert being demonstrated.
/// **Swapping this for a real upload means one field on [HomeShopPreview] and this widget**, nothing
/// around it.
///
/// Each file is already cut to this box (1024x512 for a ~305x152dp slot, which is 3x on a phone),
/// so `cover` is a no-op crop rather than a decision made at runtime.
class _SlotPhoto extends StatelessWidget {
  const _SlotPhoto({required this.slotIndex});

  static const List<String> _photos = [
    'assets/decorations/vip/vip1.webp',
    'assets/decorations/vip/vip2.webp',
    'assets/decorations/vip/vip3.webp',
    'assets/decorations/vip/vip4.webp',
    'assets/decorations/vip/vip5.webp',
  ];

  /// the position in the ring - modulo'd below, because the ring grows past five when more
  /// placements arrive than there are slots
  final int slotIndex;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // under the photo for the frame or two the bundle takes to decode: a branded wash rather than
      // the card's white, which would read as a flash on every card the carousel builds
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primarySoft, AppColors.surfaceMuted],
        ),
      ),
      child: Image.asset(
        _photos[slotIndex % _photos.length],
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}

/// «VIP» stays latin and untranslated: it is the name of the paid tier, not a word. White on the
/// photo rather than orange - brand orange is for something you can press.
class _VipTag extends StatelessWidget {
  const _VipTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        boxShadow: AppShadows.card,
      ),
      child: const Text(
        'VIP',
        style: TextStyle(
          color: AppColors.textDark,
          fontSize: 11,
          height: 1.1,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The rating, opposite the tag. A white pill because it sits on an image: once a real photo is
/// behind it, the pill is what keeps the number readable over anything.
class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating});

  /// already formatted by the caller
  final String rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
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
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The white block: identity on top, money at the bottom, a hairline between them.
///
/// Only the **top** corners are rounded - the bottom two are the card's own, already cut by its clip,
/// and rounding them twice would pull the sheet away from the card's edge.
class _FactsSheet extends StatelessWidget {
  const _FactsSheet({
    required this.shop,
    required this.isPlaceholder,
    required this.strings,
  });

  final HomeShopPreview? shop;
  final bool isPlaceholder;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final shop = this.shop;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shop?.name ?? strings.slotShopNameLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              // a field name, drawn so «Название магазина» cannot be mistaken for a shop called that
              color: isPlaceholder ? AppColors.textGrey : AppColors.textDark,
              fontSize: 17,
              height: 1.15,
              letterSpacing: -0.3,
              fontWeight: isPlaceholder ? FontWeight.w600 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          _AddressLine(
            text: shop?.address ?? strings.slotAddressLabel,
            color: isPlaceholder ? AppColors.textFaint : AppColors.textGrey,
          ),

          // real gaps rather than `spaceBetween`: distributed slack changed the spacing with the content,
          // so the block read as compressed at the top and stranded at the bottom
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1, color: AppColors.hairline),
          const Spacer(),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // **a card here can legitimately have no price**: ListVipShops left-joins the basket index, so
              // a shop that has not finished pricing shows its name, its address and no comparison. it used
              // to inner-join, which meant somebody paid for a placement and saw nothing.
              Expanded(
                child: Text(
                  switch (shop?.basketPrice) {
                    final basket? => strings.somAmount(basket),
                    // sits where the total does, at the same size and weight - that is the point being made.
                    // the grey is the only difference, so it reads as the name of a figure, not a figure.
                    null => strings.slotBasketLabel,
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: shop?.basketPrice == null ? AppColors.textGrey : AppColors.textDark,
                    fontSize: 19,
                    height: 1.1,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // the comparison already says «рынка» in words - see `priceTierCheaper`. it is the reason the
              // price above it is worth reading, so it shares the line rather than sitting under it.
              if (shop?.priceTier case final tier?)
                PriceTierBadge(
                  tier: tier,
                  differencePercent: shop?.priceDifferencePercent,
                  strings: strings,
                )
              else if (isPlaceholder)
                Flexible(
                  child: Text(
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
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// its own widget so the pin, its gap and the type cannot drift apart from one card to the next
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
