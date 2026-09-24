import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/app_shell/presentation/widgets/floating_bottom_nav_bar.dart';
import 'package:frontend/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/map/presentation/screens/map_screen.dart';
import 'package:frontend/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/messages/presentation/screens/chats_screen.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/profile/presentation/screens/profile_screen.dart';
import 'package:frontend/features/tickets/presentation/screens/tickets_screen.dart';
import 'package:frontend/features/stores/presentation/screens/add_store_screen.dart';
import 'package:frontend/features/stores/presentation/screens/my_shops_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> with WidgetsBindingObserver {
  static const _bottomPadding = 96.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // coming back into the app re-reads prices on the next shop opened - nothing refreshes mid-scroll
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ProductsController>().markAllStale();
    }
  }

  List<ShellNavItem> _buildNavItems(AppLocalizations strings) => [
    ShellNavItem(icon: LucideIcons.house, label: strings.homeTab),
    // the job-ticket marketplace took the slot search used to hold; search lives on the map and home.
    // a clipboard rather than a hard hat: the tab is every kind of request people post here, and a
    // helmet said "builders only" about a board that will also carry material baskets.
    ShellNavItem(icon: LucideIcons.clipboard_list, label: strings.ticketsTab),
    ShellNavItem(icon: LucideIcons.map_pin, label: strings.mapTab),
    ShellNavItem(icon: LucideIcons.message_square, label: strings.messagesTab),
    ShellNavItem(icon: LucideIcons.user, label: strings.profileTab),
  ];

  /// Named rather than a bare 2 in two places that would have to be changed together.
  static const _mapTabIndex = 2;

  static const _profileTabIndex = 4;

  // built per-frame rather than as a static field: ProfileScreen needs a BuildContext to push
  List<Widget> _buildPages(BuildContext context) => [
    const HomeScreen(showScaffold: false, bottomPadding: _bottomPadding),
    const TicketsScreen(showScaffold: false, bottomPadding: _bottomPadding),
    // IndexedStack builds every child and paints one, so the map cannot tell it is back in view -
    // and it needs to, since its shop list is a snapshot that goes stale. this bool is that signal.
    MapScreen(
      showScaffold: false,
      bottomPadding: _bottomPadding,
      isActive: _currentIndex == _mapTabIndex,
    ),
    const ChatsScreen(showScaffold: false, bottomPadding: _bottomPadding),
    ProfileScreen(
      showScaffold: false,
      bottomPadding: _bottomPadding,
      onFavoritesTap: () => FavoritesScreen.open(context),
      onAddStoreTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddStoreScreen()),
      ),
      onManageShopTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MyShopsScreen()),
      ),
    ),
  ];

  int _currentIndex = 0;

  void _selectTab(int index) {
    // **a guest's Профиль is a door, not a tab.** there is no profile to show until there is an
    // account, and registering under the nav bar read as a half-open door - so the tap opens the
    // flow over the shell and leaves the current tab where it was.
    if (index == _profileTabIndex && context.read<AuthController>().profileState.isGuest) {
      _openOnboarding();
      return;
    }

    if (_currentIndex == index) return;

    setState(() {
      _currentIndex = index;
    });
  }

  /// Lands on Профиль only if an account came out of the flow; a closed one leaves the visitor on
  /// the tab they were reading.
  Future<void> _openOnboarding() async {
    final signedIn = await OnboardingFlow.open(context);
    if (!mounted || !signedIn) return;

    setState(() {
      _currentIndex = _profileTabIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final navItems = _buildNavItems(strings);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      bottomNavigationBar: FloatingBottomNavBar(
        items: navItems,
        currentIndex: _currentIndex,
        onItemSelected: _selectTab,
      ),
      body: IndexedStack(index: _currentIndex, children: _buildPages(context)),
    );
  }
}
