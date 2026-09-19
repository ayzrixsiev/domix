import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/auth_service.dart';
import '../screens/profile_screen.dart';

// decides when to start the telegram handshake, processes what comes back, and tells the ui
class AuthController extends ChangeNotifier {

  // one controller for the app's life; the factory hands back the same instance every time
  static final AuthController _instance = AuthController._internal();

  factory AuthController() => _instance;

  AuthController._internal() {
    // the backend cannot reach the app, so "your account is gone" arrives as a 401 on whatever
    // request a repository happens to make next. this is where that turns into a logout.
    AuthService.onSessionInvalidated = _onSessionInvalidated;

    // the other half: re-check on every return to the foreground, so an account deleted while the
    // phone was in a pocket is already signed out when it comes back out.
    _lifecycle = _AppLifecycleWatcher(onResumed: verifySession);
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  late final _AppLifecycleWatcher _lifecycle;

  final AuthService _authService = AuthService();
  
  bool _isLoading = false;

  // deliberately *not* _isLoading: that flag draws the "open telegram and share your number" overlay,
  // which is the wrong thing to show somebody who just asked to be deleted
  bool _isDeletingAccount = false;
  String? _loginErrorDetail;

  // a session died under a request the user made themselves, and nobody has told them yet.
  // SessionExpiryGuard watches this: it shows the dialog and then pops back to the shell.
  bool _sessionExpiredUnseen = false;

  // current ui state for ProfileScreen
  ProfileViewState _profileState = const ProfileViewState.guest();

  /// Why the last [deleteAccount] failed, as a machine-readable code the screen localizes. A code
  /// rather than a sentence: russian text held here would be frozen in whichever language happened to
  /// be selected when the request was made.
  String? _deleteAccountErrorCode;

  bool get isLoading => _isLoading;
  bool get isDeletingAccount => _isDeletingAccount;
  /// The raw reason a login attempt failed - **for the log and for nothing else**: it is an English
  /// exception string assembled for whoever debugs it, and it ended up drawn in the waiting overlay
  /// once. Non-null is still the *signal* that the attempt failed.
  String? get loginErrorDetail => _loginErrorDetail;
  String? get deleteAccountErrorCode => _deleteAccountErrorCode;
  ProfileViewState get profileState => _profileState;
  bool get sessionExpiredUnseen => _sessionExpiredUnseen;

  // the guard calls this once the dialog has been read, so it is announced exactly once
  void acknowledgeSessionExpiry() {
    if (!_sessionExpiredUnseen) return;
    _sessionExpiredUnseen = false;
    notifyListeners();
  }

  /// Called once the session has ended, with whether the account itself was destroyed.
  ///
  /// **A callback, not an import**, which keeps `profile/` from depending on `stores/`; `main()`
  /// connects the two ends. The flag matters: a plain logout leaves every shop standing, while a
  /// deletion takes them off the map for everybody.
  void Function(bool accountDeleted)? onSessionEnded;

  // cold boot: read hardware storage to restore user state with no network round trip
  Future<void> checkExistingLogin() async {
    try {
      final token = await _authService.getToken();
      if (token == null || token.isEmpty) return;

      // **expiry is checked before anything is drawn, and without asking the server.** the `exp` claim is
      // readable offline, and a user whose token ran out must not see their own profile for the half
      // second it takes a network call to fail.
      if (AuthService.isTokenExpired(token)) {
        await logout();
        return;
      }

      final role = await _authService.getRole() ?? 'customer';
      final name = await _authService.getName() ?? 'Domix User';
      final phone = await _authService.getPhone() ?? '';

      // hydrate profile state from the local cache
      _applyAccount(role: role, name: name, phone: phone);
    } catch (_) {
      // storage read failed or is corrupted: stay in the guest state
    }
  }

  /// Asks the server whether this session is still real, on launch and on every return to the
  /// foreground - which is what makes a deleted account land on the guest screen by itself. The cached
  /// hydration happens first on purpose, so a cold start does not wait on a check that almost always
  /// passes.
  ///
  /// **Only [SessionExpiredException] signs anyone out** - a timeout, a 500 or a tunnel is not
  /// evidence about the token.
  Future<void> verifySession() async {
    if (_profileState.isGuest) return;

    try {
      final me = await _authService.fetchMe();

      // the server's answer wins over the cache. this is also how a role change reaches an installed app:
      // a customer who registers a shop becomes a shop_owner during the telegram flow, and the owner
      // screens used to stay hidden until they signed out and back in.
      await _authService.saveSession(
        token: (await _authService.getToken())!,
        role: me.role,
        name: me.name,
        phone: me.phone,
      );
      _applyAccount(role: me.role, name: me.name, phone: me.phone);
    } on SessionExpiredException {
      // fetchMe already fired onSessionInvalidated; logging out twice is harmless and keeps the guarantee
      // local to the caller that can see it
      await logout();
    } catch (_) {
      // network trouble: keep the cached session exactly as it was
    }
  }

  /// Whether a server role may own and edit shops: `shop_owner`, **and `admin` too**. The backend
  /// authorizes the two identically, and the Telegram handler never demotes an admin - so an admin who
  /// signed up as «Владелец магазина» stays one, and comparing against the single literal `shop_owner`
  /// drew them the customer profile with no way in to shops they already own.
  static bool canManageShops(String role) => role == 'shop_owner' || role == 'admin';

  void _applyAccount({required String role, required String name, required String phone}) {
    _profileState = canManageShops(role)
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

  /// Step one of signing in: ask the server to send a one-time code to [phone].
  ///
  /// Returns the number in the server's own canonical spelling (`998XXXXXXXXX`) - [verifyCode] must
  /// be called with that, not with whatever was typed. Throws [AuthApiException] carrying the
  /// server's refusal code, which the screen turns into a sentence.
  ///
  /// **Nothing is stored and no state changes here.** Until a code comes back verified there is no
  /// account, which is the same reason the server keeps pending codes out of its database.
  Future<CodeRequestResult> requestCode({
    required String phone,
    required String name,
    required String role,
  }) {
    return _authService.requestCode(phone: phone, name: name, role: role);
  }

  /// Step two: exchange the code for a session. On success the token is already in secure storage
  /// and the profile state has flipped to signed-in, so the caller only has to leave the screen.
  Future<void> verifyCode({required String phone, required String code}) async {
    final me = await _authService.verifyCode(phone: phone, code: code);
    // the same mapping the cached and /api/me paths use, rather than a second copy of the role
    // comparison - it was a second copy once, and only one of the two learned about `admin`
    _applyAccount(role: me.role, name: me.name, phone: me.phone);
  }

  // dismiss the current error once the user has read it, so it doesn't linger forever
  void clearError() {
    _loginErrorDetail = null;
    notifyListeners();
  }

  // the server told us this token is dead. not a button - it fires from whichever repository made the
  // request that came back 401, and the guest check keeps several in-flight 401s to one logout.
  // silent is the launch/resume check: nobody asked for it, so it signs out without a word.
  void _onSessionInvalidated({required bool silent}) {
    if (_profileState.isGuest) return;
    if (!silent) _sessionExpiredUnseen = true;
    unawaited(logout());
  }

  // wipe local storage and reset the interface back to guest
  Future<void> logout({bool accountDeleted = false}) async {
    _isLoading = false;
    _loginErrorDetail = null;
    await _authService.logout();
    _profileState = const ProfileViewState.guest();
    // fired before notifyListeners, so whatever rebuilds below already sees the cleared shop lists -
    // the other order paints one frame of the old owner's shops onto the guest screen
    onSessionEnded?.call(accountDeleted);
    notifyListeners();
  }

  /// Destroys the account on the server, then does everything [logout] does.
  ///
  /// **Server first, phone second, and the order is the whole design**: wiping storage first throws
  /// away the token the request needs, and wiping it after a *failed* request signs the user out of an
  /// account that still exists. Returns true when the account is gone; the caller shows the error.
  Future<bool> deleteAccount() async {
    if (_isDeletingAccount) return false;

    _isDeletingAccount = true;
    _deleteAccountErrorCode = null;
    notifyListeners();

    try {
      await _authService.deleteAccount();
      // `accountDeleted: true` is what takes this owner's pins off the map. a plain logout must not do
      // that - the shops are still there, they are simply no longer ours to edit.
      await logout(accountDeleted: true);
      return true;
    } on TimeoutException catch (e) {
      // its own code, because it is its own instruction: the request may well have reached the server, so
      // "press Удалить again" is the right advice and "check your connection" is not
      debugPrint('deleteAccount timed out: $e');
      _deleteAccountErrorCode = 'timeout';
      return false;
    } catch (e) {
      // logged, not swallowed: this used to catch into `_`, so the one string explaining a failed deletion
      // existed for a microsecond inside a catch block and no human ever saw it
      debugPrint('deleteAccount failed: $e');
      _deleteAccountErrorCode = 'server_error';
      return false;
    } finally {
      // `finally` rather than a line in each branch, so an exception type nobody predicted cannot leave
      // the button disabled forever
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycle);
    super.dispose();
  }
}

/// Turns "the app came back to the foreground" into a callback. A separate object, so the observer
/// mixin's fifteen lifecycle methods do not land on a class whose job is the login state machine.
class _AppLifecycleWatcher extends WidgetsBindingObserver {
  _AppLifecycleWatcher({required this.onResumed});

  final Future<void> Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(onResumed());
  }
}
