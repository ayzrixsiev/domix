import 'package:flutter/foundation.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

/// A shop another screen wants the map to show. **A request that waits to be taken, not a stream**:
/// the map tab is built at launch but its native window may not exist yet, so the request has to
/// survive until the map is ready for it.
class MapFocusController extends ChangeNotifier {
  Shop? _request;

  Shop? get request => _request;

  void show(Shop shop) {
    _request = shop;
    notifyListeners();
  }

  Shop? take() {
    final shop = _request;
    _request = null;
    return shop;
  }
}
