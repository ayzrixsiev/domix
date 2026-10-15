import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

/// The five VIP slots: one card across the page, swiped sideways, with a row of dots under it.
///
/// **Five cards, always, sold or not** - an unsold slot is what tells an owner scrolling past that a
/// place is available, so it is drawn as the real card with its values missing.
///
/// **The loop**: `PageView.builder` is unbounded *forwards* only, so it starts deep inside a virtual
/// range and maps the index back with a modulo (Dart's `%` is Euclidean). It advances on its own, so
/// every placement is seen by somebody who never touches the strip; a finger outranks the clock.
///
/// **The dots are what say there are more cards** - a card this wide has no room for a sliver of its
/// neighbour - and the count in them is the inventory.
class VipShopsCarousel extends StatefulWidget {
  const VipShopsCarousel({super.key, required this.slots, this.onShopTap});

  /// **Mirrors `vipShopsLimit` in the Go handler** - units of a thing that is sold, not a page size.
  /// The app draws whichever is larger, this or what actually arrived, so the two disagreeing can
  /// never hide a placement somebody paid for.
  static const int slotCount = 5;

  /// The ring from [vipSlotRing], arranged centre-outwards. The empty guard at the top of [build] is
  /// real, not defensive padding: `index % 0` below is a division by zero.
  final List<HomeShopPreview?> slots;

  /// The page is the whole width and the card is inset by this. **Deliberately narrower than the
  /// feed's own 10** - this is the one block on the home screen allowed to break that left edge,
  /// and the four it buys go where they are worth the most: the storefront and the comparison
  /// sentence beside it both run out of room before anything else on the card does. Between two
  /// cards mid-swipe it reads as twice this.
  static const double cardGutter = 6;

  /// Fixed, because a `PageView` needs a bounded height. **a `Column` inside a fixed-height card fails
  /// by overflowing, not by scrolling** - silent in release - so adding a line means raising this
  /// number, and the empty card is built to exactly the same height. it is also the one number that
  /// grows the photograph without taking width off the sentence under the address.
  static const double cardHeight = 176;

  /// How long a card holds the screen before the strip moves on by itself. **The section is an
  /// advert and it has five slots, so a strip that only ever shows its first card is four fifths
  /// unsold** - this is what puts the other placements in front of a customer who never swipes.
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
    _controller = PageController(initialPage: _initialPage);
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
      if (!_controller.hasClients || !_controller.position.hasContentDimensions)
        return;
      // forwards forever - the virtual range is unbounded in exactly this direction
      _controller.nextPage(
        duration: _autoAdvanceGlide,
        curve: Curves.easeInOut,
      );
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
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
              // the viewport is exactly [cardHeight] tall, so its default hard edge would cut the shadow off
              // at the card's own bottom edge. Clip.none lets the 30px ambient blur spill into the whitespace
              // above and below the strip, which is where a lift lives.
              clipBehavior: Clip.none,
              itemBuilder: (context, index) {
                // the position in the ring, not the virtual page: the same slot draws the same shop
                // however many times the loop comes back round to it
                final slot = widget.slots[index % widget.slots.length];

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VipShopsCarousel.cardGutter,
                  ),
                  child: PressableScale(
                    // PressableScale rather than an ink ripple: a ripple is a faint wash inside a card that
                    // fills the page and never moves. its onTapCancel matters here - the PageView claims the
                    // gesture the moment a swipe starts, and without it the card would stay shrunk after
                    // every failed tap.
                    onTap: _tapHandlerFor(slot),
                    child: _SlotCard(shop: slot, strings: strings),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        // rebuilt on every scroll tick, so the dot grows as the page settles rather than snapping
        // once the gesture is over
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _SlotDots(
            count: widget.slots.length,
            // `%` is Euclidean in Dart, and the virtual page is always positive anyway
            active: _currentPage.round() % widget.slots.length,
          ),
        ),
      ],
    );
  }
}

/// Which of the five slots is on screen. **The count is the inventory, not a page count** - five
/// dots over one card is the section saying there are four more placements, sold or not.
///
/// The active dot is brand orange *and* wider: at 7px a hue change alone is a detail somebody has
/// to look for, and the row is read at a glance or not at all.
class _SlotDots extends StatelessWidget {
  const _SlotDots({required this.count, required this.active});

  final int count;
  final int active;

  static const double _size = 6;
  static const double _activeSize = 9;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppMotion.base,
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3.5),
            width: i == active ? _activeSize : _size,
            height: i == active ? _activeSize : _size,
            decoration: BoxDecoration(
              color: i == active
                  ? AppColors.primaryOrange
                  : AppColors.trackGrey,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

// ── the card: **a sold slot and an unsold one are one widget**, and only their text and its colour
// differ. the unsold one was drawn recessed for a while and rejected on sight - four faded frames
// around one real card made the strip look broken rather than available. ──

/// One VIP slot: the storefront, then who and where, how the basket compares, and two figures.
///
/// **The photograph is uploaded from the admin panel, never generated** - an unphotographed placement
/// draws an empty frame with its category glyph, because an invented shop front over a real shop's
/// name is the one thing the section that is *sold* cannot show.
///
/// **«Рейтинг» has no source in this build** (no reviews table), so a real shop draws a dash and only
/// an empty slot shows a number, which is part of what is being sold.
class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.shop, required this.strings});

  /// **Null is an unsold placement**, not missing data: the card is drawn in full with the names of
  /// its fields where the values go. Nothing here may become a plausible value - the one section of
  /// the app that is sold is the last place an invented shop belongs.
  final HomeShopPreview? shop;

  final AppLocalizations strings;

  /// What the photograph takes of the card's width.
  ///
  /// **a floor set by the other column, not a taste**: the comparison pill needs ~160dp, which is what
  /// is left beside the frame on a 360dp screen. any wider and the one sentence a customer reads this
  /// card for starts ellipsising.
  static const int _photoFlex = 46;
  static const int _factsFlex = 54;

  @override
  Widget build(BuildContext context) {
    final shop = this.shop;
    final isPlaceholder = shop == null;

    return Container(
      decoration: _cardSurface,
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: _photoFlex,
            child: _Storefront(
              url: shop?.imageThumbUrl,
              category: shop?.shop.category,
              strings: strings,
            ),
          ),
          Expanded(
            flex: _factsFlex,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 4, 4, 4),
              // **spread, not stacked with a single Spacer.** The column is three blocks - who and
              // where, the comparison, the figures - and on a card this tall all the slack used to
              // pile up under the address as one hole. spaceBetween splits it into two equal joints.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              shop?.name ?? strings.slotShopNameLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                // a field name, drawn so «Название магазина» cannot be mistaken for a shop called that
                                color: isPlaceholder
                                    ? AppColors.textGrey
                                    : AppColors.textDark,
                                fontSize: 17,
                                height: 1.15,
                                letterSpacing: -0.3,
                                fontWeight: isPlaceholder
                                    ? FontWeight.w600
                                    : FontWeight.w700,
                              ),
                            ),
                          ),
                          // the chevron says the whole card opens something. on an unsold slot there is
                          // nothing to open, so it is not drawn rather than drawn dead.
                          if (!isPlaceholder) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              LucideIcons.chevron_right,
                              size: 17,
                              color: AppColors.textFaint,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      _AddressLine(
                        text: shop?.address ?? strings.slotAddressLabel,
                        color: isPlaceholder
                            ? AppColors.textFaint
                            : AppColors.textGrey,
                      ),
                    ],
                  ),

                  // the comparison already says «рынка» in words - see `priceTierCheaper`. it is the one
                  // reason a customer reads this card rather than scrolling past it.
                  if (shop?.priceTier case final tier?)
                    PriceTierBadge(
                      tier: tier,
                      differencePercent: shop?.priceDifferencePercent,
                      strings: strings,
                    )
                  else
                    Text(
                      // **a sold card can legitimately have no comparison**: ListVipShops left-joins the
                      // basket index, so a shop that has not finished pricing shows its name and no badge.
                      // it used to inner-join, which meant somebody paid for a placement and saw nothing.
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

                  _SlotFigures(shop: shop, strings: strings),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two figures along the bottom of a card, each a number over the name of what it counts.
///
/// **There is no third one.** «От вас» was a distance, and this app never asks for a location it
/// does not need for the map.
class _SlotFigures extends StatelessWidget {
  const _SlotFigures({required this.shop, required this.strings});

  final HomeShopPreview? shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final shop = this.shop;

    // Flexible, not two fixed cells: «Товаров» and «Reyting» are the longest words on the card and
    // the column they share is two thirds of a 320dp phone. A caption that ellipsises is a worse
    // card than a tight one; a RenderFlex overflow is a yellow stripe across it.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: _Figure(
            // **only the empty slot shows a rating.** there is no reviews table, so a real shop has
            // nothing to show - on the slot it is part of what a placement is being sold as.
            value: shop == null ? kSlotRating : strings.noFigure,
            caption: strings.cardRatingCaption,
            leading: const Icon(
              CupertinoIcons.star_fill,
              color: AppColors.starYellow,
              size: 12,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: _Figure(
            // 0 is "this read did not count them", and the carousel's read always does - so a shop
            // whose catalogue is genuinely empty is the only card that draws a dash here
            value: (shop?.productCount ?? 0) > 0
                ? '${shop!.productCount}'
                : strings.noFigure,
            caption: strings.cardProductsCaption,
          ),
        ),
      ],
    );
  }
}

/// one figure: the number, and under it the name of what was counted
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.caption, this.leading});

  final String value;
  final String caption;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 15,
                  height: 1.1,
                  letterSpacing: -0.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (leading case final glyph?) ...[const SizedBox(width: 3), glyph],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 10.5,
            height: 1.15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// The photograph, and the «VIP магазин» tag riding on it.
///
/// `cover`, unlike a product tile's `contain`: this is a building, and bands of panel colour either
/// side would read as a broken image.
///
/// **An empty frame is a real state, not a loading one** - only an admin can put a photo here, so the
/// frame carries the category glyph instead of inventing what the shop looks like.
class _Storefront extends StatelessWidget {
  const _Storefront({
    required this.url,
    required this.category,
    required this.strings,
  });

  final String? url;
  final ShopCategory? category;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final url = this.url;

    return DecoratedBox(
      // **a panel inside the card, not a hole in it**: `photoPanel` sits within a hair of the page's
      // colour, so a frame running into the card's edge in it reads as a bite taken out of the card.
      decoration: BoxDecoration(
        color: AppColors.cardGrey,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              // `store` for an unsold slot: there is no shop behind it to have a category
              child: Icon(
                category?.icon ?? LucideIcons.store,
                size: 26,
                color: AppColors.textFaint,
              ),
            ),
            if (url != null)
              Image.network(
                url,
                fit: BoxFit.cover,
                // without it a 1000px jpeg costs 4 MB of raw bitmap however small it is drawn, and
                // five of these live in the loop at once
                cacheWidth: 400,
                // an unreachable server leaves the frame showing rather than flutter's broken-image glyph
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                // fades in once decoded instead of popping; the frame underneath is the loading state
                frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: AppMotion.base,
                    curve: Curves.easeOut,
                    child: child,
                  );
                },
              ),
            Positioned(left: 7, top: 7, child: _VipTag(strings: strings)),
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

/// «VIP» stays latin and untranslated: it is the name of the paid tier, not a word.
///
/// **A white pill, because it rides on a photograph again** - it was dark while the card was all
/// white, where a white chip would have been a shadow with a word in it. The shadow is what keeps it
/// readable over a pale sky in the top-left of a storefront.
class _VipTag extends StatelessWidget {
  const _VipTag({required this.strings});

  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        boxShadow: AppShadows.card,
      ),
      // **it has to fit inside the frame, which is a third of a 320dp phone**: the frame clips, so a
      // longer label would be cut off rather than wrap. 10px leaves «VIP магазин» ~15dp of room.
      child: Text(
        strings.vipShopTag,
        maxLines: 1,
        style: const TextStyle(
          color: AppColors.textDark,
          fontSize: 10,
          height: 1.1,
          letterSpacing: -0.1,
          fontWeight: FontWeight.w700,
        ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // nudged onto the first line's baseline: a pin centred against two lines of address floats
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            CupertinoIcons.location_solid,
            color: AppColors.textFaint,
            size: 11,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            // two lines: a Tashkent address is a street, a number and a district, and one line of
            // it ellipsises before the district - which is the half a customer navigates by
            maxLines: 2,
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
