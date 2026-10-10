import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// The shop's mark: its category's glyph in white on a brand-orange disc, in a white collar.
///
/// It sits on the seam between the cover and the white details surface, which is what the collar is
/// for - the disc has to read as one object while half of it lies on a coloured picture and half on
/// white.
///
/// **The glyph is [ShopCategory.icon], the same one the map pin carries.** A shop is usually reached
/// by tapping its pin, and a different mark on the card it opens would read as a different shop.
/// The disc stays brand orange on all four categories: the cover is what says which kind of shop
/// this is, and the mark is what says whose app it is.
class ShopCategoryAvatar extends StatelessWidget {
  const ShopCategoryAvatar({
    super.key,
    required this.category,
    this.size = defaultSize,
  });

  final ShopCategory category;

  /// The card's layout is built around this - see `_ShopHeader` - so a caller changing it has to
  /// hand the same number to the header.
  static const double defaultSize = 84;

  final double size;

  /// White, and thick enough to survive the disc sitting on a saturated cover.
  static const double _collar = 4.5;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surfaceWhite, width: _collar),
        // top-left to bottom-right, so the disc catches light the same way AppShadows drops it
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A2B), AppColors.primaryDeep],
        ),
        boxShadow: AppShadows.raised,
      ),
      child: Center(
        child: Icon(
          category.icon,
          color: AppColors.textLight,
          size: size * 0.42,
        ),
      ),
    );
  }
}
