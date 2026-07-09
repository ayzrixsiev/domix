import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum ProfileAccountState {
  guest('StateGUEST'),
  client('StateCLIENT'),
  vendor('StateVENDOR');

  const ProfileAccountState(this.apiCode);

  final String apiCode;
}

class ProfileViewState {
  const ProfileViewState.guest({this.initials = 'АП'})
    : state = ProfileAccountState.guest,
      fullName = 'Гость',
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
  bool get isClient => state == ProfileAccountState.client;
  bool get isVendor => state == ProfileAccountState.vendor;
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.profile = const ProfileViewState.guest(),
    this.showScaffold = true,
    this.bottomPadding = 36,
    this.onLoginTap,
    this.onCreateShopTap,
    this.onManageShopTap,
    this.onAddProductTap,
    this.onSupportTap,
    this.onLogoutTap,
  });

  final ProfileViewState profile;
  final bool showScaffold;
  final double bottomPadding;
  final VoidCallback? onLoginTap;
  final VoidCallback? onCreateShopTap;
  final VoidCallback? onManageShopTap;
  final VoidCallback? onAddProductTap;
  final VoidCallback? onSupportTap;
  final VoidCallback? onLogoutTap;

  static const Color _primaryOrange = Color(0xFFFF6F00);
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _divider = Color(0xFFEAECEF);
  static const Color _softSurface = Color(0xFFF8FAFC);
  static const Color _danger = Color(0xFFB42318);

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 28, 20, bottomPadding),
        children: [
          _buildHeader(),
          if (!profile.isVendor) ...[
            const SizedBox(height: 28),
            _buildActionCard(),
          ],
          SizedBox(height: profile.isVendor ? 30 : 24),
          ..._buildMenuRows(),
        ],
      ),
    );

    if (!showScaffold) {
      return ColoredBox(color: Colors.white, child: body);
    }

    return Scaffold(backgroundColor: Colors.white, body: body);
  }

  Widget _buildHeader() {
    if (profile.isGuest) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileAvatar(
            initials: profile.initials,
            size: 86,
            backgroundColor: const Color(0xFFEDEBFF),
            textColor: const Color(0xFF5B5A7A),
          ),
          const SizedBox(height: 18),
          const Text(
            'Гость',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 28,
              height: 1.12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ProfileAvatar(
          initials: profile.initials,
          size: 78,
          backgroundColor: const Color(0xFFFFF0E3),
          textColor: _primaryOrange,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (profile.isVendor)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      profile.fullName,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 23,
                        height: 1.16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _buildVendorBadge(),
                  ],
                )
              else
                Text(
                  profile.fullName,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 24,
                    height: 1.16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(height: 7),
              Text(
                profile.phoneNumber,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 15,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVendorBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0E3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFD7B8)),
      ),
      child: const Text(
        'Продавец',
        style: TextStyle(
          color: _primaryOrange,
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    if (profile.isGuest) {
      return _ProfileCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Войти в аккаунт. Сохраняйте избранное и отслеживайте заказы',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            _ProfileButton(
              label: 'Войти / Зарегистрироваться',
              onTap: onLoginTap,
            ),
          ],
        ),
      );
    }

    return _ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  CupertinoIcons.bag_badge_plus,
                  color: _primaryOrange,
                  size: 23,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Зарабатывайте с Domix',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Откройте свой магазин строительных материалов',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ProfileButton(label: 'Создать магазин', onTap: onCreateShopTap),
        ],
      ),
    );
  }

  List<Widget> _buildMenuRows() {
    switch (profile.state) {
      case ProfileAccountState.guest:
        return [
          _buildMenuRow(
            icon: CupertinoIcons.chat_bubble_2,
            title: 'Поддержка',
            onTap: onSupportTap,
          ),
        ];
      case ProfileAccountState.client:
        return [
          _buildMenuRow(
            icon: CupertinoIcons.chat_bubble_2,
            title: 'Поддержка',
            onTap: onSupportTap,
          ),
          _buildMenuRow(
            icon: CupertinoIcons.square_arrow_right,
            title: 'Выйти из аккаунта',
            textColor: _danger,
            iconColor: _danger,
            onTap: onLogoutTap,
          ),
        ];
      case ProfileAccountState.vendor:
        return [
          _buildMenuRow(
            icon: CupertinoIcons.bag,
            title: 'Управление магазином',
            onTap: onManageShopTap,
          ),
          _buildMenuRow(
            icon: CupertinoIcons.plus_circle,
            title: 'Добавить новый товар',
            onTap: onAddProductTap,
          ),
          _buildMenuRow(
            icon: CupertinoIcons.chat_bubble_2,
            title: 'Поддержка',
            onTap: onSupportTap,
          ),
          _buildMenuRow(
            icon: CupertinoIcons.square_arrow_right,
            title: 'Выйти из аккаунта',
            textColor: _danger,
            iconColor: _danger,
            onTap: onLogoutTap,
          ),
        ];
    }
  }

  Widget _buildMenuRow({
    required IconData icon,
    required String title,
    required VoidCallback? onTap,
    Color? textColor,
    Color? iconColor,
  }) {
    final resolvedTextColor = textColor ?? _textPrimary;
    final resolvedIconColor = iconColor ?? _textMuted;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 66,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _divider)),
          ),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: _softSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: resolvedIconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: resolvedTextColor,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                color: resolvedTextColor.withAlpha(92),
                size: 18,
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
    required this.initials,
    required this.size,
    required this.backgroundColor,
    required this.textColor,
  });

  final String initials;
  final double size;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          color: textColor,
          fontSize: size * 0.3,
          height: 1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF2F4F7)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.08),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
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
      color: ProfileScreen._primaryOrange,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap ?? () {},
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
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
