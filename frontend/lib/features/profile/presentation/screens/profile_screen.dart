import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/app_form.dart';
import 'package:frontend/core/widgets/destructive_confirm_dialog.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:frontend/features/profile/data/account_role.dart';
import '../controllers/auth_controller.dart';
import 'about_screen.dart';
import 'profile_edit_screen.dart';

enum ProfileAccountState {
  guest('StateGUEST'),
  client('StateCLIENT'),
  vendor('StateVENDOR');

  const ProfileAccountState(this.apiCode);
  final String apiCode;
}

class ProfileViewState {
  const ProfileViewState.guest()
    : state = ProfileAccountState.guest,
      initials = '',
      fullName = '',
      phoneNumber = '',
      isAdmin = false;

  const ProfileViewState.client({
    required this.initials,
    required this.fullName,
    required this.phoneNumber,
  }) : state = ProfileAccountState.client,
       isAdmin = false;

  const ProfileViewState.vendor({
    required this.initials,
    required this.fullName,
    required this.phoneNumber,
    this.isAdmin = false,
  }) : state = ProfileAccountState.vendor;

  final ProfileAccountState state;
  final String initials;
  final String fullName;
  final String phoneNumber;
  final bool isAdmin;

  bool get isGuest => state == ProfileAccountState.guest;
  bool get isVendor => state == ProfileAccountState.vendor;

  /// Корзина is a customer's tab, and staff may use it too: the server lets `admin` through.
  bool get seesCart => !isVendor || isAdmin;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.showScaffold = true,
    this.bottomPadding = 36,
    this.onManageShopTap,
    this.onAddStoreTap,
    this.onFavoritesTap,
  });

  final bool showScaffold;
  final double bottomPadding;
  final VoidCallback? onManageShopTap;
  final VoidCallback? onAddStoreTap;
  final VoidCallback? onFavoritesTap;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _showShopsSubMenu = false;

  /// The current language's copy, read **without subscribing** - see [build] for the subscription.
  /// **`Provider.of(context)` defaults to `listen: true`, and that is illegal outside a build**: from
  /// a tap handler it throws *inside* the gesture callback, so «Удалить аккаунт» simply did nothing.
  AppLocalizations get _strings => context.read<LanguageProvider>().strings;

  AppLanguage get _currentLang => context.read<LanguageProvider>().language;

  void _updateLanguage(AppLanguage newLang) {
    Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).updateLanguage(newLang);
  }

  // open bottom modal sheet to select between russian and uzbek
  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _strings.selectLanguage,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                for (final lang in AppLanguage.values)
                  _LanguageOptionTile(
                    language: lang,
                    isSelected: lang == _currentLang,
                    onTap: () {
                      Navigator.pop(context);
                      _updateLanguage(lang);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // the one place this screen subscribes to the language. every `_strings` below reads without
    // listening - half of them are inside tap handlers - so without this line switching to uzbek would
    // leave the profile in russian until something else rebuilt it.
    context.watch<LanguageProvider>();

    final authController = Provider.of<AuthController>(context);
    final currentProfile = authController.profileState;

    // **A guest gets a door, not the flow.** Registration is a full-screen route over the shell -
    // see OnboardingFlow - because signing up with the nav bar still on screen read as a half-open
    // door. The tab itself only has to explain why there is nothing here and lead into that route;
    // tapping Профиль from the nav bar opens it directly, so this is the way back in after the flow
    // was closed or the account signed out of.
    final body = currentProfile.isGuest
        ? _guestGate(_strings)
        : _buildAccountBody(currentProfile, authController);

    return widget.showScaffold
        ? Scaffold(backgroundColor: AppColors.background, body: body)
        : ColoredBox(color: AppColors.background, child: body);
  }

  /// **One button for both, because the server decides.** `/verify` finds the account or creates it,
  /// so "войти" and "зарегистрироваться" are the same five steps and the same request - two controls
  /// here would be two labels on one door.
  Widget _guestGate(AppLocalizations strings) {
    return EmptyStateView(
      icon: LucideIcons.user,
      title: strings.profileGuestTitle,
      subtitle: strings.profileGuestBody,
      bottomInset: widget.bottomPadding,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryActionButton(
            label: strings.profileGuestAction,
            icon: LucideIcons.log_in,
            onTap: () => OnboardingFlow.open(context),
          ),
          const SizedBox(height: 8),
          // reachable without an account: the map works for a guest, so its licence's «About» link has
          // to as well - and a Play reviewer without Telegram never gets past this screen
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
            child: Text(
              strings.aboutApp,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Asks once, then destroys the account on the server and signs out locally. The confirmation lives
  /// here rather than on the backend, where the sentence can name what is about to disappear.
  ///
  /// [AuthController.deleteAccount] calls the server *before* touching local storage, so a failure
  /// leaves the session exactly as it was and all this has to do is report it.
  Future<void> _confirmDeleteAccount() async {
    final strings = _strings;
    final controller = context.read<AuthController>();

    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: strings.deleteAccountConfirmTitle,
      body: strings.deleteAccountConfirmBody,
      confirmLabel: strings.deleteAccountConfirmAction,
      cancelLabel: strings.cancelButton,
    );
    // `mounted` after every await, not once at the top: the dialog is a route, and the user can
    // background the app or pop this screen while it is open
    if (!confirmed || !mounted) return;

    // collapse the shop submenu first - the rows behind it are about shops that are being deleted
    setState(() => _showShopsSubMenu = false);

    final deleted = await controller.deleteAccount();
    if (!mounted) return;

    if (!deleted) {
      // its own headline, not the login one: «Что-то пошло не так» over Telegram instructions sent the
      // founder looking for a Telegram problem that did not exist
      _showErrorDialog(
        title: strings.deleteAccountFailedTitle,
        // a code, localized here - so the message follows the app's language even if it changed while the
        // request was in flight
        body: strings.deleteAccountErrorFor(controller.deleteAccountErrorCode),
      );
      return;
    }
    // on success the controller has already dropped to the guest state, so this screen has rebuilt
    // itself into the signed-out version - there is nothing left to navigate away from
  }

  /// The app's one modal error: an icon, a headline, a sentence, and an OK.
  ///
  /// **It draws the wording the caller passes** - a dialog that printed one flow's strings for every
  /// caller told the user the wrong thing with nothing able to catch it.
  ///
  /// [detail] is logged and never drawn: the line that debugs this is the line no owner can act on.
  void _showErrorDialog({
    required String title,
    required String body,
    String? detail,
  }) {
    if (detail != null) debugPrint('Auth error: $detail');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.dangerSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: AppColors.danger,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              _ProfileButton(
                label: _strings.okButton,
                onTap: () => Navigator.of(dialogCtx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// **A route rather than a sheet**, like the registration flow: a form under the nav bar reads as a
  /// half-open door. nothing here reloads the profile - the write goes through [AuthController], which
  /// has notified this screen by the time the route pops.
  Future<void> _openEditor() async {
    final saved = await ProfileEditScreen.open(context);
    if (!saved || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_strings.accountSavedMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// The signed-in profile: account header, the shop accordion for owners, and the settings menu.
  /// Only ever reached with a real account - [build] sends a guest to the login card instead - so
  /// nothing in here re-checks for one.
  Widget _buildAccountBody(
    ProfileViewState currentProfile,
    AuthController authController,
  ) {
    return SafeArea(
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 16, 20, widget.bottomPadding),
        children: [
          _buildAccountHeaderCard(currentProfile),
          const SizedBox(height: 24),

          // shop management, as an accordion the owner opens in place. it used to swap this card for an
          // entirely different one, which is why the entry point vanished on tap and its chevron could never
          // indicate open or closed.
          if (currentProfile.isVendor) ...[
            _MenuGroupCard(
              rows: const [],
              leading: _ExpandableMenuSection(
                isExpanded: _showShopsSubMenu,
                onToggle: () =>
                    setState(() => _showShopsSubMenu = !_showShopsSubMenu),
                // the header doubles as the close control once open, so the group needs no separate "collapse"
                // row: the chevron already rotated to point at what it revealed
                header: _MenuRowData(
                  icon: CupertinoIcons.bag,
                  title: _showShopsSubMenu
                      ? _strings.closeButton
                      : _strings.manageShops,
                  onTap: null, // supplied by the section, which owns the toggle
                ),
                children: [
                  _MenuRowData(
                    icon: CupertinoIcons.slider_horizontal_3,
                    title: _strings.shopSettings,
                    onTap: widget.onManageShopTap,
                  ),
                  _MenuRowData(
                    icon: CupertinoIcons.plus_square,
                    title: _strings.addStore,
                    onTap: widget.onAddStoreTap,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // every account operation in one card, ending with the two that close it.
          //
          // **Only «Удалить аккаунт» is red.** Signing out is undone by signing back in, so a danger
          // colour on it spends the list's one alarm on the row that is not alarming, and leaves the
          // irreversible row below looking like more of the same.
          _MenuGroupCard(
            rows: [
              _MenuRowData(
                icon: CupertinoIcons.heart,
                title: _strings.favorites,
                onTap: widget.onFavoritesTap,
              ),
              _MenuRowData(
                icon: CupertinoIcons.globe,
                title:
                    '${_strings.languageSettings} (${_currentLang.displayName})',
                onTap: _showLanguagePicker,
              ),
              _MenuRowData(
                icon: CupertinoIcons.info,
                title: _strings.aboutApp,
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
              ),
              _MenuRowData(
                icon: CupertinoIcons.square_arrow_right,
                title: _strings.logout,
                onTap: () {
                  setState(() => _showShopsSubMenu = false);
                  Provider.of<AuthController>(context, listen: false).logout();
                },
              ),
              // **This exists because Google Play requires it** - an app that lets a user create an
              // account must let them delete it from inside the app, or the listing is rejected at
              // review.
              _MenuRowData(
                icon: CupertinoIcons.trash,
                title: _strings.deleteAccount,
                textColor: AppColors.danger,
                iconColor: AppColors.danger,
                iconBackground: AppColors.dangerSoft,
                // a spinner in the trailing slot rather than a disabled row: the request is a round trip a shop
                // owner with a large catalogue will notice, and a row that stops responding reads as a freeze
                trailing: authController.isDeletingAccount
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.danger,
                        ),
                      )
                    : null,
                onTap: authController.isDeletingAccount
                    ? null
                    : _confirmDeleteAccount,
              ),
            ],
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              _strings.version,
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Who this account is, in three lines that read downward.
  ///
  /// **Stacked rather than laid beside the avatar**: the name gets the card's whole width, which is
  /// what lets it read as the subject of the screen. Beside a 76px disc a two-part Uzbek name ellipsed
  /// on any phone narrower than a Pixel. The role and the number share the last line because they
  /// answer the same question.
  Widget _buildAccountHeaderCard(ProfileViewState profile) {
    final role = AccountRole.of(isVendor: profile.isVendor);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md + 4),
        border: Border.all(color: AppColors.hairline),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primarySoft, Colors.white],
        ),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md + 4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -70,
              right: -50,
              child: _decorativeBlob(
                190,
                AppColors.primaryOrange.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProfileAvatar(
                        initials: profile.initials,
                        size: 66,
                        backgroundColor: AppColors.primaryTint,
                        textColor: AppColors.primaryDeep,
                      ),
                      const Spacer(),
                      _EditProfileButton(
                        label: _strings.editProfileButton,
                        onTap: _openEditor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    profile.fullName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 25,
                      height: 1.15,
                      letterSpacing: -0.6,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _RoleBadge(role: role, label: role.badgeLabel(_strings)),
                      const SizedBox(width: 10),
                      // Flexible, not a bare Text: a long role label and a twelve-digit number
                      // together overrun a narrow phone, and the number is the half that may clip
                      Flexible(
                        child: Text(
                          formatUzPhone(profile.phoneNumber),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decorativeBlob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// The way in to the editor, opposite the avatar. A white pill on the header's tinted gradient
/// rather than a [CircleIconButton]: this one is labelled, because a bare pencil over a name and a
/// phone number does not say which of them it edits.
class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceWhite,
      borderRadius: BorderRadius.circular(999),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.pencil,
                size: 13,
                color: AppColors.primaryOrange,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.primaryOrange,
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which side of the marketplace this account stands on, as a pill beside the number.
///
/// **Brand orange only for the roles that are a standing in it.** A shop owner and a worker are
/// offering something to everyone else; a customer is the default every account starts as, and
/// painting that in the one colour reserved for primary actions spends it on a word nobody chose.
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role, required this.label});

  final AccountRole role;
  final String label;

  @override
  Widget build(BuildContext context) {
    final professional = role != AccountRole.client;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: professional ? AppColors.primaryOrange : AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(999),
        border: professional ? null : Border.all(color: AppColors.hairline),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: professional ? Colors.white : AppColors.textMuted,
          fontSize: 10.5,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  const _LanguageOptionTile({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primarySoft : AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.primaryDeep : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                language.displayName,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primaryDeep
                      : AppColors.textDark,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (isSelected)
                const Icon(
                  CupertinoIcons.checkmark_alt_circle_fill,
                  color: AppColors.primaryDeep,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRowData {
  const _MenuRowData({
    required this.icon,
    required this.title,
    required this.onTap,
    this.textColor,
    this.iconColor,
    this.iconBackground,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Color? textColor;
  final Color? iconColor;
  final Color? iconBackground;

  /// what sits at the far right. null for the usual "this navigates somewhere" chevron; pass a widget
  /// to replace it, or [SizedBox.shrink] for a row that does not lead anywhere.
  final Widget? trailing;
}

class _MenuGroupCard extends StatelessWidget {
  const _MenuGroupCard({required this.rows, this.leading});

  final List<_MenuRowData> rows;

  /// an optional section rendered above [rows] inside the same card - the expandable shop-management
  /// group, which owns its own animation rather than being a plain row
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // the clip is what lets the expanding section slide out from under the header instead of spilling
      // past the card's rounded corners mid-animation
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            ?leading,
            for (var i = 0; i < rows.length; i++)
              _MenuRow(data: rows[i], isLast: i == rows.length - 1),
          ],
        ),
      ),
    );
  }
}

// an accordion section for a menu card: a header row that stays put and reveals its children in
// place. keeping the header on screen is the point - a control that disappears the moment you use it
// cannot say what state it put you in.
class _ExpandableMenuSection extends StatelessWidget {
  const _ExpandableMenuSection({
    required this.header,
    required this.children,
    required this.isExpanded,
    required this.onToggle,
  });

  final _MenuRowData header;
  final List<_MenuRowData> children;
  final bool isExpanded;
  final VoidCallback onToggle;

  static const Duration _duration = Duration(milliseconds: 260);
  // quick to start, long gentle settle - the same easing family the rest of the app uses
  static const Curve _curve = Cubic(0.22, 1, 0.36, 1);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MenuRow(
          data: _MenuRowData(
            icon: header.icon,
            title: header.title,
            onTap: onToggle,
            textColor: header.textColor,
            iconColor: isExpanded ? AppColors.primaryDeep : header.iconColor,
            iconBackground: isExpanded
                ? AppColors.primarySoft
                : header.iconBackground,
            // 0.25 turns = 90 degrees, so the forward chevron ends up pointing down at the rows it revealed
            trailing: AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: _duration,
              curve: _curve,
              child: Icon(
                CupertinoIcons.chevron_forward,
                color: isExpanded
                    ? AppColors.primaryDeep
                    : (header.textColor ?? AppColors.textDark).withValues(
                        alpha: 0.3,
                      ),
                size: 16,
              ),
            ),
          ),
          isLast: !isExpanded,
        ),
        // AnimatedSize measures its child each frame and tweens its own height, so swapping the rows for
        // an empty box animates the reveal without an AnimationController. topCenter anchors the growth.
        AnimatedSize(
          duration: _duration,
          curve: _curve,
          alignment: Alignment.topCenter,
          child: isExpanded
              ? Column(
                  children: [
                    for (var i = 0; i < children.length; i++)
                      _MenuRow(
                        data: children[i],
                        isLast: i == children.length - 1,
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.data, required this.isLast});

  final _MenuRowData data;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final resolvedTextColor = data.textColor ?? AppColors.textDark;
    final resolvedIconColor = data.iconColor ?? AppColors.textMuted;
    final resolvedIconBg = data.iconBackground ?? AppColors.background;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap ?? () {},
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: resolvedIconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(data.icon, color: resolvedIconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  data.title,
                  style: TextStyle(
                    color: resolvedTextColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              data.trailing ??
                  Icon(
                    CupertinoIcons.chevron_forward,
                    color: resolvedTextColor.withValues(alpha: 0.3),
                    size: 16,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    this.initials,
    required this.size,
    required this.backgroundColor,
    required this.textColor,
  });

  final String? initials;
  final double size;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        initials ?? '',
        style: TextStyle(
          color: textColor,
          fontSize: size * 0.35,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryOrange,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 52,
          width: double.infinity,
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
