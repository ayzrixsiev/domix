import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/auth_service.dart';
import '../screens/profile_screen.dart';

// Auth Manager that decides when to init handshake, process the incoming data and notify UI components to change their state
class AuthController extends ChangeNotifier {
  final AuthService _authService = AuthService();
  
  Timer? _pollingTimer;
  bool _isLoading = false;
  String? _errorMessage;
  
  // holds current UI state for the ProfileScreen
  ProfileViewState _profileState = const ProfileViewState.guest();

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ProfileViewState get profileState => _profileState;

  // handshake orchestration, start the login pipeline by sending name and role to golang and open telegram app
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

  // ask backend whether login was successfull every 2 seconds 60 times at max
  void _startPolling(String sessionId, String userName, VoidCallback onSuccess) {
    _cancelPolling(); // kill any polling loops before starting new

    int attempts = 0;
    const maxAttempts = 60;

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      if (attempts >= maxAttempts) {
        _cancelPolling();
        _isLoading = false;
        _errorMessage = "Время ожидания входа истекло / Kirish vaqti tugadi";
        notifyListeners();
        return;
      }

      try {
        final result = await _authService.checkStatus(sessionId);

        if (result.isSuccess && result.token != null) {
          _cancelPolling();
          
          // step 4: lock into encrypted hardware storage
          await _authService.saveSession(
            token: result.token!, 
            role: result.role ?? 'customer',
          );

          final displayName = result.name ?? userName;

          // update state to authenticated
          if (result.role == 'shop_owner') {
            _profileState = ProfileViewState.vendor(
              initials: _getInitials(displayName),
              fullName: displayName,
              phoneNumber: result.phone ?? '',
            );
          } else {
            _profileState = ProfileViewState.client(
              initials: _getInitials(displayName),
              fullName: displayName,
              phoneNumber: result.phone ?? '',
            );
          }

          _isLoading = false;
          notifyListeners();
          onSuccess(); // trigger navigation or snackbar
        }
      } catch (_) {
        // silently ignore temporary network blips during polling
      }
    });
  }

  void _cancelPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> logout() async {
    _cancelPolling();
    await _authService.logout();
    _profileState = const ProfileViewState.guest();
    notifyListeners();
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "U";
    final parts = name.trim().split(" ");
    if (parts.length > 1) {
      return "${parts[0][0]}${parts[1][0]}".toUpperCase();
    }
    return name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
  }

  @override
  void dispose() {
    _cancelPolling(); // kill timer if user leaves the screen
    super.dispose();
  }
}