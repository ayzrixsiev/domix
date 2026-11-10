import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/app_form.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import 'package:frontend/core/widgets/code_input_field.dart';
import 'package:frontend/features/onboarding/presentation/widgets/flow_layout.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';

/// «Войти по номеру телефона»: a number, then the code sent to it. Opened from the onboarding's last
/// step with the name and role already collected there, and answers whether an account came out.
///
/// **Until Gateway is paid for the server sends nothing**, and every number but the Play review
/// account is answered `sms_unavailable`, drawn as a note pointing back to Telegram. Paying for it
/// is the whole switch-over: this screen does not change.
class PhoneSignInFlow extends StatefulWidget {
  const PhoneSignInFlow({super.key, required this.name, required this.role});

  final String name;

  /// The server's spelling, `customer` or `shop_owner`.
  final String role;

  static Future<bool> open(
    BuildContext context, {
    required String name,
    required String role,
  }) async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PhoneSignInFlow(name: name, role: role),
        fullscreenDialog: true,
      ),
    );
    return signedIn ?? false;
  }

  @override
  State<PhoneSignInFlow> createState() => _PhoneSignInFlowState();
}

enum _Step { phone, code }

class _PhoneSignInFlowState extends State<PhoneSignInFlow> {
  _Step _step = _Step.phone;

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  /// The server's canonical spelling of the number, from `/request-code`. **`/verify` is called
  /// with this and never with what was typed** - the two only agree by luck.
  String _canonicalPhone = '';

  /// Seconds left before another code may be requested; 0 means the control is live.
  int _resendIn = 0;
  Timer? _resendTimer;

  String? _error;
  bool _smsUnavailable = false;
  bool _busy = false;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  AppLocalizations get _strings => context.read<LanguageProvider>().strings;

  /// One step back: from the code to the number, from the number to the telegram step.
  void _onBack() {
    if (_step == _Step.phone) {
      Navigator.of(context).pop(false);
      return;
    }
    _resendTimer?.cancel();
    _codeController.clear();
    setState(() {
      _resendIn = 0;
      _step = _Step.phone;
      _error = null;
    });
  }

  Future<void> _requestCode() async {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    // nine digits is the whole national number; the 998 is drawn as a prefix and never typed
    if (digits.length != 9) {
      setState(() => _error = _strings.phoneInvalidError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _smsUnavailable = false;
    });

    try {
      final result = await context.read<AuthController>().requestCode(
        phone: '998$digits',
        name: widget.name,
        role: widget.role,
      );
      if (!mounted) return;
      _canonicalPhone = result.phone;
      _startResendCountdown(result.resendAfter);
      setState(() {
        _busy = false;
        _step = _Step.code;
      });
    } catch (error) {
      if (!mounted) return;

      // **a cooldown is not a refusal**: the server only answers it while the previous code for this
      // number is still live, so the code is already in the reader's hands. The answer is the code
      // screen with the countdown running, and no second message paid for.
      if (error is AuthApiException && error.code == 'code_cooldown') {
        // the server echoes the canonical spelling only on success; for nine typed digits this is
        // the same string auth.CanonicalPhone would have produced
        _canonicalPhone = '998$digits';
        _startResendCountdown(error.retryAfter ?? 0);
        setState(() {
          _busy = false;
          _step = _Step.code;
        });
        return;
      }

      setState(() {
        _busy = false;
        if (error is AuthApiException && error.code == 'sms_unavailable') {
          _smsUnavailable = true;
          _step = _Step.phone;
        } else {
          _error = _messageFor(error);
        }
      });
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = _strings.authCodeWrong);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await context.read<AuthController>().verifyCode(
        phone: _canonicalPhone,
        code: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
        // the server threw the entry away on these, so nothing is left for the digits on screen to
        // match: empty boxes are what «запросите новый код» looks like
        if (error is AuthApiException && _deadCodeErrors.contains(error.code)) {
          _codeController.clear();
        }
      });
    }
  }

  /// The refusals that mean the pending code is gone rather than mistyped - see CodeManager.Verify.
  static const _deadCodeErrors = {
    'code_attempts_exhausted',
    'code_expired',
    'code_not_found',
  };

  Future<void> _resendCode() async {
    if (_resendIn > 0 || _busy) return;
    _codeController.clear();
    await _requestCode();
  }

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    if (seconds <= 0) return;

    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendIn--;
        if (_resendIn <= 0) timer.cancel();
      });
    });
  }

  String _messageFor(Object error) => error is AuthApiException
      ? _strings.authErrorFor(error.code)
      : _strings.authGenericError;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LanguageProvider>().strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: strings.phoneSignInTitle,
            showBack: false,
            action: CircleIconButton(
              icon: LucideIcons.x,
              tooltip: strings.closeButton,
              onTap: () => Navigator.of(context).pop(false),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.base,
              switchInCurve: AppMotion.easing,
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _step == _Step.phone
                    ? _phoneStep(strings)
                    : _codeStep(strings),
              ),
            ),
          ),
          FlowFooter(
            label: _step == _Step.phone
                ? strings.sendCodeButton
                : strings.verifyCodeButton,
            busy: _busy,
            onPrimary: _step == _Step.phone ? _requestCode : _verifyCode,
            onBack: _onBack,
            backLabel: _step == _Step.code
                ? strings.changePhoneButton
                : strings.stepBackButton,
          ),
        ],
      ),
    );
  }

  Widget _phoneStep(AppLocalizations strings) {
    return FlowStepBody(
      error: _error,
      children: [
        AppFieldLabel(strings.phoneInputLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          autofocus: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          style: appPhoneTextStyle,
          decoration: appFieldDecoration(
            hint: '90 123 45 67',
            prefix: appPhonePrefix,
          ),
          onChanged: (_) {
            if (_error != null || _smsUnavailable) {
              setState(() {
                _error = null;
                _smsUnavailable = false;
              });
            }
          },
        ),
        if (_smsUnavailable) ...[
          const SizedBox(height: 12),
          AppNoteLine(strings.smsUnavailable, icon: LucideIcons.info),
        ],
      ],
    );
  }

  /// **No label over the boxes**: the line above already says a six-digit code went to this number.
  Widget _codeStep(AppLocalizations strings) {
    return FlowStepBody(
      error: _error,
      body: strings.codeSentTo(formatUzPhone(_canonicalPhone)),
      children: [
        CodeInputField(
          controller: _codeController,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 18),
        Center(
          child: _resendIn > 0
              ? Text(
                  strings.resendCodeIn(_resendIn),
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 13,
                  ),
                )
              : TextButton(
                  onPressed: _busy ? null : _resendCode,
                  child: Text(
                    strings.resendCodeButton,
                    style: const TextStyle(
                      color: AppColors.primaryOrange,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
