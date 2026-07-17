import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

// 1. localization engine for russian and uzbek languages
enum AppLanguage {
  ru('Русский', 'ru'),
  uz("O'zbekcha", 'uz');

  const AppLanguage(this.displayName, this.code);
  final String displayName;
  final String code;
}

class _LocalizedStrings {
  final AppLanguage lang;
  _LocalizedStrings(this.lang);

  bool get isRu => lang == AppLanguage.ru;

  String get loginTitle => isRu ? 'Войти в аккаунт' : 'Hisobga kirish';
  String get loginSubtitle => isRu
      ? 'Находите магазины, сравнивайте предложения и развивайте свой бизнес!'
      : "Do'konlarni toping, takliflarni solishtiring va biznesingizni rivojlantiring!";
  String get loginButton => isRu
      ? 'Войти / Зарегистрироваться'
      : "Kirish / Ro'yxatdan o'tish";

  String get vendorBadge => isRu ? 'Продавец' : 'Sotuvchi';
  String get manageShops =>
      isRu ? 'Управление магазинами' : "Do'konlarni boshqarish";
  String get favorites => isRu ? 'Избранное' : 'Tanlanganlar';
  String get languageSettings => isRu ? 'Язык приложения' : 'Ilova tili';
  String get support => isRu ? 'Поддержка' : "Qo'llab-quvvatlash";
  String get logout => isRu ? 'Выйти из аккаунта' : 'Akkauntdan chiqish';
  String get selectLanguage => isRu ? 'Выберите язык' : 'Tilni tanlang';
  String get version => isRu ? 'Domix • 1.0.0' : 'Domix • 1.0.0';
}

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
  bool get isClient => state == ProfileAccountState.client;
  bool get isVendor => state == ProfileAccountState.vendor;
}

// 3. main interactive screen widget
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.profile = const ProfileViewState.guest(),
    this.initialLanguage = AppLanguage.ru,
    this.showScaffold = true,
    this.bottomPadding = 36,
    this.onLoginTap,
    this.onManageShopTap,
    this.onFavoritesTap,
    this.onSupportTap,
    this.onLogoutTap,
    this.onLanguageChanged,
  });

  final ProfileViewState profile;
  final AppLanguage initialLanguage;
  final bool showScaffold;
  final double bottomPadding;
  final VoidCallback? onLoginTap;
  final VoidCallback? onManageShopTap;
  final VoidCallback? onFavoritesTap;
  final VoidCallback? onSupportTap;
  final VoidCallback? onLogoutTap;
  final ValueChanged<AppLanguage>? onLanguageChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late AppLanguage _currentLang;
  late _LocalizedStrings _strings;
  
  // controller instance to manage login state and backend polling
  late final AuthController _authController;

  @override
  void initState() {
    super.initState();
    _currentLang = widget.initialLanguage;
    _strings = _LocalizedStrings(_currentLang);

    // initialize controller and bind state listener to repaint screen on login
    _authController = AuthController();
    _authController.addListener(_onAuthStateChanged);
  }

  // trigger ui repaint when backend login state changes
  void _onAuthStateChanged() {
    if (mounted) setState(() {});
  }

  // remove listener and kill polling timer to prevent memory leaks
  @override
  void dispose() {
    _authController.removeListener(_onAuthStateChanged);
    _authController.dispose(); 
    super.dispose();
  }

  // update interface language and notify parent layout
  void _updateLanguage(AppLanguage newLang) {
    setState(() {
      _currentLang = newLang;
      _strings = _LocalizedStrings(_currentLang);
    });
    widget.onLanguageChanged?.call(newLang);
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

  // open modal sheet to collect user name and role before launching telegram
  void _showLoginBottomSheet(BuildContext context) {
    final nameController = TextEditingController();
    String selectedRole = 'customer';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Регистрация / Ro'yxatdan o'tish",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Ваше имя и фамилия / Ismingiz va familiyangiz",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("Покупатель / Xaridor"),
                      selected: selectedRole == 'customer',
                      onSelected: (val) => setModalState(() => selectedRole = 'customer'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("Продавец / Sotuvchi"),
                      selected: selectedRole == 'shop_owner',
                      onSelected: (val) => setModalState(() => selectedRole = 'shop_owner'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6F00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    
                    // trigger backend authorization and switch app to telegram bot
                    _authController.startTelegramLogin(
                      name: nameController.text.trim().isEmpty ? "Domix User" : nameController.text.trim(),
                      role: selectedRole,
                      onSuccess: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Добро пожаловать в Domix! 🎉")),
                        );
                      },
                    );
                  },
                  child: const Text(
                    "Продолжить в Telegram", 
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // read active profile state directly from our live controller
    final currentProfile = _authController.profileState;

    final body = SafeArea(
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 16, 20, widget.bottomPadding),
        children: [
          // render guest hero prompt if unauthenticated, otherwise render user account header
          if (currentProfile.isGuest) ...[
            _buildGuestLoginHeroCard(),
            const SizedBox(height: 24),
          ] else ...[
            _buildAccountHeaderCard(currentProfile),
            const SizedBox(height: 24),
          ],

          // primary action links for shops and favorites using original outline icons
          if (!currentProfile.isGuest) ...[
            _MenuGroupCard(
              rows: [
                if (currentProfile.isVendor)
                  _MenuRowData(
                    icon: CupertinoIcons.bag,
                    title: _strings.manageShops,
                    onTap: widget.onManageShopTap,
                  ),
                _MenuRowData(
                  icon: CupertinoIcons.heart,
                  title: _strings.favorites,
                  onTap: widget.onFavoritesTap,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // app settings, language switcher, support, and dynamic logout button
          _MenuGroupCard(
            rows: [
              if (currentProfile.isGuest)
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
                icon: CupertinoIcons.chat_bubble_2,
                title: _strings.support,
                onTap: widget.onSupportTap,
              ),
              if (!currentProfile.isGuest)
                _MenuRowData(
                  icon: CupertinoIcons.square_arrow_right,
                  title: _strings.logout,
                  textColor: _kDanger,
                  iconColor: _kDanger,
                  iconBackground: _kDangerSoft,
                  onTap: () => _authController.logout(),
                ),
            ],
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              _strings.version,
              style: TextStyle(
                color: _kTextMuted.withOpacity(0.6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (!widget.showScaffold) {
      return ColoredBox(color: _kSoftSurface, child: body);
    }

    return Scaffold(backgroundColor: _kSoftSurface, body: body);
  }

  // guest hero card prompting unauthenticated users to log in
  Widget _buildGuestLoginHeroCard() {
    return _ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  CupertinoIcons.lock_shield,
                  color: _kPrimaryOrange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _strings.loginTitle,
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 19,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _strings.loginSubtitle,
                      style: const TextStyle(
                        color: _kTextMuted,
                        fontSize: 13.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _ProfileButton(
            label: _strings.loginButton,
            onTap: () => _showLoginBottomSheet(context),
          ),
        ],
      ),
    );
  }

  // gradient profile header card showing user initials, name, and phone
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
            color: Colors.black.withOpacity(0.04),
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
              child: _decorativeBlob(180, _kPrimaryOrange.withOpacity(0.08)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ProfileAvatar(
                    initials: profile.initials,
                    size: 68,
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
                                  fontSize: 20,
                                  height: 1.15,
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
                              fontSize: 20,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        const SizedBox(height: 6),
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

  // badge indicating the user is an active shop vendor
  Widget _buildVendorBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _kPrimaryOrange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _strings.vendorBadge,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // visual background circle decoration for header cards
  Widget _decorativeBlob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

// 4. helper components and interactive tiles
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
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
              Icon(
                CupertinoIcons.chevron_forward,
                color: resolvedTextColor.withOpacity(0.3),
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
            color: Colors.black.withOpacity(0.06),
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
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}