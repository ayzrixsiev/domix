import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Says whose camera Android killed the app under. `retrieveLostData` hands back the last picture of
/// any picker, and an owner photographing a product holds the same session as one photographing a list.
///
/// **Without it a lost product photo opens as a накладная on the next launch**, so the waybill picker
/// marks itself before it opens and clears the mark however the picker ends. A storage failure only
/// costs the recovery, never the picker.
class WaybillPhotoMarker {
  const WaybillPhotoMarker();

  static const _storage = FlutterSecureStorage();
  static const _key = 'domix_waybill_picker_open';

  Future<void> set() async {
    try {
      await _storage.write(key: _key, value: '1');
    } catch (error) {
      debugPrint('waybills: could not mark the picker ($error)');
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (error) {
      debugPrint('waybills: could not clear the picker mark ($error)');
    }
  }

  /// Whether the waybill picker was open when the app died, and the mark gone either way.
  Future<bool> take() async {
    bool marked;
    try {
      marked = await _storage.read(key: _key) != null;
    } catch (error) {
      debugPrint('waybills: could not read the picker mark ($error)');
      marked = false;
    }
    await clear();
    return marked;
  }
}
