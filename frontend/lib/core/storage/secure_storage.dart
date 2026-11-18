import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one secure store the app opens. **Every caller shares these options**: Android keeps one native
/// store per file and fixes its options at the first call, so a second instance with other options
/// would silently run on whichever came first.
///
/// **`resetOnError: false` is what keeps people signed in.** The plugin's default wipes the whole store
/// on any read or write error, a Keystore hiccup included, and the app then opens as a guest with the
/// server never having refused anything.
const appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(resetOnError: false),
);

/// Wipes a store that cannot be opened at all, keys and data, so it can be written again. Only for a
/// sign-in holding a fresh token: the reset options are taken only while the store is failing to open.
Future<void> resetBrokenSecureStorage() =>
    const FlutterSecureStorage().deleteAll(aOptions: const AndroidOptions());
