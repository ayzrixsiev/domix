import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/auth_service.dart';
import '../screens/profile_screen.dart';

// the signed-in account: the telegram handshake or the code that opens it, the checks that keep it
// honest, the ways it ends
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

  bool _isDeletingAccount = false;

  // a session died under a request the user made themselves, and nobody has told them yet.
  // SessionExpiryGuard watches this: it shows the dialog and then pops back to the shell.
  bool _sessionExpiredUnseen = false;

  // current ui state for ProfileScreen
  ProfileViewState _profileState = const ProfileViewState.guest();

  /// Why the last [deleteAccount] failed, as a machine-readable code the screen localizes. A code
  /// rather than a sentence: russian text held here would be frozen in whichever language happened to
  /// be selected when the request was made.
  String? _deleteAccountErrorCode;

  bool get isDeletingAccount => _isDeletingAccount;
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

  /// Called whenever an account becomes the current one - a cold boot onto a stored session, and a
  /// fresh sign-in. The mirror of [onSessionEnded], and wired the same way in `main()`.
  void Function()? onSessionStarted;

  // cold boot: read hardware storage to restore user state with no network round trip
  Future<void> checkExistingLogin() async {
    try {
      final token = await _authService.getToken();
      if (token == null || token.isEmpty) return;

      // **expiry is checked before anything is drawn, and without asking the server.** the `exp` claim is
      // readable offline, and a user whose token ran out must not see their own profile for the half
      // second it takes a network call to fail.
      if (AuthService.isTokenExpired(token)) {
        await _endSession();
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
  /// foreground, which is what lands a deleted account on the guest screen by itself. the cached
  /// hydration happens first, so a cold start does not wait on a check that almost always passes.
  ///
  /// **Only [SessionExpiredException] signs anyone out** - a timeout or a 500 is not evidence about
  /// the token.
  Future<void> verifySession() async {
    if (_profileState.isGuest) return;

    try {
      final me = await _authService.fetchMe();

      // the server's answer wins over the cache. this is also how a role change made elsewhere - the
      // admin panel, another phone - reaches this one without a sign-out.
      await _authService.saveSession(
        token: (await _authService.getToken())!,
        role: me.role,
        name: me.name,
        phone: me.phone,
      );
      _applyAccount(role: me.role, name: me.name, phone: me.phone);
    } on SessionExpiredException {
      // fetchMe already fired onSessionInvalidated; ending it twice is harmless and keeps the guarantee
      // local to the caller that can see it
      await _endSession();
    } catch (_) {
      // network trouble: keep the cached session exactly as it was
    }
  }

  /// Whether a server role may own and edit shops: `shop_owner`, **and `admin` too**. The backend
  /// authorizes the two identically, and signing in never demotes an admin - so an admin who
  /// signed up as «Владелец магазина» stays one, and comparing against the single literal `shop_owner`
  /// drew them the customer profile with no way in to shops they already own.
  static bool canManageShops(String role) =>
      role == 'shop_owner' || role == 'admin';

  void _applyAccount({
    required String role,
    required String name,
    required String phone,
  }) {
    final wasGuest = _profileState.isGuest;
    _profileState = canManageShops(role)
        ? ProfileViewState.vendor(
            initials: _getInitials(name),
            fullName: name,
            phoneNumber: phone,
            isAdmin: role == 'admin',
          )
        : ProfileViewState.client(
            initials: _getInitials(name),
            fullName: name,
            phoneNumber: phone,
          );
    // only on the edge: this also runs on every profile refresh, and re-fetching what belongs to a
    // session that never ended would be a request per rename
    if (wasGuest) onSessionStarted?.call();
    notifyListeners();
  }

  /// Step one of signing in: a session on the server and the link that opens our bot on it.
  ///
  /// **Nothing is stored and no state changes here**: until telegram hands the number over there is
  /// no account, which is why the server keeps the session out of its database too.
  Future<TelegramHandshake> startTelegramSignIn({
    required String name,
    required String role,
    required String lang,
  }) {
    return _authService.startTelegramSignIn(name: name, role: role, lang: lang);
  }

  /// One poll of that session. On `success` the token is already in secure storage and the profile
  /// has flipped to signed-in, so the caller only has to leave the screen.
  Future<String> pollTelegramSignIn(String session) async {
    final poll = await _authService.pollTelegramSignIn(session);
    final me = poll.me;
    // the same mapping the cached and /api/me paths use, rather than a second copy of the role
    // comparison - it was a second copy once, and only one of the two learned about `admin`
    if (me != null) {
      _applyAccount(role: me.role, name: me.name, phone: me.phone);
    }
    return poll.status;
  }

  /// The other door: a code to [phone], with the name and role the telegram session would carry.
  /// Nothing is stored here either. Throws [AuthApiException]; `sms_unavailable` is every number but
  /// the Play review account until Gateway is paid for.
  Future<CodeRequestResult> requestCode({
    required String phone,
    required String name,
    required String role,
  }) {
    return _authService.requestCode(phone: phone, name: name, role: role);
  }

  /// The code back for a session, landing exactly where a telegram `success` does.
  Future<void> verifyCode({required String phone, required String code}) async {
    final me = await _authService.verifyCode(phone: phone, code: code);
    _applyAccount(role: me.role, name: me.name, phone: me.phone);
  }

  /// Saves an edited profile: the display name, and the one role change the server allows
  /// (`customer -> shop_owner`).
  ///
  /// **The server's answer is what the app then believes**, not what was typed: a role refused as
  /// `role_locked` comes back as an exception, and a role the server quietly kept comes back as the
  /// role it kept. Throws [AuthApiException] with the refusal code, which the screen localizes.
  Future<void> updateProfile({String? name, String? role}) async {
    final me = await _authService.updateProfile(name: name, role: role);
    _applyAccount(role: me.role, name: me.name, phone: me.phone);
  }

  // the server told us this token is dead. not a button - it fires from whichever repository made the
  // request that came back 401, and the guest check keeps several in-flight 401s to one logout.
  // silent is the launch/resume check: nobody asked for it, so it signs out without a word.
  void _onSessionInvalidated({required bool silent}) {
    if (_profileState.isGuest) return;
    if (!silent) _sessionExpiredUnseen = true;
    unawaited(_endSession());
  }

  /// The «Выйти» button: ends the session on the server, then on this phone **whatever the server
  /// answered**, so an offline phone still signs out. Server first, because a revoke still in flight
  /// after a fresh sign-in would end that one too.
  Future<void> logout() async {
    await _authService.revokeSession();
    await _endSession();
  }

  // wipe local storage and reset the interface back to guest
  Future<void> _endSession({bool accountDeleted = false}) async {
    await _authService.clearSession();
    _profileState = const ProfileViewState.guest();
    // fired before notifyListeners, so whatever rebuilds below already sees the cleared shop lists -
    // the other order paints one frame of the old owner's shops onto the guest screen
    onSessionEnded?.call(accountDeleted);
    notifyListeners();
  }

  /// Destroys the account on the server, then wipes the phone the way [logout] does.
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
      await _endSession(accountDeleted: true);
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
