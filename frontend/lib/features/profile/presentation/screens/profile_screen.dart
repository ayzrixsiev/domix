import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/destructive_confirm_dialog.dart';
import 'package:frontend/features/onboarding/presentation/screens/onboarding_flow.dart';
import '../controllers/auth_controller.dart';

const Color _kPrimaryOrange = Color(0xFFFF6F00);
const Color _kPrimaryOrangeDark = Color(0xFFE65D00);
const Color _kTextPrimary = Color(0xFF111827);
const Color _kTextMuted = Color(0xFF64748B);
const Color _kDivider = Color(0xFFEEF0F2);
const Color _kSoftSurface = Color(0xFFF8FAFC);
const Color _kDanger = Color(0xFFB42318);
const Color _kDangerSoft = Color(0xFFFEF0EE);
const Color _kCardBorder = Color(0xFFF2F4F7);


// 2. profile state and account type models
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
      phoneNumber = '';

  const ProfileViewState.client({
    required this.initials,
    required this.fullName,
    required this.phoneNumber,
  }) : state = ProfileAccountState.client;

  const ProfileViewState.vendor({
    required this.initials,
    required this.fullName,
    required this.phoneNumber,
  }) : state = ProfileAccountState.vendor;

  final ProfileAccountState state;
  final String initials;
  final String fullName;
  final String phoneNumber;

  bool get isGuest => state == ProfileAccountState.guest;
  bool get isVendor => state == ProfileAccountState.vendor;
}

// 3. main interactive screen widget
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
    Provider.of<LanguageProvider>(context, listen: false)
        .updateLanguage(newLang);
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
                      color: _kDivider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _strings.selectLanguage,
                  style: const TextStyle(
                    color: _kTextPrimary,
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

    // **A guest gets the onboarding flow, not a card.** Language, the privacy policy, name and
    // role, then the phone code - see OnboardingFlow, which owns all four and every error they can
    // produce. This screen is the signed-in profile and the host of that flow, nothing else.
    final body = currentProfile.isGuest
        ? OnboardingFlow(bottomPadding: widget.bottomPadding)
        : _buildAccountBody(currentProfile, authController);

    return widget.showScaffold
        ? Scaffold(backgroundColor: _kSoftSurface, body: body)
        : ColoredBox(color: _kSoftSurface, child: body);
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
  /// **It takes its wording from the caller.** It used to take a `message`, ignore it, and print the
  /// *login* strings - so a failed account deletion told the user to check their Telegram install, and
  /// nothing could catch it since `message` was used in the `debugPrint`.
  ///
  /// [detail] is logged and never drawn: the line that debugs this is the line no shop owner can act on.
  void _showErrorDialog({required String title, required String body, String? detail}) {
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
                  color: _kDangerSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: _kDanger,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              _ProfileButton(
                label: _strings.okButton,
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  Provider.of<AuthController>(context, listen: false).clearError();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The signed-in profile: account header, the shop accordion for owners, the settings menu and
  /// the deletion card. Only ever reached with a real account - [build] sends a guest to the login
  /// card instead - so nothing in here re-checks for one.
  Widget _buildAccountBody(ProfileViewState currentProfile, AuthController authController) {
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
                onToggle: () => setState(() => _showShopsSubMenu = !_showShopsSubMenu),
                // the header doubles as the close control once open, so the group needs no separate "collapse"
                // row: the chevron already rotated to point at what it revealed
                header: _MenuRowData(
                  icon: CupertinoIcons.bag,
                  title: _showShopsSubMenu ? _strings.closeButton : _strings.manageShops,
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

          // standard operations card showing basic options for customers.
          //
          // **No «Поддержка» row.** Support is a tab in the nav bar, always one tap away from
          // anywhere; a second door to the same screen buried in a settings list is one more thing
          // to keep in step for no reach it does not already have.
          _MenuGroupCard(
            rows: [
              _MenuRowData(
                icon: CupertinoIcons.heart,
                title: _strings.favorites,
                onTap: widget.onFavoritesTap,
              ),
              _MenuRowData(
                icon: CupertinoIcons.globe,
                title: '${_strings.languageSettings} (${_currentLang.displayName})',
                onTap: _showLanguagePicker,
              ),
              _MenuRowData(
                icon: CupertinoIcons.square_arrow_right,
                title: _strings.logout,
                textColor: _kDanger,
                iconColor: _kDanger,
                iconBackground: _kDangerSoft,
                onTap: () {
                  setState(() => _showShopsSubMenu = false);
                  Provider.of<AuthController>(context, listen: false).logout();
                },
              ),
            ],
          ),

          // account deletion, in a card of its own below the menu: an irreversible action sharing a list with
          // "Язык приложения" is one somebody eventually taps on the way to something else.
          //
          // **This exists because Google Play requires it** - an app that lets a user create an account must
          // let them delete it from inside the app, or the listing is rejected at review.
          const SizedBox(height: 16),
          _MenuGroupCard(
            rows: [
              _MenuRowData(
                icon: CupertinoIcons.trash,
                title: _strings.deleteAccount,
                textColor: _kDanger,
                iconColor: _kDanger,
                iconBackground: _kDangerSoft,
                // a spinner in the trailing slot rather than a disabled row: the request is a round trip a shop
                // owner with a large catalogue will notice, and a row that stops responding reads as a freeze
                trailing: authController.isDeletingAccount
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _kDanger),
                      )
                    : null,
                onTap: authController.isDeletingAccount ? null : _confirmDeleteAccount,
              ),
            ],
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              _strings.version,
              style: TextStyle(
                color: _kTextMuted.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildAccountHeaderCard(ProfileViewState profile) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kCardBorder),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8F2), Colors.white],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -60,
              right: -40,
              child: _decorativeBlob(180, _kPrimaryOrange.withValues(alpha: 0.08)),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 76, not 68: with the vendor badge stacked above the name and phone the text column measures
                  // ~71px, so the old avatar was shorter than the text beside it and the outer lines hung past it
                  _ProfileAvatar(
                    initials: profile.initials,
                    size: 76,
                    backgroundColor: const Color(0xFFFFEEDD),
                    textColor: _kPrimaryOrangeDark,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (profile.isVendor) ...[
                          _buildVendorBadge(),
                          const SizedBox(height: 6),
                        ],
                        // single line keeps the column's height predictable against the avatar
                        Text(
                          profile.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontSize: 20,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile.phoneNumber,
                          style: const TextStyle(
                            color: _kTextMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVendorBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _kPrimaryOrange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.checkmark_seal_fill,
            color: Colors.white,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            _strings.vendorBadge,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
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
            color: isSelected ? const Color(0xFFFFF0E3) : _kSoftSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? _kPrimaryOrangeDark : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                language.displayName,
                style: TextStyle(
                  color: isSelected ? _kPrimaryOrangeDark : _kTextPrimary,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (isSelected)
                const Icon(
                  CupertinoIcons.checkmark_alt_circle_fill,
                  color: _kPrimaryOrangeDark,
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
        border: Border.all(color: _kCardBorder),
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
            iconColor: isExpanded ? _kPrimaryOrangeDark : header.iconColor,
            iconBackground: isExpanded ? const Color(0xFFFFF0E3) : header.iconBackground,
            // 0.25 turns = 90 degrees, so the forward chevron ends up pointing down at the rows it revealed
            trailing: AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: _duration,
              curve: _curve,
              child: Icon(
                CupertinoIcons.chevron_forward,
                color: isExpanded
                    ? _kPrimaryOrangeDark
                    : (header.textColor ?? _kTextPrimary).withValues(alpha: 0.3),
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
                      _MenuRow(data: children[i], isLast: i == children.length - 1),
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
    final resolvedTextColor = data.textColor ?? _kTextPrimary;
    final resolvedIconColor = data.iconColor ?? _kTextMuted;
    final resolvedIconBg = data.iconBackground ?? _kSoftSurface;

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
                : const Border(bottom: BorderSide(color: _kDivider)),
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
      color: _kPrimaryOrange,
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