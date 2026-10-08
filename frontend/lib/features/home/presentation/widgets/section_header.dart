import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';

// the title row above each home section, so the sections line up
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textDark,
        fontSize: 17,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
