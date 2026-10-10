import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/features/stores/data/price_tier.dart';

/// An enum rather than the `compact` bool it replaced: there are three sizes, and two bools would
/// allow a fourth combination with no meaning.
enum PriceTierBadgeSize {
  /// the sentence on its own tinted pill - VIP cards, where nothing else separates it from white
  pill,

  /// pill dropped and the type shrunk, where a container is already doing the separating
  compact,

  /// the shop card's price block: no pill, since the card separates its sections with rules
  headline,
}

/// How a shop's basket compares to its market: three bars and a sentence. The index itself
/// (96, 104) is never shown - the backend picks both the bucket and the percentage.
///
/// **The bars climb with the shop's standing, not with its prices.** The glyph is read before the
/// sentence is, so a chart falling next to «дешевле» would say the opposite of the words beside it.
/// Colour is never the only channel either: the sentence says "дешевле"/"дороже" out loud.
class PriceTierBadge extends StatelessWidget {
  const PriceTierBadge({
    super.key,
    required this.tier,
    required this.differencePercent,
    required this.strings,
    this.size = PriceTierBadgeSize.pill,
  });

  final PriceTier tier;

  /// Unsigned - the direction is [tier]'s job. Null renders as 0 rather than asserting: a malformed
  /// response should cost a badge, not a screen.
  final int? differencePercent;

  final AppLocalizations strings;

  final PriceTierBadgeSize size;

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

    final chart = switch (tier) {
      PriceTier.cheaper => LucideIcons.chart_no_axes_column_increasing,
      PriceTier.average => LucideIcons.chart_no_axes_column,
      PriceTier.dearer => LucideIcons.chart_no_axes_column_decreasing,
    };

    // the glyph runs a step larger than the dot it replaced at every size: lucide is a stroke font,
    // so it covers far less area than a filled circle of the same nominal width
    final (double glyph, double gap, double fontSize, FontWeight weight) = switch (size) {
      PriceTierBadgeSize.pill => (12, 5, 11.5, FontWeight.w600),
      PriceTierBadgeSize.compact => (11, 5, 11, FontWeight.w600),
      PriceTierBadgeSize.headline => (17, 7, 15.5, FontWeight.w700),
    };

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(chart, size: glyph, color: colour),
        SizedBox(width: gap),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colour,
              fontSize: fontSize,
              height: 1.2,
              fontWeight: weight,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );

    if (size != PriceTierBadgeSize.pill) return content;

    return Container(
      // 7, not 8: the pill's one caller is the VIP card, where «Средняя цена по рынку» has about two
      // pixels to spare before it ellipsises - see `_SlotCard._factsFlex`
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: content,
    );
  }
}

/// The same comparison compressed above a map pin: a dot and a signed percentage, since a pin has
/// room for about four characters. The dot is what makes forty pins scannable at a glance.
///
/// The average tier shows no number, just the dot and `≈`: its band is 98-102, and an unsigned "1%"
/// invites the very question the tier exists to answer.
class PriceTierPinLabel extends StatelessWidget {
  const PriceTierPinLabel({super.key, required this.tier, required this.differencePercent});

  final PriceTier tier;
  final int? differencePercent;

  /// larger than the badge's 7px: it has to survive being one of forty marks over busy map tiles
  static const double dotSize = 8;

  @override
  Widget build(BuildContext context) {
    final colour = switch (tier) {
      PriceTier.cheaper => AppColors.success,
      PriceTier.average => AppColors.warning,
      PriceTier.dearer => AppColors.danger,
    };

    final percent = differencePercent ?? 0;
    // U+2212, not a hyphen: a hyphen at this weight reads as a dash between two things
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
