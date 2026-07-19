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

  AuthController._internal();
  
  final AuthService _authService = AuthService();
  
  bool _isPolling = false;
  bool _isLoading = false;
  String? _errorMessage;
  
  // holds current ui state for the profilescreen
  ProfileViewState _profileState = const ProfileViewState.guest();

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ProfileViewState get profileState => _profileState;

  // cold boot check: read hardware storage on startup to instantly restore user state without network or backend interaction
  Future<void> checkExistingLogin() async {
    try {
      final token = await _authService.getToken();
      if (token == null || token.isEmpty) return;

      final role = await _authService.getRole() ?? 'customer';
      final name = await _authService.getName() ?? 'Domix User';
      final phone = await _authService.getPhone() ?? '';

      // instantly hydrate profile state from local cache
      if (role == 'shop_owner') {
        _profileState = ProfileViewState.vendor(
          initials: _getInitials(name),
          fullName: name,
          phoneNumber: phone,
        );
      } else {
        _profileState = ProfileViewState.client(
          initials: _getInitials(name),
          fullName: name,
          phoneNumber: phone,
        );
      }
      notifyListeners();
    } catch (_) {
      // if storage read fails or is corrupted, safely remain in guest state
    }
  }

  // handshake orchestration, start login pipeline by sending name and role to golang and open telegram app
  Future<void> startTelegramLogin({
    required String name, 
    required String role,
    required VoidCallback onSuccess,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // step 1: hit go backend /init
      final initResult = await _authService.initSession(name: name, role: role);

      // step 2: open telegram app
      final uri = Uri.parse(initResult.telegramUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception("Telegram application is not installed");
      }

      // step 3: start 2-second background polling
      _startPolling(initResult.sessionId, name, onSuccess);

    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll("Exception: ", "");
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
        _errorMessage = "Время ожидания входа истекло / Kirish vaqti tugadi";
        notifyListeners();
      }
    }();
  }

  void _cancelPolling() {
    _isPolling = false;
  }

  // wipe local storage and reset interface back to guest state
  Future<void> logout() async {
    _cancelPolling();
    _isLoading = false;
    _errorMessage = null;
    await _authService.logout();
    _profileState = const ProfileViewState.guest();
    notifyListeners();
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
    super.dispose();
  }
}
