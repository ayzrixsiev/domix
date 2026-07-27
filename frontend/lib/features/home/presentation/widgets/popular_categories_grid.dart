import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_placeholder_content.dart';

// Every glyph here is a Lucide icon - one family, one stroke weight, monochrome.
//
// The previous version mixed Hugeicons in, which renders each icon by assembling an SVG string at
// runtime and handing it to flutter_svg. That is strictly worse than a glyph font for this job: it
// dragged in three extra packages, cost a parse per icon, and hinted less crisply at small sizes.
// Lucide ships a real icon font, so the glyphs are vector-hinted, cost nothing to draw, and the
// package was already a dependency. Hugeicons has been removed from pubspec entirely.
class PopularCategoriesGrid extends StatelessWidget {
  const PopularCategoriesGrid({super.key});

  // dart 3 switch *expressions* over an enum are exhaustive: leave a case out and the analyzer
  // rejects the file rather than throwing at runtime the first time that tile is scrolled into view.
  static IconData _iconOf(HomeCategory category) => switch (category) {
    HomeCategory.mixes => LucideIcons.container,
    HomeCategory.blocks => LucideIcons.brick_wall,
    HomeCategory.fasteners => LucideIcons.bolt,
    HomeCategory.roofing => LucideIcons.house,
    HomeCategory.electrical => LucideIcons.zap,
    HomeCategory.plumbing => LucideIcons.droplets,
    HomeCategory.paints => LucideIcons.paint_roller,
    HomeCategory.tools => LucideIcons.wrench,
  };

  static String _labelOf(HomeCategory category, AppLocalizations strings) => switch (category) {
    HomeCategory.mixes => strings.categoryMixes,
    HomeCategory.blocks => strings.categoryBlocks,
    HomeCategory.fasteners => strings.categoryFasteners,
    HomeCategory.roofing => strings.categoryRoofing,
    HomeCategory.electrical => strings.categoryElectrical,
    HomeCategory.plumbing => strings.categoryPlumbing,
    HomeCategory.paints => strings.categoryPaints,
    HomeCategory.tools => strings.categoryTools,
  };

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        // a fixed row height rather than childAspectRatio, which was the previous approach.
        // aspect ratio derives height from *width*, so the cell got taller on a wide phone and
        // shorter on a narrow one - and once the section moved inside a padded panel the cells
        // narrowed enough that the computed height no longer fit a two-line label. this is the
        // content's actual height (64 box + 7 gap + two 13.2px lines) plus a little slack, and it
        // holds on every screen width. it also fixes the old complaint about tall empty cells,
        // since the slack is now a constant instead of whatever the width happened to imply.
        mainAxisExtent: 100,
        crossAxisSpacing: 10,
        mainAxisSpacing: 6,
      ),
      itemCount: HomeCategory.values.length,
      itemBuilder: (context, index) {
        final category = HomeCategory.values[index];
        return _CategoryTile(
          icon: _iconOf(category),
          label: _labelOf(category, strings),
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // the box stays - it is what separates one category from the next - but it is neutral now.
          // eight different pastel fills with eight matching icon colours was the loudest thing on
          // the screen and read as a children's app; a monochrome glyph on an off-white tile reads
          // as a catalogue. cardGrey (not surfaceMuted) on purpose here: surfaceMuted is tuned to sit
          // almost flush with the page background, which is what made the tile read as barely-there.
          Container(
            height: 64,
            width: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.cardGrey,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Icon(icon, color: AppColors.textDark, size: 28),
          ),
          const SizedBox(height: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
