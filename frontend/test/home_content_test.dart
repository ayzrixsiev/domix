// Does the Flutter side decode what the Go side actually sends?
//
// `test/fixtures/api_home_response.json` is not hand-written: it is the literal body captured from
// `GET /api/home` on a running server with four seeded shops - three Универсальный and one Обои, so
// the fixture covers both a multi-tab strip and a category with a single shop in it.
//
// Captured rather than typed, because a fixture someone typed out is a test of what they believed
// the backend sends, and the belief is the thing most likely to be wrong. The Go side has its own
// tests for the shape (`internal/endpoints/home_test.go`); this one checks that the two sides
// agree, which is the seam neither can test alone.
//
// Re-capture it with:
//   curl -s localhost:8080/api/home > test/fixtures/api_home_response.json

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_showcase_content.dart';
import 'package:frontend/features/products/data/product_category.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

void main() {
  group('HomeContent.fromJson against a real backend response', () {
    late HomeContent content;

    setUpAll(() {
      final raw = File('test/fixtures/api_home_response.json').readAsStringSync();
      content = HomeContent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    });

    test('decodes the VIP carousel', () {
      expect(content.vipShops, hasLength(1));
      expect(content.vipShops.single.name, 'ТЕСТ Середина');
      expect(content.vipShops.single.isVip, isTrue);
      expect(content.vipShops.single.basketPrice, 5000000);
      expect(content.vipShops.single.priceTier, PriceTier.average);
    });

    test('best offers arrive grouped into one tab per shop category', () {
      expect(
        content.bestOffers.map((g) => g.category).toList(),
        [ShopCategory.universal, ShopCategory.wallpaper],
      );
      // сантехника and дерево have no shops, so the backend sends no group and the app draws no tab
      expect(
        content.bestOffers.map((g) => g.category),
        isNot(contains(ShopCategory.plumbing)),
      );
    });

    test('keeps the server ordering inside a tab', () {
      // the ranking is the section's entire meaning, and it belongs to the SQL - a client that
      // re-sorted would be a second opinion about which shop is cheapest
      final universal = content.bestOffers.first.shops;
      expect(universal.map((s) => s.basketPrice).toList(), [4000000, 5000000, 6000000]);
      expect(
        universal.map((s) => s.priceTier).toList(),
        [PriceTier.cheaper, PriceTier.average, PriceTier.dearer],
      );
      expect(universal.first.priceDifferencePercent, 20);
    });

    test('the only shop in a category is exactly the market average', () {
      // correct rather than a degenerate case: with nobody to compare against, "average" is the
      // only honest answer. worth pinning because it reads as a bug the first time it is seen.
      final wallpaper = content.bestOffers.last.shops;
      expect(wallpaper, hasLength(1));
      expect(wallpaper.single.priceTier, PriceTier.average);
      expect(wallpaper.single.priceDifferencePercent, 0);
      expect(wallpaper.single.basketPrice, 2500000);
    });

    test('a VIP shop can also be a best offer', () {
      // VIP is a placement tier, not a separate catalogue, so it must not exclude a shop from the
      // price ranking
      expect(
        content.bestOffers.expand((g) => g.shops).any((s) => s.isVip),
        isTrue,
      );
    });

    test('the payload carries no category list', () {
      // the twelve tiles are a fixed list the app already holds, so there is nothing to decode -
      // and the shop counts that used to ride along here went with the badges that displayed them
      final raw = jsonDecode(
        File('test/fixtures/api_home_response.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(raw.containsKey('categories'), isFalse);
    });

    test('hasNoShops is false when the backend returned shops', () {
      expect(content.hasNoShops, isFalse);
    });
  });

  group('HomeContent.fromJson edge cases', () {
    test('an empty database decodes to empty lists, not a crash', () {
      // the literal body the server returns today, with no shops in it
      const empty = '{"vip_shops":[],"best_offers":[]}';
      final content = HomeContent.fromJson(jsonDecode(empty) as Map<String, dynamic>);

      expect(content.vipShops, isEmpty);
      expect(content.bestOffers, isEmpty);
      expect(content.hasNoShops, isTrue);
    });

    test('a null list is survived rather than thrown on', () {
      // the backend uses make(...) everywhere specifically so this cannot happen, but a decoder
      // that dies on it would turn one backend regression into a white screen
      const nulls = '{"vip_shops":null,"best_offers":null}';
      final content = HomeContent.fromJson(jsonDecode(nulls) as Map<String, dynamic>);

      expect(content.vipShops, isEmpty);
      expect(content.hasNoShops, isTrue);
    });

    test('a shop with no published price decodes as null, never as zero', () {
      // the distinction the whole nullable column exists for: "not priced yet" is not "free"
      const unpriced = '''
      {"vip_shops":[],
       "best_offers":[{"category":"universal","shops":[
         {"id":1,"name":"Х","contact_phone":"+998","address":"А","category":"universal",
          "rating":0,"is_vip":false,"price_tier":null,"price_difference_percent":null,
          "basket_price":null,"latitude":41.3,"longitude":69.2}]}]}
      ''';
      final content = HomeContent.fromJson(jsonDecode(unpriced) as Map<String, dynamic>);

      final shop = content.bestOffers.single.shops.single;
      expect(shop.priceTier, isNull);
      expect(shop.priceDifferencePercent, isNull);
      expect(shop.basketPrice, isNull);
    });

    test('an unknown shop category is skipped rather than misfiled', () {
      // ShopCategory.fromCode defaults to universal, which is right for a single shop row and very
      // wrong for a whole tab - it would merge a fifth category's shops into Универсальный and rank
      // them against a basket they were never priced against
      const extra = '''
      {"vip_shops":[],
       "best_offers":[{"category":"universal","shops":[]},{"category":"spaceships","shops":[]}]}
      ''';
      final content = HomeContent.fromJson(jsonDecode(extra) as Map<String, dynamic>);

      expect(content.bestOffers, hasLength(1));
      expect(content.bestOffers.single.category, ShopCategory.universal);
    });
  });

  group('showcase content', () {
    test('every category opens onto products, from the shops that stock it', () {
      // the drill-down list is derived from the same map the home sections are, so a shop that is
      // cheap on the home screen is cheap here too - the relationship the real data has
      for (final category in ProductCategory.values) {
        final products = showcaseProductsForCategory(category);
        expect(products, isNotEmpty, reason: '${category.code} opens onto nothing');
        for (final entry in products) {
          expect(entry.product.category, category.code);
          expect(entry.product.price, isNotNull);
          expect(entry.shopName, isNotEmpty);
        }
        // cheapest first, like the SQL
        final prices = [for (final e in products) e.product.price!];
        expect(prices, [...prices]..sort());
      }
    });

    test('best offers are grouped and ranked cheapest first, like the SQL', () {
      expect(kShowcaseBestOffers, isNotEmpty);
      for (final group in kShowcaseBestOffers) {
        final baskets = [for (final shop in group.shops) shop.basketPrice!];
        expect(baskets, [...baskets]..sort(),
            reason: 'the ${group.category.code} tab is not cheapest-first');
      }
    });

    test('the showcase tiers are computed from the baskets, not hand-written', () {
      // the point of the showcase is to behave like the real thing. a hand-typed badge could drift
      // away from the basket printed next to it; deriving it the way the SQL view does cannot.
      for (final group in kShowcaseBestOffers) {
        final average = group.shops
                .map((s) => s.basketPrice!)
                .reduce((total, basket) => total + basket) /
            group.shops.length;

        for (final shop in group.shops) {
          final index = (shop.basketPrice! / average * 100).round();
          expect(shop.priceDifferencePercent, (index - 100).abs(),
              reason: '${shop.name} advertises a gap its own basket does not support');
        }
      }
    });

    test('every showcase shop carries a badge', () {
      // there is no market-size floor any more, so every ranked shop has a comparison - including
      // the only shop in a category, which is exactly average by definition
      for (final group in kShowcaseBestOffers) {
        for (final shop in group.shops) {
          expect(shop.priceTier, isNotNull, reason: '${shop.name} has no badge');
        }
      }
    });

    test('every VIP showcase row is actually flagged VIP', () {
      expect(kShowcaseVipShops, isNotEmpty);
      expect(kShowcaseVipShops.every((s) => s.isVip), isTrue);
    });

    test('a VIP shop can win a best-offer slot on price', () {
      // mirrors the real query, which does not exclude them
      expect(kShowcaseBestOffers.expand((g) => g.shops).any((s) => s.isVip), isTrue);
    });
  });
}
