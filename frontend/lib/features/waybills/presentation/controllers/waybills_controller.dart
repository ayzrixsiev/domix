import 'package:flutter/foundation.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/waybills/data/waybill.dart';
import 'package:frontend/features/waybills/data/waybills_repository.dart';

/// What this customer has sent. Loaded when the tab comes into view rather than at sign-in: an owner's
/// session must not spend a refused request on a tab it never shows.
class WaybillsController extends ChangeNotifier {
  WaybillsController({WaybillsRepository? repository})
    : _repository = repository ?? WaybillsRepository();

  final WaybillsRepository _repository;

  List<Waybill> _items = const [];
  bool _loading = false;
  LoadFailure? _failure;

  List<Waybill> get items => _items;
  bool get isLoading => _loading;
  LoadFailure? get failure => _failure;

  WaybillsRepository get repository => _repository;

  Future<void> load() async {
    _loading = true;
    _failure = null;
    notifyListeners();

    try {
      _items = await _repository.fetchWaybills();
    } catch (error) {
      debugPrint('waybills: load failed ($error)');
      _failure = LoadFailure.of(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The list is on the server by now, so it is shown at once whatever the next [load] manages. By id,
  /// because a retry after a lost answer comes back with the row it already wrote.
  void add(Waybill waybill) {
    _items = [
      waybill,
      for (final item in _items)
        if (item.id != waybill.id) item,
    ];
    notifyListeners();
  }

  /// These are somebody's own lists, and the next person on this phone must not be handed them.
  void handleSessionEnded() {
    if (_items.isEmpty && _failure == null) return;
    _items = const [];
    _failure = null;
    notifyListeners();
  }
}
