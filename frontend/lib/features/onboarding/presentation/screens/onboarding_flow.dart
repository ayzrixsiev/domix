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
import 'package:frontend/core/widgets/app_form.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import 'package:frontend/features/onboarding/data/privacy_policy.dart';
import 'package:frontend/core/widgets/code_input_field.dart';
import 'package:frontend/features/onboarding/presentation/widgets/step_progress_bar.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/profile/data/account_role.dart';

/// The five screens between opening Domix for the first time and having an account.
///
/// **One widget rather than five routes**: every step reads or writes the same four values, and no
/// step is independently reachable - a code only exists as the tail of a request made on the
/// previous screen.
///
/// **Nothing is persisted until the code verifies** - the account does not exist until then, and the
/// server keeps the pending code in RAM for the same reason - so abandoning the flow leaves nothing
/// behind but the language, which is a device preference.
///
/// **A route over the shell, not a tab inside it**: registering with the nav bar still on screen
/// offers four other places to be while asking for a phone number. The X in the header is the one
/// way out that does not walk back through every step.
/// **One flow for both, because the server has one path.** `/verify` finds the account or creates
/// it - see `upsertUser` - so signing in and registering are the same five steps and the same two
/// requests. There is no shorter door to offer.
enum _Step { language, policy, profile, phone, code }

/// Clear air under the footer's lowest control, over the system inset.
const double _footerGap = 24;

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  /// Opens the flow over whatever is on screen, and answers whether an account came out of it.
  static Future<bool> open(BuildContext context) async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const OnboardingFlow(), fullscreenDialog: true),
    );
    return signedIn ?? false;
  }

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Step _step = _Step.language;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  AccountRole _role = AccountRole.client;

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

  /// The back control: one step, never the whole flow - the X in the header is what abandons it.
  /// Null on the first step, and on [_Step.code] it goes back to the number rather than one step in
  /// the enum - "изменить номер" is the only sensible retreat from a code that went to the wrong
  /// phone.
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

      // **a cooldown is not a refusal, and drawing it as one is what made this a dead end.** The
      // server only answers it while the previous code for this number is still live, so the
      // sms is already in the reader's hands - «Изменить номер» and back onto the same number was
      // being told "слишком много запросов" about a code sitting in their messages. The answer is
      // the code screen with the countdown running, and no second message paid for.
      if (error is AuthApiException && error.code == 'code_cooldown') {
        // the server echoes the canonical spelling only on success; for nine typed digits this is
        // the same string auth.CanonicalPhone would have produced
        _canonicalPhone = '998$digits';
        setState(() => _busy = false);
        _startResendCountdown(error.retryAfter ?? 0);
        _goTo(_Step.code);
        return;
      }

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

    try {
      await context.read<AuthController>().verifyCode(phone: _canonicalPhone, code: code);

      if (!mounted) return;
      // the flow is a route now, so it has to take itself off the screen - the profile it was opened
      // from has already rebuilt into the signed-in one underneath
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
        // the server threw the entry away on these three, so there is nothing left for the digits on
        // screen to match. empty boxes are what «запросите новый код» looks like - leaving them
        // filled invites another tap on «Подтвердить» against a code that no longer exists.
        if (error is AuthApiException && _deadCodeErrors.contains(error.code)) {
          _codeController.clear();
        }
      });
    }
  }

  /// The refusals that mean the pending code is gone rather than mistyped - see CodeManager.Verify.
  static const _deadCodeErrors = {'code_attempts_exhausted', 'code_expired', 'code_not_found'};

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

    final counter = strings.stepCounter(stepIndex + 1, _Step.values.length);

    // no SafeArea around the column: AppPageHeader consumes the status bar itself, which is what
    // lets its surface run up under it instead of leaving a strip of page colour above the title
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: strings.onboardingTitle,
            subtitle: strings.onboardingSubtitle,
            // the left disc is a chevron and this is not a step back - «Назад» in the footer is.
            // the X abandons the whole flow from whichever step it is on.
            showBack: false,
            action: CircleIconButton(
              icon: LucideIcons.x,
              tooltip: strings.closeButton,
              onTap: () => Navigator.of(context).pop(false),
            ),
            // the bar rides on the header's own surface: how far through the flow you are is part of
            // navigating it, not part of the step being filled in
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(_progressExtent),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                // the counter moved down here off the action slot, which the X now holds
                child: Row(
                  children: [
                    Expanded(
                      child: StepProgressBar(
                        currentStep: stepIndex,
                        totalSteps: _Step.values.length,
                        semanticsLabel: counter,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      counter,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
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

  /// The counter's line box, plus the 12 that separates the row from the header's bottom edge.
  static const double _progressExtent = 18 + 12;

  Widget _stepBody(AppLocalizations strings) => switch (_step) {
        _Step.language => _languageStep(strings),
        _Step.policy => _policyStep(strings),
        _Step.profile => _profileStep(strings),
        _Step.phone => _phoneStep(strings),
        _Step.code => _codeStep(strings),
      };

  /// **The error is drawn here and not in the footer**: in the footer it changed the footer's height,
  /// which moved «Далее» up and down between steps.
  ///
  /// [body] is for the two steps that have something to say. The others are the controls alone,
  /// because "выберите язык" above a list of two languages explains nothing the list does not.
  ///
  /// **Centred when it fits, scrolled when it does not**: the minimum height is the viewport's, so
  /// two controls centre themselves instead of hanging off the top edge, and the long step and a
  /// raised keyboard fall back to an ordinary scroll.
  Widget _scrollableStep({String? body, required List<Widget> children}) {
    const padding = EdgeInsets.fromLTRB(20, 20, 20, 8);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - padding.vertical),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                AppErrorLine(_error!),
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
          ),
        ),
      ),
    );
  }

  Widget _languageStep(AppLocalizations strings) {
    final current = context.watch<LanguageProvider>().language;

    return _scrollableStep(
      // the one step that has to say what it is: somebody who opened Профиль expecting an account
      // is looking at two language tiles and no explanation of why
      body: strings.onboardingNoAccount,
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
  /// **The full text is behind «Читать полностью» rather than filling the step**: the law and both
  /// stores require the policy to be *available* before consent, not scrolled past, and nine screens
  /// of legal text teach people to scroll blindly.
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
        AppFieldLabel(strings.nameInputLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: appFieldDecoration(hint: strings.nameInputLabel),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 22),
        AppFieldLabel(strings.registerRolePrompt),
        const SizedBox(height: 8),
        for (final role in AccountRole.values) ...[
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
        AppFieldLabel(strings.phoneInputLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          style: appPhoneTextStyle,
          decoration: appFieldDecoration(hint: '90 123 45 67', prefix: appPhonePrefix),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      ],
    );
  }

  /// The code, and under it the one thing to do when it never arrives.
  ///
  /// **No label over the boxes.** The line above already says a six-digit code went to this number,
  /// and six empty boxes are not something a reader needs told what they are.
  Widget _codeStep(AppLocalizations strings) {
    return _scrollableStep(
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


  /// **Both slots are always drawn**, the back one empty on the first step, and the error lives in the
  /// scrolling content - otherwise the footer is three heights across five steps and «Далее» walks up
  /// and down the screen. The bottom inset is the system's own plus [_footerGap], so the back button
  /// does not sit on the bar the phone draws over it.
  Widget _footer(AppLocalizations strings) {
    final label = switch (_step) {
      _Step.phone => strings.sendCodeButton,
      _Step.code => strings.verifyCodeButton,
      _ => strings.nextButton,
    };
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, systemInset + _footerGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppWideButton(label: label, busy: _busy, onTap: _busy ? null : _onPrimaryAction),
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


