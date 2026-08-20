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
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

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

  });

  group('HomeContent.fromJson edge cases', () {
    test('an empty database decodes to empty lists, not a crash', () {
      // the literal body the server returns today, with no shops in it
      const empty = '{"vip_shops":[],"best_offers":[]}';
      final content = HomeContent.fromJson(jsonDecode(empty) as Map<String, dynamic>);

      expect(content.vipShops, isEmpty);
      expect(content.bestOffers, isEmpty);
    });

    test('a null list is survived rather than thrown on', () {
      // the backend uses make(...) everywhere specifically so this cannot happen, but a decoder
      // that dies on it would turn one backend regression into a white screen
      const nulls = '{"vip_shops":null,"best_offers":null}';
      final content = HomeContent.fromJson(jsonDecode(nulls) as Map<String, dynamic>);

      expect(content.vipShops, isEmpty);
      expect(content.bestOffers, isEmpty);
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

  // ─────────────────────────── slots ───────────────────────────
  //
  // Where a paid placement lands is a commercial rule, not a layout detail, so it is tested here
  // rather than through a carousel: **the founder must never have to swipe past an empty card to
  // reach a shop that is paying for the section.** With one placement sold, that shop is what a
  // customer sees when the section comes into view, and the carousel opens on the middle position -
  // so "fills from the centre" and "opens on a real shop" are the same statement.

  group('vipSlotRing', () {
    HomeShopPreview shop(String name) => HomeShopPreview.fromShop(Shop(
          id: name.hashCode,
          name: name,
          contactPhone: '+998901112233',
          address: 'Ташкент',
          category: ShopCategory.universal,
          latitude: 41.3,
          longitude: 69.2,
          rating: 0,
          isVip: true,
        ));

    /// The ring as names, with `·` for an open slot - the table in the doc comment, executable.
    List<String> ringOf(int sold) => vipSlotRing(
          [for (var i = 0; i < sold; i++) shop(String.fromCharCode(65 + i))],
          slotCount: 5,
        ).map((slot) => slot?.name ?? '·').toList();

    test('fills from the centre outwards, alternating right then left', () {
      expect(ringOf(0), ['·', '·', '·', '·', '·']);
      expect(ringOf(1), ['·', '·', 'A', '·', '·']);
      expect(ringOf(2), ['·', '·', 'A', 'B', '·']);
      expect(ringOf(3), ['·', 'C', 'A', 'B', '·']);
      expect(ringOf(4), ['·', 'C', 'A', 'B', 'D']);
      expect(ringOf(5), ['E', 'C', 'A', 'B', 'D']);
    });

    test('the first placement is always at the position the carousel opens on', () {
      // the carousel parks on `length ~/ 2`, so this is the assertion that makes "a customer sees a
      // real shop, not an empty card" true - the rest of the arrangement is about the neighbours
      for (var sold = 1; sold <= 5; sold++) {
        final ring = ringOf(sold);
        expect(ring[ring.length ~/ 2], 'A', reason: 'with $sold sold, the centre is not the first');
      }
    });

    test('the nearest cards in both directions are the other real ones', () {
      // the second and third placements sit either side of the first, so one swipe in either
      // direction from the opening card lands on a paying shop before it lands on an empty one
      final ring = ringOf(3);
      final centre = ring.length ~/ 2;
      expect(ring[centre + 1], 'B');
      expect(ring[centre - 1], 'C');
    });

    test('always draws its full number of places, however few are sold', () {
      for (var sold = 0; sold <= 5; sold++) {
        expect(ringOf(sold), hasLength(5));
      }
    });

    test('more placements than places grows the ring instead of dropping one', () {
      // hiding a placement somebody paid for is the failure this whole section is built to avoid,
      // so a backend that grew the inventory must cost an app an extra card, never a card
      final shops = [for (var i = 0; i < 7; i++) shop('shop$i')];
      final ring = vipSlotRing(shops, slotCount: 5);

      expect(ring, hasLength(7));
      expect(ring.whereType<HomeShopPreview>(), hasLength(7));
      // and no two placements landed on the same position, which is what the modulo has to hold
      expect(ring.map((s) => s!.name).toSet(), hasLength(7));
      // the first one is still what the carousel opens on
      expect(ring[ring.length ~/ 2]!.name, 'shop0');
    });
  });

  group('rankedSlots', () {
    HomeShopPreview shop(String name) => HomeShopPreview.fromShop(Shop(
          id: name.hashCode,
          name: name,
          contactPhone: '+998901112233',
          address: 'Ташкент',
          category: ShopCategory.universal,
          latitude: 41.3,
          longitude: 69.2,
          rating: 0,
        ));

    test('keeps the server ordering and pads the tail', () {
      // **in order, not centred** - the difference from the ring above. this section is a ranking:
      // the top of the list is the cheapest shop and the reader is meant to start there.
      final slots = rankedSlots([shop('A'), shop('B')], slotCount: 5);

      expect(slots.map((s) => s?.name).toList(), ['A', 'B', null, null, null]);
    });

    test('never truncates', () {
      final shops = [for (var i = 0; i < 8; i++) shop('shop$i')];
      expect(rankedSlots(shops, slotCount: 5), hasLength(8));
    });

    test('nothing ranked is still a full set of places', () {
      expect(rankedSlots(const [], slotCount: 15), hasLength(15));
      expect(rankedSlots(const [], slotCount: 15).whereType<HomeShopPreview>(), isEmpty);
    });
  });
}
