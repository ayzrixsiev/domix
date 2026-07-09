import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const Color _kPrimaryOrange = Color(0xFFFF6F00);
const Color _kPrimaryOrangeDark = Color(0xFFE65D00);
const Color _kTextPrimary = Color(0xFF111827);
const Color _kTextMuted = Color(0xFF64748B);
const Color _kDivider = Color(0xFFEEF0F2);
const Color _kSoftSurface = Color(0xFFF8FAFC);
const Color _kDanger = Color(0xFFB42318);
const Color _kDangerSoft = Color(0xFFFEF0EE);
const Color _kCardBorder = Color(0xFFF2F4F7);

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

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPadding),
        children: [
          _buildHeaderCard(),
          SizedBox(height: profile.isVendor ? 28 : 20),
          if (!profile.isVendor) ...[
            _buildActionCard(),
            const SizedBox(height: 28),
          ],
          _buildMenuLabel(),
          const SizedBox(height: 10),
          _MenuGroupCard(rows: _buildMenuRows()),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'Domix • версия 1.0.0',
              style: TextStyle(
                color: _kTextMuted.withOpacity(0.55),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    if (!showScaffold) {
      return ColoredBox(color: _kSoftSurface, child: body);
    }

    return Scaffold(backgroundColor: _kSoftSurface, body: body);
  }

  Widget _buildMenuLabel() {
    return const Padding(
      padding: EdgeInsets.only(left: 4),
      child: Text(
        'ЕЩЁ',
        style: TextStyle(
          color: Color(0xFF98A2B3),
          fontSize: 12,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kCardBorder),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8F2), Colors.white],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -70,
              right: -50,
              child: _decorativeBlob(200, _kPrimaryOrange.withOpacity(0.08)),
            ),
            Positioned(
              bottom: -60,
              left: -40,
              child: _decorativeBlob(140, _kPrimaryOrange.withOpacity(0.05)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
              child: profile.isGuest
                  ? _buildGuestHeader()
                  : _buildAccountHeader(),
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

  Widget _buildGuestHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ProfileAvatar(
          initials: 'АП',
          size: 78,
          backgroundColor: Color(0xFFFFEEDD),
          textColor: _kPrimaryOrangeDark,
        ),
        const SizedBox(height: 18),
        const Text(
          'Гость',
          style: TextStyle(
            color: _kTextPrimary,
            fontSize: 27,
            height: 1.1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildAccountHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ProfileAvatar(
          initials: profile.initials,
          size: 72,
          backgroundColor: const Color(0xFFFFEEDD),
          textColor: _kPrimaryOrangeDark,
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
                        color: _kTextPrimary,
                        fontSize: 21,
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
                    color: _kTextPrimary,
                    fontSize: 22,
                    height: 1.16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                profile.phoneNumber,
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 14,
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
        color: _kPrimaryOrange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Продавец',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
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
                    CupertinoIcons.lock_shield,
                    color: _kPrimaryOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Войти в аккаунт',
                        style: TextStyle(
                          color: _kTextPrimary,
                          fontSize: 17,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Сохраняйте избранное и отслеживайте заказы',
                        style: TextStyle(
                          color: _kTextMuted,
                          fontSize: 13.5,
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
                  color: _kPrimaryOrange,
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
                        color: _kTextPrimary,
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Откройте свой магазин строительных материалов',
                      style: TextStyle(
                        color: _kTextMuted,
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

  List<_MenuRowData> _buildMenuRows() {
    switch (profile.state) {
      case ProfileAccountState.guest:
        return [
          _MenuRowData(
            icon: CupertinoIcons.chat_bubble_2,
            title: 'Поддержка',
            onTap: onSupportTap,
          ),
        ];
      case ProfileAccountState.client:
        return [
          _MenuRowData(
            icon: CupertinoIcons.chat_bubble_2,
            title: 'Поддержка',
            onTap: onSupportTap,
          ),
          _MenuRowData(
            icon: CupertinoIcons.square_arrow_right,
            title: 'Выйти из аккаунта',
            textColor: _kDanger,
            iconColor: _kDanger,
            iconBackground: _kDangerSoft,
            onTap: onLogoutTap,
          ),
        ];
      case ProfileAccountState.vendor:
        return [
          _MenuRowData(
            icon: CupertinoIcons.bag,
            title: 'Управление магазином',
            onTap: onManageShopTap,
          ),
          _MenuRowData(
            icon: CupertinoIcons.plus_circle,
            title: 'Добавить новый товар',
            onTap: onAddProductTap,
          ),
          _MenuRowData(
            icon: CupertinoIcons.chat_bubble_2,
            title: 'Поддержка',
            onTap: onSupportTap,
          ),
          _MenuRowData(
            icon: CupertinoIcons.square_arrow_right,
            title: 'Выйти из аккаунта',
            textColor: _kDanger,
            iconColor: _kDanger,
            iconBackground: _kDangerSoft,
            onTap: onLogoutTap,
          ),
        ];
    }
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
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Color? textColor;
  final Color? iconColor;
  final Color? iconBackground;
}

class _MenuGroupCard extends StatelessWidget {
  const _MenuGroupCard({required this.rows});

  final List<_MenuRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              _MenuRow(data: rows[i], isLast: i == rows.length - 1),
          ],
        ),
      ),
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
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: _kDivider)),
          ),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: resolvedIconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(data.icon, color: resolvedIconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  data.title,
                  style: TextStyle(
                    color: resolvedTextColor,
                    fontSize: 15.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                color: resolvedTextColor.withOpacity(0.35),
                size: 17,
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
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: textColor,
          fontSize: size * 0.32,
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
        border: Border.all(color: _kCardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.06),
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
      color: _kPrimaryOrange,
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