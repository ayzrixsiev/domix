import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/data/stores_repository.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';

/// The map's shop list is a **snapshot**, and these pin the two ways it goes wrong.
///
/// Both bugs were found on a real phone and both are silent: the map still renders, it just renders
/// something that is no longer true. Neither is reachable from a widget test of `MapScreen` either,
/// since MapKit does not exist on a test host - so the rules live on the controller and are checked
/// here, which is also where they belong.
void main() {
  group('a deleted account takes its pins with it', () {
    test('the owner\'s shops leave the public map, and nobody else\'s do', () async {
      final repo = _FakeStoresRepository(
        stores: [_shop(1, 'Мой магазин'), _shop(2, 'Чужой магазин')],
        myShops: [_shop(1, 'Мой магазин')],
      );
      final controller = StoresController(repository: repo);

      await controller.loadStores();
      await controller.loadMyShops();
      expect(controller.stores.map((s) => s.id), [1, 2]);

      controller.handleSessionEnded(true);

      // shop 1 is gone from the map at the same instant the account is - the server's cascade
      // already destroyed it, and waiting for a re-fetch would leave a pin pointing at nothing.
      // shop 2 belongs to somebody else and is untouched.
      expect(controller.stores.map((s) => s.id), [2]);
      expect(controller.myShops, isEmpty);
    });

    test('a plain logout leaves every pin standing', () async {
      final repo = _FakeStoresRepository(
        stores: [_shop(1, 'Мой магазин'), _shop(2, 'Чужой магазин')],
        myShops: [_shop(1, 'Мой магазин')],
      );
      final controller = StoresController(repository: repo);

      await controller.loadStores();
      await controller.loadMyShops();

      controller.handleSessionEnded(false);

      // signing out ends our right to *manage* a shop. it does not close the shop, and blanking it
      // off the map would be the app inventing a fact about somebody else's business.
      expect(controller.stores.map((s) => s.id), [1, 2]);
      // the management list still goes: there is nobody left to manage it
      expect(controller.myShops, isEmpty);
    });

    test('the snapshot is marked stale either way, so the next map visit re-syncs', () async {
      final repo = _FakeStoresRepository(stores: [_shop(1, 'Магазин')]);
      final controller = StoresController(repository: repo);

      await controller.loadStores();
      expect(controller.isStoresStale, isFalse);

      controller.handleSessionEnded(true);

      // this is what covers the case the subtraction above cannot: an owner who deletes their
      // account without ever opening "Мои магазины" leaves _myShops empty, so there are no ids to
      // subtract - and the re-fetch is the only thing that gets those pins off the map.
      expect(controller.isStoresStale, isTrue);
      await controller.refreshStoresIfStale();
      expect(repo.fetchStoresCalls, 2);
    });
  });

  group('a failed load does not become permanent', () {
    test('a stale-check after a failure retries, and a fresh list does not', () async {
      final repo = _FakeStoresRepository(stores: [_shop(1, 'Магазин')], failNextFetch: true);
      final controller = StoresController(repository: repo);

      await controller.loadStores();
      expect(controller.loadError, isNotNull);
      expect(controller.stores, isEmpty);

      // the bug this exists for: MapScreen.initState runs once per app session and IndexedStack
      // keeps the State alive, so a failed load used to leave «Не удалось загрузить магазины» on
      // screen with nothing - not even restarting the app - able to clear it.
      expect(controller.isStoresStale, isTrue);
      await controller.refreshStoresIfStale();
      expect(repo.fetchStoresCalls, 2);
      expect(controller.loadError, isNull);
      expect(controller.stores, hasLength(1));

      // and the other half: a list fetched a moment ago is left alone, so flicking between tabs is
      // not a request per switch
      await controller.refreshStoresIfStale();
      expect(repo.fetchStoresCalls, 2);
    });

    test('a second load while one is in flight is dropped', () async {
      final repo = _FakeStoresRepository(stores: [_shop(1, 'Магазин')], holdFetch: true);
      final controller = StoresController(repository: repo);

      final first = controller.loadStores();
      // not awaited: this is the tab-switch-while-loading case, and without the guard it would
      // stack a second ten-second timeout behind the first
      final second = controller.loadStores();
      repo.releaseFetch();
      await Future.wait([first, second]);

      expect(repo.fetchStoresCalls, 1);
    });
  });
}

Shop _shop(int id, String name) => Shop(
      id: id,
      name: name,
      contactPhone: '+998901112233',
      address: 'Ташкент',
      category: ShopCategory.universal,
      latitude: 41.3,
      longitude: 69.2,
      rating: 0,
    );

/// Stands in for the HTTP layer. Extends the real repository rather than implementing an interface,
/// because [StoresController] takes the concrete type - a one-test abstraction would be a second
/// contract to keep in step for no gain here.
class _FakeStoresRepository implements StoresRepository {
  _FakeStoresRepository({
    this.stores = const [],
    this.myShops = const [],
    this.failNextFetch = false,
    this.holdFetch = false,
  });

  List<Shop> stores;
  List<Shop> myShops;
  bool failNextFetch;

  /// Keeps [fetchStores] pending until [releaseFetch], so a second call can be made while the first
  /// is still in flight - the only way to exercise the in-flight guard.
  bool holdFetch;
  final _gate = Completer<void>();

  int fetchStoresCalls = 0;

  void releaseFetch() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<List<Shop>> fetchStores() async {
    fetchStoresCalls++;
    if (holdFetch) await _gate.future;
    if (failNextFetch) {
      failNextFetch = false;
      throw Exception('Failed to load shops (503)');
    }
    return List.of(stores);
  }

  @override
  Future<List<Shop>> fetchMyShops() async => List.of(myShops);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by these tests');
}
