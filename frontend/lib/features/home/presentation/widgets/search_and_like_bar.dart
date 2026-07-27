import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';

class SearchAndLikeBar extends StatelessWidget {
  const SearchAndLikeBar({super.key});

  static const double _height = 48;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: _surface,
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.textFaint, size: 19),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.searchHint,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // both halves now share one decoration. previously only the filter button carried a shadow,
        // so the two sat at visibly different depths despite being one control strip.
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () {},
            child: Container(
              height: _height,
              width: _height,
              alignment: Alignment.center,
              decoration: _surface,
              child: const Icon(Icons.tune_rounded, color: AppColors.primaryOrange, size: 19),
            ),
          ),
        ),
      ],
    );
  }

  static final BoxDecoration _surface = BoxDecoration(
    color: AppColors.surfaceWhite,
    borderRadius: BorderRadius.circular(AppRadius.sm),
    border: Border.all(color: AppColors.hairline),
    boxShadow: AppShadows.card,
  );
}
