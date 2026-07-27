import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

// the "Title ........ See all" row above each home section. it was copy-pasted into three widgets
// with slightly different type sizes and a bare TextButton whose default material padding pushed
// the action out of alignment with the title. one widget means the sections actually line up.
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
          // an InkWell with its own padding rather than a TextButton: TextButton carries a 64px
          // minimum width and 16px of built-in horizontal padding, which is what was pushing the
          // action past the section's right edge and out of line with the cards below it.
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
                    // an icon rather than a "→" typed into the copy: the literal character depended
                    // on the font shipping that glyph, and it could not be sized or spaced with the
                    // label the way a real icon can
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
