import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// the search bar that floats over the map; shared so the map tab and the shop address picker match.
/// [trailing] is the clear button, a spinner or a submit arrow - whatever the screen needs.
class FloatingSearchField extends StatelessWidget {
  const FloatingSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSubmitted,
    this.focusNode,
    this.onChanged,
    this.trailing,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline),
        // it floats over a busy, coloured map rather than sitting on a page, so it needs the
        // stronger of the two elevations
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.search, color: AppColors.textFaint, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                ),
                // strips the material underline and the default 16px vertical padding, so the text
                // sits centred in our own 50px box instead of fighting it
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          trailing ?? const SizedBox(width: 8),
        ],
      ),
    );
  }
}
