import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/auth_service.dart';
import '../screens/profile_screen.dart';

// auth manager that decides when to init handshake, process incoming data and notify ui components to change
class AuthController extends ChangeNotifier {

  // private, once assigned to the object unchangeable controller which is created once at the app start
  static final AuthController _instance = AuthController._internal();

  // factory returns the same controller every time it is called like this AuthController(), no copies made
  factory AuthController() => _instance;

  AuthController._internal() {
    // the backend has no way to reach the app, so "your account is gone" arrives as a 401 on the
    // next request a repository happens to make. this is where that turns into a logout.
    AuthService.onSessionInvalidated = _onSessionInvalidated;

    // and this is the other half: re-check whenever the app comes back to the foreground, so a user
    // deleted while their phone was in a pocket finds a guest screen when they take it out, instead
    // of a profile that stops working the first time they press something.
    _lifecycle = _AppLifecycleWatcher(onResumed: verifySession);
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  late final _AppLifecycleWatcher _lifecycle;

  final AuthService _authService = AuthService();
  
  bool _isPolling = false;
  bool _isLoading = false;

  // deliberately *not* _isLoading. that flag draws the "open telegram and share your number"
  // overlay, which is the wrong thing to show somebody who just asked to be deleted.
  bool _isDeletingAccount = false;
  String? _loginErrorDetail;

  // holds current ui state for the profilescreen
  ProfileViewState _profileState = const ProfileViewState.guest();

  /// Why the last [deleteAccount] failed, as a machine-readable code the screen localizes:
  /// `timeout` when the server never answered, `server_error` for anything else. Null when the last
  /// attempt succeeded, or when none has been made.
  ///
  /// A code rather than a sentence, matching the contract the shop and product endpoints already
  /// use: this controller must not hold russian text, or the message would be frozen in whichever
  /// language happened to be selected when the request was made.
  String? _deleteAccountErrorCode;

  bool get isLoading => _isLoading;
  bool get isDeletingAccount => _isDeletingAccount;
  /// The raw reason a login attempt failed - **for the log and for nothing else.**
  ///
  /// It is deliberately not called `errorMessage`: it is an English exception string
  /// (`Failed to initialize login session: 502`, `Could not open Telegram`), assembled for whoever
  /// debugs it. `ProfileScreen` printed it verbatim in the waiting overlay for a while, which is the
  /// same class of bug as `_showErrorDialog` rendering the login copy for a failed deletion
  /// (CLAUDE.md §8): **a field whose name promises a sentence the user can read, holding one they
  /// cannot.** The screen shows written copy and passes this to `debugPrint`.
  ///
  /// Non-null is still the *signal* that the attempt failed, which is what the overlay reads it for.
  String? get loginErrorDetail => _loginErrorDetail;
  String? get deleteAccountErrorCode => _deleteAccountErrorCode;
  ProfileViewState get profileState => _profileState;

  /// Called once the session has ended, with whether the account itself was destroyed.
  ///
  /// **A callback, not an import.** `StoresController` holds a snapshot of every shop on the map,
  /// and deleting an account destroys that user's shops server-side - so those pins are wrong the
  /// instant this fires, and nothing else would ever tell the map so. Wiring it as a field rather
  /// than importing the stores feature keeps `profile/` from depending on `stores/`, the same way
  /// [AuthService.onSessionInvalidated] keeps `data/` from depending on `presentation/`. `main()`
  /// connects the two ends.
  ///
  /// The flag matters: a plain logout leaves every shop standing and ends only *our* right to
  /// manage them, while a deletion takes them off the map for everybody.
  void Function(bool accountDeleted)? onSessionEnded;

  // cold boot check: read hardware storage on startup to instantly restore user state without network or backend interaction
  Future<void> checkExistingLogin() async {
    try {
      final token = await _authService.getToken();
      if (token == null || token.isEmpty) return;

      // **expiry is checked before anything is drawn, and without asking the server.** the `exp`
      // claim is plain readable JSON inside the token, so four-months-later is knowable offline -
      // and a user whose token ran out must not see their own profile for the half second it takes
      // a network call to fail.
      if (AuthService.isTokenExpired(token)) {
        await logout();
        return;
      }

      final role = await _authService.getRole() ?? 'customer';
      final name = await _authService.getName() ?? 'Domix User';
      final phone = await _authService.getPhone() ?? '';

      // instantly hydrate profile state from local cache
      _applyAccount(role: role, name: name, phone: phone);
    } catch (_) {
      // if storage read fails or is corrupted, safely remain in guest state
    }
  }

  /// Asks the server whether this session is still real, and updates what it says about us.
  ///
  /// **Called after [checkExistingLogin] on launch and again on every return to the foreground**,
  /// which is what makes a deleted account land on the guest screen by itself rather than on the
  /// next thing the user taps. The cached hydration above happens first on purpose: this is a
  /// network round trip, and blocking the first frame on it would give every cold start a spinner
  /// to pay for a check that almost always passes.
  ///
  /// **Only [SessionExpiredException] signs anyone out.** A timeout, a 500, a tunnel - none of those
  /// are evidence about the token, and treating them as such would log people out of a working
  /// account every time the server hiccuped.
  Future<void> verifySession() async {
    if (_profileState.isGuest) return;

    try {
      final me = await _authService.fetchMe();

      // the server's answer wins over the cache. this is also how a role change reaches an app that
      // has been installed since before it: a customer who registered a shop becomes a shop_owner
      // during the telegram flow, and until this existed the owner screens stayed hidden until they
      // signed out and back in.
      await _authService.saveSession(
        token: (await _authService.getToken())!,
        role: me.role,
        name: me.name,
        phone: me.phone,
      );
      _applyAccount(role: me.role, name: me.name, phone: me.phone);
    } on SessionExpiredException {
      // fetchMe already fired onSessionInvalidated; logging out twice is harmless and this keeps the
      // guarantee local to the caller that can see it
      await logout();
    } catch (_) {
      // network trouble. keep the cached session exactly as it was.
    }
  }

  void _applyAccount({required String role, required String name, required String phone}) {
    _profileState = role == 'shop_owner'
        ? ProfileViewState.vendor(
            initials: _getInitials(name),
            fullName: name,
            phoneNumber: phone,
          )
        : ProfileViewState.client(
            initials: _getInitials(name),
            fullName: name,
            phoneNumber: phone,
          );
    notifyListeners();
  }

  // handshake orchestration, start login pipeline by sending name and role to golang and open telegram app
  Future<void> startTelegramLogin({
    required String name, 
    required String role,
    required VoidCallback onSuccess,
  }) async {
    try {
      _isLoading = true;
      _loginErrorDetail = null;
      notifyListeners();

      // step 1: hit go backend /init
      final initResult = await _authService.initSession(name: name, role: role);

      // step 2: open telegram app
      //
      // launched directly rather than behind a canLaunchUrl gate, and the gate is what broke login
      // on every real phone. two things were wrong with it. **canLaunchUrl asks "can anything on
      // this device open an https URL", which is not the question** - and on Android 11+ it answers
      // false unless the manifest declares a <queries> intent for VIEW+https, which ours did not, so
      // it failed with Telegram installed and a browser sitting right there. And the message it
      // threw named the wrong cause: the t.me link is an ordinary https URL, so a phone *without*
      // Telegram opens Telegram's own web preview rather than failing, which is exactly why the
      // documented deep-link format is used instead of the tg:// scheme.
      //
      // launchUrl returns false (or throws) when nothing handled it, which is the real signal.
      final uri = Uri.parse(initResult.telegramUrl);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw Exception("Could not open Telegram");
      }

      // step 3: start 2-second background polling
      _startPolling(initResult.sessionId, name, onSuccess);

    } catch (e) {
      _isLoading = false;
      _loginErrorDetail = e.toString().replaceAll("Exception: ", "");
      notifyListeners();
    }
  }

  // ask backend whether login was successful every 2 seconds 60 times at max
  void _startPolling(String sessionId, String userName, VoidCallback onSuccess) {
    _cancelPolling(); // kill any polling loops before starting new

    _isPolling = true;

    // it runs polling in a separate async background thread to avoid overlapping requests
    () async {
      const maxAttempts = 60;
      int attempts = 0;

      while (_isPolling && attempts < maxAttempts) {
        attempts++;
        try {
          final result = await _authService.checkStatus(sessionId);

          if (result.isSuccess && result.token != null) {
            // stop polling
            _isPolling = false;

            final displayName = result.name ?? userName;
            final displayPhone = result.phone ?? '';
            final displayRole = result.role ?? 'customer';

            // persist session securely
            await _authService.saveSession(
              token: result.token!,
              role: displayRole,
              name: displayName,
              phone: displayPhone,
            );

            // update state
            if (displayRole == 'shop_owner') {
              _profileState = ProfileViewState.vendor(
                initials: _getInitials(displayName),
                fullName: displayName,
                phoneNumber: displayPhone,
              );
            } else {
              _profileState = ProfileViewState.client(
                initials: _getInitials(displayName),
                fullName: displayName,
                phoneNumber: displayPhone,
              );
            }

            _isLoading = false;
            notifyListeners();
            onSuccess();
            return;
          }
        } catch (_) {
          // ignore temporary errors; continue polling
        }

        // wait between attempts; check cancellation flag while waiting
        for (int i = 0; i < 20; i++) {
          if (!_isPolling) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      if (_isPolling) {
        // max attempts reached or was not successful
        _isPolling = false;
        _isLoading = false;
        notifyListeners();
      }
    }();
  }

  void _cancelPolling() {
    _isPolling = false;
  }

  // dismiss the current error once the user has read it and pressed ok, so it doesn't linger forever
  void clearError() {
    _loginErrorDetail = null;
    notifyListeners();
  }

  /// The server told us this token is dead - wipe it and drop to the guest state.
  ///
  /// Separate from [logout] only in how it is reached: this one is not a button, it fires from
  /// whichever repository happened to make the request that came back 401. Guarded against firing
  /// twice, because several repositories can be in flight at once and each of them will report the
  /// same 401 - without the guard the profile screen would rebuild once per request.
  void _onSessionInvalidated() {
    if (_profileState.isGuest) return;
    unawaited(logout());
  }

  // wipe local storage and reset interface back to guest state
  Future<void> logout({bool accountDeleted = false}) async {
    _cancelPolling();
    _isLoading = false;
    _loginErrorDetail = null;
    await _authService.logout();
    _profileState = const ProfileViewState.guest();
    // fired before notifyListeners, so whatever rebuilds on the line below already sees the cleared
    // shop lists. the other order paints one frame of the old owner's shops onto the guest screen -
    // brief, but it is exactly the frame somebody screenshots.
    onSessionEnded?.call(accountDeleted);
    notifyListeners();
  }

  /// Destroys the account on the server, then does everything [logout] does.
  ///
  /// **Server first, phone second, and the order is the whole design.** Wiping local storage before
  /// the request would throw away the token the request needs; wiping it after a *failed* request
  /// would leave the user signed out of an account that still exists, with their shops still on the
  /// map and no session to try again with. So nothing local is touched until the server has
  /// confirmed, and a failure leaves the app exactly as it was.
  ///
  /// Returns true when the account is gone. The caller shows the error itself rather than reading
  /// [loginErrorDetail], because this is a modal flow with its own dialog - routing it through the
  /// shared error field would paint it over the profile screen after the sheet has closed.
  Future<bool> deleteAccount() async {
    if (_isDeletingAccount) return false;

    _isDeletingAccount = true;
    _deleteAccountErrorCode = null;
    notifyListeners();

    try {
      await _authService.deleteAccount();
      // `accountDeleted: true` is what takes this owner's pins off the map. a plain logout must not
      // do that - the shops are still there, they are simply no longer ours to edit.
      await logout(accountDeleted: true);
      return true;
    } on TimeoutException catch (e) {
      // its own code, because it is its own instruction: the request may well have reached the
      // server, so "press Удалить again" is the right advice and "check your connection" is not.
      // the same distinction ProductsController draws for a save that ran out of time.
      debugPrint('deleteAccount timed out: $e');
      _deleteAccountErrorCode = 'timeout';
      return false;
    } catch (e) {
      // logged, not swallowed. this used to catch into `_` and return false, so the one string that
      // explains a failed deletion existed for a microsecond inside a catch block and no human ever
      // saw it - the same bug ProductsController._mutate was fixed for.
      debugPrint('deleteAccount failed: $e');
      _deleteAccountErrorCode = 'server_error';
      return false;
    } finally {
      // in the success case logout() has already notified; this runs after it and is what clears the
      // spinner. `finally` rather than a line in each branch, so an exception type nobody predicted
      // cannot leave the button disabled forever.
      _isDeletingAccount = false;
      notifyListeners();
    }
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "U";
    final parts = name.trim().split(" ");
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return "${parts[0][0]}${parts[1][0]}".toUpperCase();
    }
    return name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
  }

 // right before removing auth controller, turn off polling
  @override
  void dispose() {
    _cancelPolling();
    WidgetsBinding.instance.removeObserver(_lifecycle);
    super.dispose();
  }
}

/// Turns "the app came back to the foreground" into a callback.
///
/// A separate object rather than making AuthController itself a WidgetsBindingObserver: the observer
/// mixin would drag fifteen lifecycle methods the controller has no opinion about into a class whose
/// job is the login state machine.
class _AppLifecycleWatcher extends WidgetsBindingObserver {
  _AppLifecycleWatcher({required this.onResumed});

  final Future<void> Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(onResumed());
  }
}
