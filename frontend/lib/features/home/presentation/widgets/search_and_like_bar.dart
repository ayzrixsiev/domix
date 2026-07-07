import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';

class SearchAndLikeBar extends StatelessWidget {
  const SearchAndLikeBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.search, color: AppColors.textGrey, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Поиск...',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          height: 50,
          width: 50,
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: const Color.fromRGBO(0, 0, 0, 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppColors.primaryOrange),
            onPressed: () {},
          ),
        ),
      ],
    );
  }
}