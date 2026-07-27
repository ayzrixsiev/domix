import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_placeholder_content.dart';
import 'section_header.dart';

// the visual identity of one category tile. paired with HomeCategory by the switch below, so adding
// a category to the enum is a compile error here until its icon and tint are filled in - which is
// exactly the safety the old `Map<String, dynamic>` version threw away.
class _CategoryStyle {
  const _CategoryStyle(this.icon, this.tint, this.iconColor);

  final IconData icon;
  final Color tint;
  final Color iconColor;
}

class PopularCategoriesGrid extends StatelessWidget {
  const PopularCategoriesGrid({super.key});

  // dart 3 switch *expressions* over an enum are exhaustive: leave a case out and the analyzer
  // rejects the file rather than throwing at runtime the first time that tile is scrolled into view.
  static _CategoryStyle _styleOf(HomeCategory category) => switch (category) {
    HomeCategory.concrete =>
      const _CategoryStyle(LucideIcons.layers, Color(0xFFEEF4FF), Color(0xFF3B72E8)),
    HomeCategory.cement =>
      const _CategoryStyle(LucideIcons.package, Color(0xFFF6EFFA), Color(0xFF8E4FB0)),
    HomeCategory.brick =>
      const _CategoryStyle(LucideIcons.layout_grid, Color(0xFFFDEEEF), Color(0xFFD4574F)),
    HomeCategory.rebar =>
      const _CategoryStyle(LucideIcons.braces, Color(0xFFE9F5F3), Color(0xFF16897C)),
    HomeCategory.foamBlock =>
      const _CategoryStyle(LucideIcons.square, Color(0xFFFDF3E3), Color(0xFFCF8A17)),
    HomeCategory.roofing =>
      const _CategoryStyle(Icons.roofing_rounded, Color(0xFFEDEFFA), Color(0xFF4A56B5)),
    HomeCategory.paint =>
      const _CategoryStyle(LucideIcons.palette, Color(0xFFEAF6EC), Color(0xFF3E9350)),
    HomeCategory.insulation =>
      const _CategoryStyle(LucideIcons.shield, Color(0xFFFCEDE9), Color(0xFFC15436)),
  };

  static String _labelOf(HomeCategory category, AppLocalizations strings) => switch (category) {
    HomeCategory.concrete => strings.categoryConcrete,
    HomeCategory.cement => strings.categoryCement,
    HomeCategory.brick => strings.categoryBrick,
    HomeCategory.rebar => strings.categoryRebar,
    HomeCategory.foamBlock => strings.categoryFoamBlock,
    HomeCategory.roofing => strings.categoryRoofing,
    HomeCategory.paint => strings.categoryPaint,
    HomeCategory.insulation => strings.categoryInsulation,
  };

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: strings.popularProducts,
          actionLabel: strings.seeAll,
          onAction: () {},
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.84,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: HomeCategory.values.length,
          itemBuilder: (context, index) {
            final category = HomeCategory.values[index];
            return _CategoryTile(
              style: _styleOf(category),
              label: _labelOf(category, strings),
            );
          },
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.style, required this.label});

  final _CategoryStyle style;
  final String label;

  @override
  Widget build(BuildContext context) {
    // no drop shadow here on purpose: eight small tiles each casting their own shadow reads as
    // texture rather than depth. a hairline outline separates them from the page just as well.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: style.tint,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(style.icon, color: style.iconColor, size: 21),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
