import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class InfiniteShopCarousel extends StatelessWidget {
  const InfiniteShopCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    final shops = [
      {
        'name': 'СтройМастер',
        'address': 'Юнусабадский р-н, ул. Амира Темура, 45',
        'rating': '4.9',
        'paycheck': 'Средний чек: 1 500 000 сум',
      },
      {
        'name': 'МегаСтрой',
        'address': 'Мирзо-Улугбекский р-н, ул. Буюк Ипак Йули',
        'rating': '4.8',
        'paycheck': 'Средний чек: 850 000 сум',
      },
      {
        'name': 'ДомСтрой',
        'address': 'Алмазарский р-н, пр. Бунёдкор, 12',
        'rating': '4.7',
        'paycheck': 'Средний чек: 720 000 сум',
      },
      {
        'name': 'РемонтПлюс',
        'address': 'Чиланзар, ул. Шахрисабз, 7',
        'rating': '4.6',
        'paycheck': 'Средний чек: 950 000 сум',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Популярные магазины',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('Смотреть все →', style: TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 156,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: shops.length * 2,
            controller: PageController(viewportFraction: 0.88),
            itemBuilder: (context, index) {
              final shop = shops[index % shops.length];
              return Container(
                width: 300,
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1E2C), Color(0xFF2D2D44)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color.fromRGBO(0, 0, 0, 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
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
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 255, 255, 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.star, color: AppColors.starYellow, size: 14),
                              const SizedBox(width: 4),
                              Text(shop['rating']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(LucideIcons.map_pin, color: AppColors.textGrey, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(shop['address']!, style: const TextStyle(color: AppColors.textGrey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryOrange.withAlpha(51),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primaryOrange.withAlpha(128)),
                      ),
                      child: Text(shop['paycheck']!, style: const TextStyle(color: Color(0xFFFF9E58), fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}