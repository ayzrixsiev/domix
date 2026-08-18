import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/features/stores/data/price_tier.dart';

/// How a shop's basket compares to its market, as a coloured dot and a sentence:
/// **🟢 на 4% дешевле рынка**.
///
/// **The number behind it is never shown.** The Basket Price Index (96, 104) is a comparison the
/// reader has to be taught to perform, against a baseline nobody explained, and a shop card is not
/// where anyone reads instructions. The backend decides the bucket and the percentage; this widget
/// only picks a colour and a string. See `backend/internal/pricing`.
///
/// Rendered as a filled circle rather than the 🟢/🟡/🔴 emoji the spec was written with: emoji are
/// drawn by whichever font the device happens to ship, so their size, alignment and exact hue vary
/// per platform, and they would be the only non-Lucide glyphs in the app. A `Container` with a
/// token colour is the same signal, drawn the same way everywhere.
///
/// Colour is never the only channel - the sentence next to the dot says "дешевле" or "дороже" in
/// words, so the badge still reads for someone who cannot distinguish the two.
class PriceTierBadge extends StatelessWidget {
  const PriceTierBadge({
    super.key,
    required this.tier,
    required this.differencePercent,
    required this.strings,
    this.compact = false,
  });

  final PriceTier tier;

  /// Unsigned - the direction is [tier]'s job. Null is tolerated (rendered as 0) rather than
  /// asserted on, since a malformed response should cost a badge, not a screen.
  final int? differencePercent;

  final AppLocalizations strings;

  /// Drops the surrounding pill and shrinks the type, for rows where the badge sits inside another
  /// container that is already separating it from the background.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (Color colour, Color background) = switch (tier) {
      PriceTier.cheaper => (AppColors.success, AppColors.successSoft),
      PriceTier.average => (AppColors.warning, AppColors.warningSoft),
      PriceTier.dearer => (AppColors.danger, AppColors.dangerSoft),
    };

    final percent = differencePercent ?? 0;
    final label = switch (tier) {
      PriceTier.cheaper => strings.priceTierCheaper(percent),
      PriceTier.average => strings.priceTierAverage,
      PriceTier.dearer => strings.priceTierDearer(percent),
    };

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 6 : 7,
          height: compact ? 6 : 7,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        SizedBox(width: compact ? 5 : 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colour,
              fontSize: compact ? 11 : 12,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );

    if (compact) return content;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: content,
    );
  }
}

/// The same comparison compressed to fit above a map pin: a coloured dot and a signed percentage.
///
/// A pin has room for about four characters, so the sentence is out - but "−4%" is still not the raw
/// index, and it is the one form that stays scannable when forty of them are on screen at once,
/// which is exactly what a map is for. The sign replaces the words, so the direction survives.
///
/// **The dot is the point of this widget on a map.** Reading forty labels means reading forty
/// numbers; picking out the green ones is a glance. It is the same dot [PriceTierBadge] draws, at
/// the same three token colours, so a pin and the sheet it opens agree without either knowing about
/// the other.
///
/// The colour is never alone: the number is tinted to match, and the sign spells out the direction
/// for anyone the red/green distinction fails.
///
/// **The average tier shows no number at all, just the dot and `≈`.** Its band is 98-102, so the
/// difference can be 1 or 2 - and an unsigned "1%" next to a yellow dot invites exactly the question
/// the tier exists to answer ("cheaper or dearer by 1%?"). The tier's claim is that the difference
/// is not worth stating, so it doesn't state one.
class PriceTierPinLabel extends StatelessWidget {
  const PriceTierPinLabel({super.key, required this.tier, required this.differencePercent});

  final PriceTier tier;
  final int? differencePercent;

  /// Slightly larger than the badge's 7px. There is no dense text beside it here, and it has to
  /// survive being one of forty small objects over busy map tiles.
  static const double dotSize = 8;

  @override
  Widget build(BuildContext context) {
    final colour = switch (tier) {
      PriceTier.cheaper => AppColors.success,
      PriceTier.average => AppColors.warning,
      PriceTier.dearer => AppColors.danger,
    };

    final percent = differencePercent ?? 0;
    // the minus is U+2212, not a hyphen: a hyphen at this weight reads as a dash between two things
    // rather than as a sign on one
    final label = switch (tier) {
      PriceTier.cheaper => '−$percent%',
      PriceTier.dearer => '+$percent%',
      PriceTier.average => '≈',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: colour,
            fontSize: 11,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}
