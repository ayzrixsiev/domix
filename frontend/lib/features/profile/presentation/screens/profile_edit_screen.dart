import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/app_form.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import 'package:frontend/core/widgets/destructive_confirm_dialog.dart';
import 'package:frontend/core/widgets/role_option_tile.dart';
import 'package:frontend/features/profile/data/auth_service.dart';
import 'package:frontend/features/profile/data/account_role.dart';
import '../controllers/auth_controller.dart';

/// Editing an account that already exists: the display name and the role on one form.
///
/// **The number is not editable here or anywhere**: it is the one telegram proved at sign-in, and a
/// different number is a different account.
///
/// **A full-screen route with an X, like the registration flow.** Nothing auto-submits: «Сохранить»
/// writes, the X abandons.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  /// Opens the editor over whatever is on screen, and answers whether anything was saved - so the
  /// profile behind it can say so.
  static Future<bool> open(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const ProfileEditScreen(),
        fullscreenDialog: true,
      ),
    );
    return saved ?? false;
  }

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

/// Clear air under the footer's button, over the system inset.
const double _footerGap = 24;

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _nameController = TextEditingController();

  /// The role as it will be saved. Seeded from the account and only movable while
  /// [AccountRole.canStillChange] - see [_roleSection].
  late AccountRole _role;

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
    _nameController.dispose();
    super.dispose();
  }

  AppLocalizations get _strings => context.read<LanguageProvider>().strings;

  /// The role the account arrived with - what a change is measured against, and what decides
  /// whether the picker is drawn at all.
  AccountRole get _originalRole => AccountRole.of(
    isVendor: context.read<AuthController>().profileState.isVendor,
  );

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
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
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
            subtitle: strings.editProfileSubtitle,
            showBack: false,
            action: CircleIconButton(
              icon: LucideIcons.x,
              tooltip: strings.closeButton,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(child: _formStep(strings)),
          _footer(strings),
        ],
      ),
    );
  }

  /// The form on a scrollable page, with the refusal above it.
  ///
  /// **The error is drawn here and not in the footer**, so it pushes content that was already
  /// scrollable instead of changing the footer's height and walking «Сохранить» up the screen.
  Widget _scrollable({required List<Widget> children}) {
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
          ...children,
        ],
      ),
    );
  }

  Widget _formStep(AppLocalizations strings) {
    return _scrollable(
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
        ..._roleSection(strings),
      ],
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
        AppNoteLine(strings.roleLockedNote, icon: LucideIcons.lock),
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
      AppNoteLine(strings.roleChangeWarning, icon: LucideIcons.triangle_alert),
    ];
  }

  Widget _footer(AppLocalizations strings) {
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, systemInset + _footerGap),
      child: AppWideButton(
        label: strings.saveChangesButton,
        busy: _busy,
        onTap: _busy ? null : _save,
      ),
    );
  }
}
