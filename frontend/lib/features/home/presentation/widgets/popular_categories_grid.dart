import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class PopularCategoriesGrid extends StatelessWidget {
  const PopularCategoriesGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = [
      {
        'name': 'Бетон',
        'icon': LucideIcons.layers,
        'color': const Color(0xFFE3F2FD),
        'iconColor': const Color(0xFF1E88E5),
      },
      {
        'name': 'Цемент',
        'icon': LucideIcons.package,
        'color': const Color(0xFFF3E5F5),
        'iconColor': const Color(0xFF8E24AA),
      },
      {
        'name': 'Кирпич',
        'icon': LucideIcons.layout_grid,
        'color': const Color(0xFFFFEBEE),
        'iconColor': const Color(0xFFE53935),
      },
      {
        'name': 'Арматура',
        'icon': LucideIcons.braces,
        'color': const Color(0xFFE0F2F1),
        'iconColor': const Color(0xFF00897B),
      },
      {
        'name': 'Пеноблок',
        'icon': LucideIcons.square,
        'color': const Color(0xFFFFF8E1),
        'iconColor': const Color(0xFFFFA000),
      },
      {
        'name': 'Кровля',
        'icon': Icons.roofing_rounded,
        'color': const Color(0xFFE8EAF6),
        'iconColor': const Color(0xFF3949AB),
      },
      {
        'name': 'Краска',
        'icon': LucideIcons.palette,
        'color': const Color(0xFFE8F5E9),
        'iconColor': const Color(0xFF43A047),
      },
      {
        'name': 'Изоляция',
        'icon': LucideIcons.shield,
        'color': const Color(0xFFFBE9E7),
        'iconColor': const Color(0xFFD84315),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Популярные товары',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Text(
                'Все →',
                style: TextStyle(
                  color: AppColors.primaryOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.83,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceWhite,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromRGBO(0, 0, 0, 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: cat['color'] as Color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      cat['icon'] as IconData,
                      color: cat['iconColor'] as Color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cat['name'] as String,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
