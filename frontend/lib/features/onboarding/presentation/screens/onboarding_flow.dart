import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/role_option_tile.dart';
import 'package:frontend/core/widgets/screen_header.dart';
import 'package:frontend/features/onboarding/data/privacy_policy.dart';
import 'package:frontend/features/onboarding/presentation/widgets/step_progress_bar.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/tickets/data/job_role.dart';
import 'package:frontend/features/tickets/presentation/controllers/tickets_controller.dart';

/// The five screens between opening Domix for the first time and having an account.
///
/// **One widget rather than five routes.** Every step reads or writes the same four values - the
/// language, the accepted policy version, the name and role, the phone - and a route per step means
/// either passing all four forward and back or holding them somewhere above the routes anyway. The
/// steps are also not independently reachable: there is no deep link to "enter your code", because
/// a code only exists as the tail of a request made on the previous screen.
///
/// **Nothing is persisted until the code verifies.** The account does not exist until then - the
/// server keeps the pending code in RAM for the same reason - so abandoning this flow at any step
/// leaves nothing behind but the language, which is a device preference rather than an account.
enum _Step { language, policy, profile, phone, code }

/// Clear air between the footer's lowest control and the top of the shell's floating nav bar.
const double _footerGap = 30;

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, this.bottomPadding = 36});

  /// Room under the footer for the shell's floating nav bar.
  final double bottomPadding;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Step _step = _Step.language;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  JobRole _role = JobRole.client;

  bool _policyAccepted = false;

  /// The server's canonical spelling of the number, from `/request-code`. **`/verify` is called
  /// with this and never with what was typed** - the two only agree by luck.
  String _canonicalPhone = '';

  /// Seconds left before another code may be requested; 0 means the control is live.
  int _resendIn = 0;
  Timer? _resendTimer;

  /// Already localized, because the thing that produced it knew the error code and this does not.
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  AppLocalizations get _strings => context.read<LanguageProvider>().strings;

  // ------------------------------------------------------------------------------------------
  // moving between steps
  // ------------------------------------------------------------------------------------------

  void _goTo(_Step step) {
    setState(() {
      _step = step;
      _error = null;
    });
  }

  /// The back control. Null on the first step, and on [_Step.code] it goes back to the number
  /// rather than one step in the enum - "изменить номер" is the only sensible retreat from a code
  /// that went to the wrong phone.
  VoidCallback? get _onBack => switch (_step) {
        _Step.language => null,
        _Step.policy => () => _goTo(_Step.language),
        _Step.profile => () => _goTo(_Step.policy),
        _Step.phone => () => _goTo(_Step.profile),
        _Step.code => _changePhone,
      };

  void _changePhone() {
    _resendTimer?.cancel();
    _codeController.clear();
    setState(() => _resendIn = 0);
    _goTo(_Step.phone);
  }

  void _onPrimaryAction() {
    switch (_step) {
      case _Step.language:
        _goTo(_Step.policy);
      case _Step.policy:
        if (!_policyAccepted) {
          setState(() => _error = _strings.policyMustAccept);
          return;
        }
        _goTo(_Step.profile);
      case _Step.profile:
        if (_nameController.text.trim().isEmpty) {
          setState(() => _error = _strings.nameRequiredError);
          return;
        }
        _goTo(_Step.phone);
      case _Step.phone:
        _requestCode();
      case _Step.code:
        _verifyCode();
    }
  }

  // ------------------------------------------------------------------------------------------
  // the two network steps
  // ------------------------------------------------------------------------------------------

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
    });

    try {
      final result = await context.read<AuthController>().requestCode(
            phone: '998$digits',
            name: _nameController.text.trim(),
            role: _role.code,
          );
      if (!mounted) return;
      _canonicalPhone = result.phone;
      _startResendCountdown(result.resendAfter);
      setState(() => _busy = false);
      _goTo(_Step.code);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
        // a refusal that is about waiting carries how long, and the countdown is more use than
        // the sentence on its own
        if (error is AuthApiException && error.retryAfter != null) {
          _startResendCountdown(error.retryAfter!);
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

    // read before the await: a successful verify rebuilds the tree out from under this widget, and
    // a Provider lookup on a deactivated context asserts
    final ticketsController = context.read<TicketsController>();

    try {
      await context.read<AuthController>().verifyCode(phone: _canonicalPhone, code: code);

      // **the role is remembered on the phone, not only sent to the server.** the backend has no
      // worker role - it maps everything that is not shop_owner down to customer - so this is what
      // keeps a worker a worker when `/api/me` answers "customer" on the next foreground.
      ticketsController.setRole(_role);

      // nothing else to do: AuthController has flipped out of the guest state, so the screen that
      // hosts this flow has already rebuilt into the signed-in profile underneath us
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _resendCode() async {
    if (_resendIn > 0 || _busy) return;
    _codeController.clear();
    await _requestCode();
    // _requestCode moves to the code step, which is where we already are - harmless, and it keeps
    // the countdown and error handling in exactly one place
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

  /// **Written copy, never the exception.** A refusal carries a code the strings file turns into a
  /// sentence; anything else - a dead socket, a proxy's HTML - is the generic failure, because what
  /// a reader can do about it is the same either way.
  String _messageFor(Object error) => error is AuthApiException
      ? _strings.authErrorFor(error.code)
      : _strings.authGenericError;

  // ------------------------------------------------------------------------------------------
  // build
  // ------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // the one subscription: every `_strings` below reads without listening, and half of them are
    // inside callbacks, so without this the flow would stay in the old language after step one
    final strings = context.watch<LanguageProvider>().strings;
    final stepIndex = _Step.values.indexOf(_step);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: strings.onboardingTitle,
            subtitle: strings.onboardingSubtitle,
            // no rule: the progress bar immediately below is already a horizontal line, and two of
            // them stacked read as a mistake
            showRule: false,
            trailing: Text(
              strings.stepCounter(stepIndex + 1, _Step.values.length),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: StepProgressBar(
              currentStep: stepIndex,
              totalSteps: _Step.values.length,
              semanticsLabel: strings.stepCounter(stepIndex + 1, _Step.values.length),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.base,
              switchInCurve: AppMotion.easing,
              // keyed on the step, or the switcher sees one child of the same type throughout and
              // never transitions
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _stepBody(strings),
              ),
            ),
          ),
          _footer(strings),
        ],
      ),
    );
  }

  Widget _stepBody(AppLocalizations strings) => switch (_step) {
        _Step.language => _languageStep(strings),
        _Step.policy => _policyStep(strings),
        _Step.profile => _profileStep(strings),
        _Step.phone => _phoneStep(strings),
        _Step.code => _codeStep(strings),
      };

  /// Every step but the policy is a short form on a scrollable page - short today, and one line of
  /// help text away from not being short on a 4-inch phone with the keyboard up.
  ///
  /// **The error is drawn here and not in the footer.** In the footer it changed the footer's
  /// height, which moved «Далее» up and down between steps; here it pushes content that was already
  /// scrollable and the buttons do not move at all.
  ///
  /// [body] is for the one step that has something to say - which number the code went to. The
  /// others are a title and the controls, because "выберите язык" above a list of two languages
  /// explains nothing that the list does not.
  Widget _scrollableStep({String? body, required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      physics: const BouncingScrollPhysics(),
      children: [
        if (_error != null) ...[
          _ErrorLine(_error!),
          const SizedBox(height: 16),
        ],
        if (body != null) ...[
          Text(
            body,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 18),
        ],
        ...children,
      ],
    );
  }

  Widget _languageStep(AppLocalizations strings) {
    final current = context.watch<LanguageProvider>().language;

    return _scrollableStep(
      children: [
        for (final language in AppLanguage.values) ...[
          RoleOptionTile(
            icon: LucideIcons.languages,
            title: language.displayName,
            // named in the language being offered, so somebody who cannot read the current one can
            // still find theirs
            subtitle: language == AppLanguage.ru ? 'Русский язык' : "O'zbek tili",
            isSelected: language == current,
            onTap: () => context.read<LanguageProvider>().updateLanguage(language),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// The policy step: the document's name, the one-paragraph summary, a way in to the full text,
  /// and the tick.
  ///
  /// **The full text is behind «Читать полностью» rather than filling the step**, and almost nobody
  /// will open it. That is the honest design: what the law and both stores require is that the
  /// policy be *available* before consent, not that a wall of it be scrolled past - and a step that
  /// is nine screens of legal text teaches people to scroll blindly, which is worse than a summary
  /// they actually read plus a door to the rest.
  Widget _policyStep(AppLocalizations strings) {
    final language = context.watch<LanguageProvider>().language;

    return _scrollableStep(
      children: [
        Text(
          strings.onboardingPolicyTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 19,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          strings.policyRevision(policyVersion),
          style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              privacyPolicyLead(language),
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showPolicySheet(strings, language),
            icon: const Icon(LucideIcons.book_open, size: 16, color: AppColors.primaryOrange),
            label: Text(
              strings.policyReadFull,
              style: const TextStyle(
                color: AppColors.primaryOrange,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _ConsentCheckbox(
          label: strings.policyAcceptLabel,
          value: _policyAccepted,
          onChanged: (value) => setState(() {
            _policyAccepted = value;
            if (value) _error = null;
          }),
        ),
      ],
    );
  }

  /// The whole policy, in a sheet that opens to most of the screen and scrolls.
  ///
  /// A sheet rather than a pushed route: this is a thing to glance into and dismiss, and a route
  /// would take the progress bar off screen and make the reader feel they had left the flow.
  void _showPolicySheet(AppLocalizations strings, AppLanguage language) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: AppColors.trackGrey,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: ListView(
                // the sheet's own controller, or the drag-to-resize gesture and the list's scroll
                // fight each other and the sheet jumps
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  Text(
                    strings.onboardingPolicyTitle,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 19,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.policyRevision(policyVersion),
                    style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  for (final section in privacyPolicySections(language)) ...[
                    Text(
                      section.title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final paragraph in section.body) ...[
                      Text(
                        paragraph,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileStep(AppLocalizations strings) {
    return _scrollableStep(
      children: [
        _FieldLabel(strings.nameInputLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: _fieldDecoration(hint: strings.nameInputLabel),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 22),
        _FieldLabel(strings.registerRolePrompt),
        const SizedBox(height: 8),
        for (final role in JobRole.values) ...[
          RoleOptionTile(
            icon: role.icon,
            title: role.label(strings),
            subtitle: role.subtitle(strings),
            isSelected: role == _role,
            onTap: () => setState(() => _role = role),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _phoneStep(AppLocalizations strings) {
    return _scrollableStep(
      children: [
        _FieldLabel(strings.phoneInputLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
          decoration: _fieldDecoration(hint: '90 123 45 67').copyWith(
            // a fixed country code rather than a picker: Domix is one country, and a picker is a
            // way to send a code to a number no Uzbek operator will deliver
            prefixIcon: const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 8, 0),
              child: Text(
                '+998',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      ],
    );
  }

  Widget _codeStep(AppLocalizations strings) {
    return _scrollableStep(
      body: strings.codeSentTo(_displayPhone),
      children: [
        _FieldLabel(strings.codeInputLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofocus: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 10,
          ),
          decoration: _fieldDecoration(hint: '– – – – – –'),
          onChanged: (value) {
            if (_error != null) setState(() => _error = null);
            // six digits is the whole code, so there is nothing to press "done" for
            if (value.length == 6 && !_busy) _verifyCode();
          },
        ),
        const SizedBox(height: 18),
        Center(
          child: _resendIn > 0
              ? Text(
                  strings.resendCodeIn(_resendIn),
                  style: const TextStyle(color: AppColors.textFaint, fontSize: 13),
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

  /// `998901234567` as `+998 90 123 45 67`. Grouped rather than raw: a twelve-digit run is not
  /// something a reader can check their own number against at a glance.
  String get _displayPhone {
    final digits = _canonicalPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 12) return _canonicalPhone;
    return '+${digits.substring(0, 3)} ${digits.substring(3, 5)} '
        '${digits.substring(5, 8)} ${digits.substring(8, 10)} ${digits.substring(10)}';
  }

  /// The two controls, at the same height on every step.
  ///
  /// **Both slots are always drawn**, the back one empty on the first step, and the error moved out
  /// of here into the scrolling content - otherwise the footer was three different heights across
  /// five steps and «Далее» walked up and down the screen as you advanced.
  ///
  /// The bottom inset is the shell's floating nav bar, *plus the system inset under it*, *plus a
  /// gap*. The bar pads itself by the home-indicator height, so on a gesture-navigation phone its
  /// top edge sits higher than the padding the shell hands down and the buttons were behind it -
  /// and clearing it by a hair still looked wrong, because the back button then sat in the 12px
  /// crack between the two. [_footerGap] is what lifts the pair clear of the bar entirely.
  Widget _footer(AppLocalizations strings) {
    final label = switch (_step) {
      _Step.phone => strings.sendCodeButton,
      _Step.code => strings.verifyCodeButton,
      _ => strings.nextButton,
    };
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, widget.bottomPadding + systemInset + _footerGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _WizardButton(label: label, busy: _busy, onTap: _busy ? null : _onPrimaryAction),
          // the two were touching: a TextButton's own padding is the only thing that was between
          // them, which read as one control with a caption stuck under it
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: _onBack == null
                ? null
                : TextButton(
                    onPressed: _busy ? null : _onBack,
                    child: Text(
                      _step == _Step.code ? strings.changePhoneButton : strings.stepBackButton,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration({required String hint}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: color),
      );

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textFaint, fontWeight: FontWeight.w500),
    filled: true,
    fillColor: AppColors.surfaceMuted,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(AppColors.hairline),
    enabledBorder: border(AppColors.hairline),
    focusedBorder: border(AppColors.primaryOrange),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textDark,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// The consent tick. A whole tappable row rather than a bare `Checkbox`, because a 20px box is
/// below every touch-target guideline there is and this is the one control that has to be
/// deliberate.
class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                height: 22,
                width: 22,
                decoration: BoxDecoration(
                  color: value ? AppColors.primaryOrange : AppColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: value ? AppColors.primaryOrange : AppColors.trackGrey,
                    width: 1.5,
                  ),
                ),
                child: value
                    ? const Icon(LucideIcons.check, size: 15, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The step's refusal, in danger colours on a tinted strip. Not a SnackBar: it answers the button
/// directly above it and has to stay on screen while the user fixes the field.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(LucideIcons.circle_alert, size: 16, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The footer's primary button: full width, and it holds its own spinner.
///
/// Full width rather than [PrimaryActionButton], which sizes to its label - a wizard's "Далее" is
/// the one thing on the step that is always in the same place, and a button that changes width with
/// its caption moves under the thumb between steps.
class _WizardButton extends StatelessWidget {
  const _WizardButton({required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final radius = BorderRadius.circular(AppRadius.sm);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: enabled ? AppShadows.accent(AppColors.primaryOrange) : null,
      ),
      child: Material(
        color: enabled ? AppColors.primaryOrange : AppColors.trackGrey,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Center(
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: enabled ? Colors.white : AppColors.textFaint,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
