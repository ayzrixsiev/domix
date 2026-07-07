import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class ShopsNearbyGrid extends StatelessWidget {
  const ShopsNearbyGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final nearbyShops = [
      {
        'name': 'СантехОпт',
        'address': '0.5 км • ул. Мукими',
        'rating': '4.7',
        'paycheck': '~500 000 сум',
      },
      {
        'name': 'ЭлектроМир',
        'address': '1.2 км • ул. Катартал',
        'rating': '4.9',
        'paycheck': '~1 200 000 сум',
      },
      {
        'name': 'Кровля Плюс',
        'address': '1.8 км • Чиланзар-2',
        'rating': '4.6',
        'paycheck': '~4 500 000 сум',
      },
      {
        'name': 'ЦементЦентр',
        'address': '2.1 км • ул. Чапаната',
        'rating': '4.8',
        'paycheck': '~900 000 сум',
      },
      {
        'name': 'Прораб Маркет',
        'address': '2.4 км • Актепа',
        'rating': '5.0',
        'paycheck': '~2 100 000 сум',
      },
      {
        'name': 'Инструменты24',
        'address': '3.0 км • проспект Bunyodkor',
        'rating': '4.5',
        'paycheck': '~650 000 сум',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Магазины рядом с вами',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: nearbyShops.length,
          itemBuilder: (context, index) {
            final shop = nearbyShops[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.02),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          shop['name']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.star,
                            color: AppColors.starYellow,
                            size: 14,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            shop['rating']!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.navigation,
                        color: AppColors.accentBlue,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          shop['address']!,
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardGrey,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      shop['paycheck']!,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
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
