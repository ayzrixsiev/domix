import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Why the phone did not say where it is. **An enum rather than one exception per case**: all four
/// end up as one sentence on the map's banner, and two of them have a button that opens a different
/// system page.
enum UserLocationFailure {
  /// location is switched off for the whole phone - our dialog cannot fix that, the settings can
  servicesOff,

  /// refused this once. asking again is allowed, so the sentence just says what is missing.
  denied,

  /// refused for good, or blocked by a device policy - only the app's own settings page undoes it
  deniedForever,

  /// granted, but no fix arrived in time or the platform threw
  unavailable,
}

class UserLocationException implements Exception {
  const UserLocationException(this.failure);

  final UserLocationFailure failure;

  @override
  String toString() => 'UserLocationException(${failure.name})';
}

/// The phone's own position, for one press of «Рядом со мной».
///
/// **One fix per press, never a subscription.** The map uses the point to move the camera once; a
/// stream would keep the gps awake for as long as the tab is open and buy nothing - nobody walks
/// while reading a shop list. The coordinate is not stored and not sent to our api.
class UserLocationService {
  /// Long enough for a cold gps indoors, short enough that the spinner is not a hang.
  static const Duration _timeout = Duration(seconds: 12);

  /// How stale the phone's last known fix may be before showing it would be a lie. The camera is
  /// about to move by kilometres, so minutes-old is still the right neighbourhood.
  static const Duration _lastKnownMaxAge = Duration(minutes: 5);

  /// Asks, requesting the permission if it has never been answered. Throws
  /// [UserLocationException] for every way this ends without a point.
  Future<({double latitude, double longitude})> current() async {
    // checked first because the permission dialog is pointless while the whole radio is off: the
    // user would grant it and still get nothing
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const UserLocationException(UserLocationFailure.servicesOff);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const UserLocationException(UserLocationFailure.deniedForever);
    }
    if (permission == LocationPermission.denied) {
      throw const UserLocationException(UserLocationFailure.denied);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        // `medium` is the fused network/gps provider, which answers in a second indoors where a
        // `best` request waits for satellites. a map at city zoom cannot show the difference.
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _timeout,
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (e) {
      debugPrint('UserLocationService: no fix: $e');

      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp) < _lastKnownMaxAge) {
        return (latitude: last.latitude, longitude: last.longitude);
      }
      throw const UserLocationException(UserLocationFailure.unavailable);
    }
  }

  /// Opens the page that can undo [failure] - the phone's location switch, or our own permissions.
  /// Sending the user to the wrong one of the two is a dead end they cannot tell from a bug.
  Future<void> openSettingsFor(UserLocationFailure failure) async {
    if (failure == UserLocationFailure.servicesOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
