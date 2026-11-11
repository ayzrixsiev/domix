import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/role_option_tile.dart';
import 'package:frontend/core/widgets/app_form.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import 'package:frontend/features/onboarding/data/privacy_policy.dart';
import 'package:frontend/features/onboarding/presentation/screens/phone_sign_in_flow.dart';
import 'package:frontend/features/onboarding/presentation/widgets/flow_layout.dart';
import 'package:frontend/features/onboarding/presentation/widgets/step_progress_bar.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/profile/data/account_role.dart';

/// The four screens between opening Domix for the first time and having an account.
///
/// **One widget rather than four routes**: every step reads or writes the same values, and no step is
/// independently reachable - the last one only exists as the tail of the name and role before it.
///
/// **Nothing is persisted until telegram hands the number over** - the account does not exist until
/// then, and the server keeps the session in RAM for the same reason - so abandoning the flow leaves
/// nothing behind but the language, which is a device preference.
///
/// **A route over the shell, not a tab inside it**: registering with the nav bar still on screen
/// offers four other places to be while asking for a phone number. The X in the header is the one
/// way out that does not walk back through every step.
///
/// **One flow for both, because the server has one path.** The bot's number is found or created -
/// see `upsertUser` - so signing in and registering are the same four steps and the same button.
///
/// **The phone route is a door off the last step, never a step**: it would tell every telegram user
/// they are on step four of six. It is what the Play reviewer signs in through.
enum _Step { language, policy, profile, telegram }

/// How often the session is asked whether telegram has answered.
const Duration _pollEvery = Duration(seconds: 2);

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  /// Opens the flow over whatever is on screen, and answers whether an account came out of it.
  static Future<bool> open(BuildContext context) async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const OnboardingFlow(),
        fullscreenDialog: true,
      ),
    );
    return signedIn ?? false;
  }

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow>
    with WidgetsBindingObserver {
  _Step _step = _Step.language;

  final _nameController = TextEditingController();

  AccountRole _role = AccountRole.client;

  bool _policyAccepted = false;

  /// The session being waited on, null until «Зарегистрироваться через Telegram» is pressed.
  TelegramHandshake? _handshake;
  DateTime _deadline = DateTime.now();
  Timer? _pollTimer;
  bool _polling = false;

  /// Already localized, because the thing that produced it knew the error code and this does not.
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  /// **The reader is in telegram while this waits, so the app is in the background**, where Android
  /// may hold its timers back. Coming to the front asks at once instead of on the next tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_poll());
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
  /// Null on the first step; while the bot is being waited on it cancels the wait instead, since the
  /// name behind it is already riding in that session.
  VoidCallback? get _onBack => switch (_step) {
    _Step.language => null,
    _Step.policy => () => _goTo(_Step.language),
    _Step.profile => () => _goTo(_Step.policy),
    _Step.telegram when _handshake != null => _cancelHandshake,
    _Step.telegram => () => _goTo(_Step.profile),
  };

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
        _goTo(_Step.telegram);
      case _Step.telegram:
        // no footer button here: the step draws its two ways in itself
        break;
    }
  }

  // ------------------------------------------------------------------------------------------
  // the handshake: a session, the bot, and a poll until it answers
  // ------------------------------------------------------------------------------------------

  Future<void> _startHandshake() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final handshake = await context
          .read<AuthController>()
          .startTelegramSignIn(
            name: _nameController.text.trim(),
            role: _role.code,
            lang: context.read<LanguageProvider>().language.code,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _handshake = handshake;
        _deadline = DateTime.now().add(Duration(seconds: handshake.expiresIn));
      });
      _pollTimer = Timer.periodic(_pollEvery, (_) => _poll());
      await _openTelegram();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
  }

  /// **The return value of launchUrl is the signal, not canLaunchUrl** - see the `<queries>` block
  /// in the manifest for why the second one lies on Android 11+.
  Future<void> _openTelegram() async {
    final handshake = _handshake;
    if (handshake == null) return;

    var opened = false;
    try {
      opened = await launchUrl(
        handshake.link,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() => _error = _strings.authTelegramNotOpened);
    }
  }

  Future<void> _poll() async {
    final handshake = _handshake;
    if (handshake == null || _polling) return;
    if (DateTime.now().isAfter(_deadline)) {
      _endHandshake(_strings.authSessionExpired);
      return;
    }

    _polling = true;
    try {
      final status = await context.read<AuthController>().pollTelegramSignIn(
        handshake.session,
      );
      if (!mounted) return;

      // **a success closes the flow even if the wait was cancelled meanwhile**: the account is already
      // signed in on this phone by then, and a flow left open over it would be asking to sign in again
      if (status == HandshakePoll.success) {
        _pollTimer?.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      if (status == HandshakePoll.pending || _handshake != handshake) return;
      _endHandshake(_strings.authErrorFor(status));
    } catch (_) {
      // a dropped poll says nothing about the sign-in: the next tick asks again
    } finally {
      _polling = false;
    }
  }

  void _endHandshake(String? error) {
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() {
      _handshake = null;
      _error = error;
    });
  }

  void _cancelHandshake() => _endHandshake(null);

  /// The name and role ride into the code request as they ride into a telegram session.
  Future<void> _openPhoneSignIn() async {
    final signedIn = await PhoneSignInFlow.open(
      context,
      name: _nameController.text.trim(),
      role: _role.code,
    );
    if (signedIn && mounted) Navigator.of(context).pop(true);
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
    _Step.telegram => _telegramStep(strings),
  };

  Widget _languageStep(AppLocalizations strings) {
    final current = context.watch<LanguageProvider>().language;

    return FlowStepBody(
      error: _error,
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
            subtitle: language == AppLanguage.ru
                ? 'Русский язык'
                : "O'zbek tili",
            isSelected: language == current,
            onTap: () =>
                context.read<LanguageProvider>().updateLanguage(language),
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

    return FlowStepBody(
      error: _error,
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
            icon: const Icon(
              LucideIcons.book_open,
              size: 16,
              color: AppColors.primaryOrange,
            ),
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
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 12,
                    ),
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
    return FlowStepBody(
      error: _error,
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

  /// What the buttons are about to do, and once one is pressed, what is being waited for.
  ///
  /// **The two ways in are one choice, so they are drawn as one**: the same button, the same width,
  /// stacked in the middle of the step with Telegram first. The phone route is a door off this step
  /// rather than a step, so the counter stays at four for everybody who never opens it.
  Widget _telegramStep(AppLocalizations strings) {
    if (_handshake == null) {
      return FlowStepBody(
        error: _error,
        children: [
          AppWideButton(
            label: strings.telegramSignInButton,
            busy: _busy,
            onTap: _busy ? null : _startHandshake,
          ),
          const SizedBox(height: 12),
          AppWideButton(
            label: strings.phoneSignInButton,
            onTap: _busy ? null : _openPhoneSignIn,
          ),
        ],
      );
    }

    return FlowStepBody(
      error: _error,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.primaryOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                strings.telegramWaitingTitle,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          strings.telegramWaitingBody,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        AppWideButton(
          label: strings.telegramReopenButton,
          onTap: _openTelegram,
        ),
      ],
    );
  }

  /// The telegram step's actions are in its content, so its footer is the back row alone.
  Widget _footer(AppLocalizations strings) {
    final onTelegram = _step == _Step.telegram;

    return FlowFooter(
      label: onTelegram ? null : strings.nextButton,
      busy: _busy,
      onPrimary: _onPrimaryAction,
      onBack: _onBack,
      backLabel: onTelegram && _handshake != null
          ? strings.cancelButton
          : strings.stepBackButton,
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
                  color: value
                      ? AppColors.primaryOrange
                      : AppColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: value
                        ? AppColors.primaryOrange
                        : AppColors.trackGrey,
                    width: 1.5,
                  ),
                ),
                child: value
                    ? const Icon(
                        LucideIcons.check,
                        size: 15,
                        color: Colors.white,
                      )
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
