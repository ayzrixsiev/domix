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
import 'package:frontend/core/widgets/destructive_confirm_dialog.dart';
import 'package:frontend/core/widgets/role_option_tile.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'package:frontend/features/profile/data/account_role.dart';
import '../controllers/auth_controller.dart';

/// Editing an account that already exists: the display name and the role on one form, the phone
/// number behind a code sent to the number being claimed.
///
/// **The number is not a field on the form, and that is the design**: the phone is the account's
/// identity, so moving it needs the new number proven - a paid message and two round trips. Bundling
/// it into «Сохранить» would mean one button that sometimes sends an sms.
///
/// **A full-screen route with an X, like the registration flow.** Nothing auto-submits: the X abandons
/// whatever step is open and «Назад» walks one step back.
enum _Step { form, phone, code }

/// Clear air under the footer's lowest control, over the system inset.
const double _footerGap = 24;

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  /// Opens the editor over whatever is on screen. Answers what changed, so the profile behind it
  /// can say so - null when the screen was abandoned.
  static Future<ProfileEditOutcome?> open(BuildContext context) {
    return Navigator.of(context).push<ProfileEditOutcome>(
      MaterialPageRoute(
        builder: (_) => const ProfileEditScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

/// What the editor did, for the sentence the profile shows afterwards. Two cases rather than a
/// bool: "номер изменён" is the more surprising of the two and deserves its own line.
enum ProfileEditOutcome { profileSaved, phoneChanged }

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  _Step _step = _Step.form;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  /// The role as it will be saved. Seeded from the account and only movable while
  /// [AccountRole.canStillChange] - see [_roleSection].
  late AccountRole _role;

  /// The server's canonical spelling of the new number, from `/request-code`. **`/verify` is called
  /// with this and never with what was typed** - the two only agree by luck.
  String _canonicalPhone = '';

  int _resendIn = 0;
  Timer? _resendTimer;

  /// Already localized, because the thing that produced it knew the error code and this does not.
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();

    final profile = context.read<AuthController>().profileState;
    _nameController.text = profile.fullName;
    _role = AccountRole.of(isVendor: profile.isVendor);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  AppLocalizations get _strings => context.read<LanguageProvider>().strings;

  /// The role the account arrived with - what a change is measured against, and what decides
  /// whether the picker is drawn at all.
  AccountRole get _originalRole => AccountRole.of(
    isVendor: context.read<AuthController>().profileState.isVendor,
  );

  // ------------------------------------------------------------------------------------------
  // moving between steps
  // ------------------------------------------------------------------------------------------

  void _goTo(_Step step) {
    setState(() {
      _step = step;
      _error = null;
    });
  }

  /// One step back, never the whole screen - the X in the header is what abandons it. Null on the
  /// form, which has nowhere behind it.
  VoidCallback? get _onBack => switch (_step) {
    _Step.form => null,
    _Step.phone => () => _goTo(_Step.form),
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
      case _Step.form:
        _save();
      case _Step.phone:
        _requestCode();
      case _Step.code:
        _verifyCode();
    }
  }

  // ------------------------------------------------------------------------------------------
  // saving the name and the role
  // ------------------------------------------------------------------------------------------

  /// **One request, and only when something actually changed.** A «Сохранить» on an untouched form
  /// is a round trip that can fail, for a write with nothing in it.
  Future<void> _save() async {
    final strings = _strings;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = strings.nameRequiredError);
      return;
    }

    final controller = context.read<AuthController>();
    final originalRole = _originalRole;

    final nameChanged = name != controller.profileState.fullName;
    final roleChanged = _role != originalRole;

    if (!nameChanged && !roleChanged) {
      Navigator.of(context).pop();
      return;
    }

    // asked once, before anything is written: this is the only choice on the screen that cannot be
    // taken back
    if (roleChanged) {
      final confirmed = await DestructiveConfirmDialog.show(
        context,
        title: strings.roleChangeConfirmTitle,
        body: strings.roleChangeConfirmBody(_role.label(strings)),
        confirmLabel: strings.roleChangeConfirmAction,
        cancelLabel: strings.cancelButton,
        icon: LucideIcons.shield_alert,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await controller.updateProfile(
        name: nameChanged ? name : null,
        role: roleChanged ? _role.code : null,
      );

      if (!mounted) return;
      Navigator.of(context).pop(ProfileEditOutcome.profileSaved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
  }

  // ------------------------------------------------------------------------------------------
  // the two network steps of the phone change
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
      final result = await context
          .read<AuthController>()
          .requestPhoneChangeCode('998$digits');
      if (!mounted) return;
      _canonicalPhone = result.phone;
      _startResendCountdown(result.resendAfter);
      setState(() => _busy = false);
      _goTo(_Step.code);
    } catch (error) {
      if (!mounted) return;

      // a cooldown is not a refusal - the code it is protecting is still live and sitting in the
      // reader's messages, so the answer is the code screen with the countdown running rather than
      // a second message paid for. Same reasoning as OnboardingFlow.
      if (error is AuthApiException && error.code == 'code_cooldown') {
        _canonicalPhone = '998$digits';
        setState(() => _busy = false);
        _startResendCountdown(error.retryAfter ?? 0);
        _goTo(_Step.code);
        return;
      }

      setState(() {
        _busy = false;
        _error = _messageFor(error);
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
      await context.read<AuthController>().verifyPhoneChange(
        phone: _canonicalPhone,
        code: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(ProfileEditOutcome.phoneChanged);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
        // the server threw the entry away on these three, so there is nothing left for the digits on
        // screen to match - empty boxes are what «запросите новый код» looks like
        if (error is AuthApiException && _deadCodeErrors.contains(error.code)) {
          _codeController.clear();
        }
      });
    }
  }

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

  /// **Written copy, never the exception.** A refusal carries a code the strings file turns into a
  /// sentence; anything else - a dead socket, a proxy's HTML - is the generic failure, because what
  /// a reader can do about it is the same either way.
  String _messageFor(Object error) => error is AuthApiException
      ? _strings.profileErrorFor(error.code)
      : _strings.authGenericError;

  // ------------------------------------------------------------------------------------------
  // build
  // ------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // the one subscription: every `_strings` below reads without listening, and half of them are
    // inside callbacks
    final strings = context.watch<LanguageProvider>().strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: strings.editProfileTitle,
            subtitle: _step == _Step.form
                ? strings.editProfileSubtitle
                : strings.changePhoneButton,
            // the X abandons the whole screen from whichever step it is on; «Назад» in the footer
            // is what walks one step
            showBack: false,
            action: CircleIconButton(
              icon: LucideIcons.x,
              tooltip: strings.closeButton,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.base,
              switchInCurve: AppMotion.easing,
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
    _Step.form => _formStep(strings),
    _Step.phone => _phoneStep(strings),
    _Step.code => _codeStep(strings),
  };

  /// The step's controls on a scrollable page, with the refusal above them.
  ///
  /// **The error is drawn here and not in the footer**, so it pushes content that was already
  /// scrollable instead of changing the footer's height and walking «Сохранить» up the screen.
  Widget _scrollableStep({String? body, required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            AppErrorLine(_error!),
            const SizedBox(height: 16),
          ],
          if (body != null) ...[
            Text(
              body,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget _formStep(AppLocalizations strings) {
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
        AppFieldLabel(strings.currentPhoneLabel),
        const SizedBox(height: 8),
        _phoneRow(strings),
        const SizedBox(height: 22),
        AppFieldLabel(strings.registerRolePrompt),
        const SizedBox(height: 8),
        ..._roleSection(strings),
      ],
    );
  }

  /// The number as it stands, and the way into changing it. A row rather than a field: there is
  /// nothing to type here, and a text field holding a value that cannot be edited in place is an
  /// invitation to try.
  Widget _phoneRow(AppLocalizations strings) {
    final phone = context.watch<AuthController>().profileState.phoneNumber;

    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => _goTo(_Step.phone),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.phone,
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(formatUzPhone(phone), style: appPhoneTextStyle),
              ),
              Text(
                strings.editProfileButton,
                style: const TextStyle(
                  color: AppColors.primaryOrange,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                LucideIcons.chevron_right,
                size: 16,
                color: AppColors.primaryOrange,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The picker while the role can still move, and a locked statement of it once it cannot.
  ///
  /// **A customer may become a worker or a shop owner, and nobody goes back.** The server refuses
  /// the reverse as well (PATCH /api/me answers `role_locked`), so this is the explanation rather
  /// than the enforcement - a rule guarded only by a hidden control is not guarded.
  List<Widget> _roleSection(AppLocalizations strings) {
    if (!_originalRole.canStillChange) {
      return [
        RoleOptionTile(
          icon: _originalRole.icon,
          title: _originalRole.label(strings),
          subtitle: _originalRole.subtitle(strings),
          // neither selected nor tappable: this is a statement of what the account is
          isSelected: true,
          onTap: () {},
        ),
        const SizedBox(height: 10),
        _Note(strings.roleLockedNote, icon: LucideIcons.lock),
      ];
    }

    return [
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
      _Note(strings.roleChangeWarning, icon: LucideIcons.triangle_alert),
    ];
  }

  Widget _phoneStep(AppLocalizations strings) {
    return _scrollableStep(
      body: strings.phoneChangeExplainer,
      children: [
        AppFieldLabel(strings.newPhoneLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofocus: true,
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
            if (_error != null) setState(() => _error = null);
          },
        ),
      ],
    );
  }

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

  /// The two controls, at the same height on every step - the back slot is drawn empty on the form
  /// rather than removed, so «Сохранить» does not move when the phone change opens.
  Widget _footer(AppLocalizations strings) {
    final label = switch (_step) {
      _Step.form => strings.saveChangesButton,
      _Step.phone => strings.sendCodeButton,
      _Step.code => strings.verifyCodeButton,
    };
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, systemInset + _footerGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppWideButton(
            label: label,
            busy: _busy,
            onTap: _busy ? null : _onPrimaryAction,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: _onBack == null
                ? null
                : TextButton(
                    onPressed: _busy ? null : _onBack,
                    child: Text(
                      _step == _Step.code
                          ? strings.changePhoneButton
                          : strings.stepBackButton,
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

/// A quiet line of consequence under a control - what the choice above costs, or why it is fixed.
/// Deliberately not [AppErrorLine]: nothing has gone wrong, and danger colours here would read as a
/// refusal of a form nobody has submitted yet.
class _Note extends StatelessWidget {
  const _Note(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.textMuted,
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
