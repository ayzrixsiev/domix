// stores_repository.dart
// simple placeholder repository for stores-related network/db actions
// keep implementation minimal; replace with real API calls later

class StoresRepository {
  // fetch list of stores (placeholder)
  Future<List<Map<String, dynamic>>> fetchStores() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {'id': 's1', 'name': 'Demo Store', 'lat': 0.0, 'lng': 0.0},
    ];
  }

  // create or update store (placeholder)
  Future<void> saveStore(Map<String, dynamic> store) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
