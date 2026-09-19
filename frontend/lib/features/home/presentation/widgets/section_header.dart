import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

// the "Title ........ See all" row above each home section, so the sections line up.
// [actionLabel]/[onAction] are optional and only "Популярные категории" passes them today - do not
// wire one up to an empty `onAction: () {}` just to make the row look complete.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 17,
              letterSpacing: -0.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(width: 12),
          // an InkWell with its own padding rather than a TextButton, whose 64px minimum width and 16px of
          // built-in padding pushed the action past the section's right edge
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: const TextStyle(
                        color: AppColors.primaryOrange,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    // an icon rather than a "→" typed into the copy: the literal depends on the font shipping that
                    // glyph and cannot be sized or spaced with the label
                    const Icon(
                      CupertinoIcons.chevron_forward,
                      color: AppColors.primaryOrange,
                      size: 12,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
