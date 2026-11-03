import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/app_shell/presentation/widgets/floating_bottom_nav_bar.dart';
import 'package:frontend/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/map/presentation/controllers/map_focus_controller.dart';
import 'package:frontend/features/map/presentation/screens/map_screen.dart';
import 'package:frontend/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/messages/presentation/screens/chats_screen.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/profile/presentation/screens/profile_screen.dart';
import 'package:frontend/features/waybills/presentation/screens/waybills_screen.dart';
import 'package:frontend/features/stores/presentation/screens/add_store_screen.dart';
import 'package:frontend/features/stores/presentation/screens/my_shops_screen.dart';

/// In the order the pages stack. **A tab is named rather than numbered** because Корзина is missing from
/// an owner's bar: the same position means a different tab depending on who is signed in.
enum _ShellTab { home, cart, map, messages, profile }

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen>
    with WidgetsBindingObserver {
  static const _bottomPadding = 96.0;

  late final MapFocusController _mapFocus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapFocus = context.read<MapFocusController>()..addListener(_showMap);
  }

  // a shop card's «Маршрут»: whatever is open over the shell closes, and the map tab takes over. the
  // map itself flies to the shop - it is the one holding the request
  void _showMap() {
    if (_mapFocus.request == null) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _selected = _ShellTab.map);
  }

  @override
  void dispose() {
    _mapFocus.removeListener(_showMap);
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

  /// Корзина is for customers and admins: the server refuses everybody else, so an owner is not offered it.
  List<_ShellTab> _tabsFor(ProfileViewState profile) => [
    for (final tab in _ShellTab.values)
      if (tab != _ShellTab.cart || profile.seesCart) tab,
  ];

  ShellNavItem _navItem(_ShellTab tab, AppLocalizations strings) =>
      switch (tab) {
        _ShellTab.home => ShellNavItem(
          icon: LucideIcons.house,
          label: strings.homeTab,
        ),
        _ShellTab.cart => ShellNavItem(
          icon: LucideIcons.shopping_cart,
          label: strings.cartTab,
        ),
        _ShellTab.map => ShellNavItem(
          icon: LucideIcons.map_pin,
          label: strings.mapTab,
        ),
        _ShellTab.messages => ShellNavItem(
          icon: LucideIcons.message_square,
          label: strings.messagesTab,
        ),
        _ShellTab.profile => ShellNavItem(
          icon: LucideIcons.user,
          label: strings.profileTab,
        ),
      };

  // built per-frame rather than as a static field: ProfileScreen needs a BuildContext to push
  List<Widget> _buildPages(BuildContext context, _ShellTab current) => [
    const HomeScreen(showScaffold: false, bottomPadding: _bottomPadding),
    // **always in the stack, even for an owner, who simply never sees it.** a page list that changed
    // with the role would shift the map's position and rebuild it from nothing
    WaybillsScreen(
      isActive: current == _ShellTab.cart,
      onExit: () => _selectTab(_ShellTab.home),
    ),
    // IndexedStack builds every child and paints one, so the map cannot tell it is back in view -
    // and it needs to, since its shop list is a snapshot that goes stale. this bool is that signal.
    MapScreen(
      showScaffold: false,
      // nothing to clear: the nav bar is gone while this tab is open - see the note on _buildNavBar
      bottomPadding: 0,
      isActive: current == _ShellTab.map,
      onExit: () => _selectTab(_ShellTab.home),
    ),
    const ChatsScreen(showScaffold: false, bottomPadding: _bottomPadding),
    ProfileScreen(
      showScaffold: false,
      bottomPadding: _bottomPadding,
      onFavoritesTap: () => FavoritesScreen.open(context),
      onAddStoreTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AddStoreScreen())),
      onManageShopTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MyShopsScreen())),
    ),
  ];

  _ShellTab _selected = _ShellTab.home;

  void _selectTab(_ShellTab tab) {
    // **a guest's Профиль is a door, not a tab.** there is no profile to show until there is an
    // account, and registering under the nav bar read as a half-open door - so the tap opens the
    // flow over the shell and leaves the current tab where it was.
    if (tab == _ShellTab.profile &&
        context.read<AuthController>().profileState.isGuest) {
      _openOnboarding();
      return;
    }

    if (_selected == tab) return;

    setState(() {
      _selected = tab;
    });
  }

  /// Lands on Профиль only if an account came out of the flow; a closed one leaves the visitor on
  /// the tab they were reading.
  Future<void> _openOnboarding() async {
    final signedIn = await OnboardingFlow.open(context);
    if (!mounted || !signedIn) return;

    setState(() {
      _selected = _ShellTab.profile;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final tabs = _tabsFor(context.watch<AuthController>().profileState);
    // a customer who opens a shop from under the cart tab: it is gone, so they land on the home screen
    final current = tabs.contains(_selected) ? _selected : _ShellTab.home;
    // the two tabs that run edge to edge and carry a way out of their own - see the nav bar below
    final isFullScreen = current == _ShellTab.map || current == _ShellTab.cart;

    return PopScope(
      // **only a full-screen tab takes the back button off the shell.** everywhere else the shell is
      // the root route and back should still close the app; on these two it is the second way out,
      // beside the button each of them draws.
      canPop: !isFullScreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isFullScreen) _selectTab(_ShellTab.home);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        // **the map and Корзина have no nav bar.** a map is a canvas the user pans and pinches, and a
        // bar floating over its lower third is both in the way and in the way of the controls that
        // belong there; Корзина ends in a pinned «Новая накладная» a floating bar would sit on. Each
        // draws its own way back, and so does the system back gesture - see the PopScope above.
        bottomNavigationBar: isFullScreen
            ? null
            : FloatingBottomNavBar(
                items: [for (final tab in tabs) _navItem(tab, strings)],
                currentIndex: tabs.indexOf(current),
                onItemSelected: (index) => _selectTab(tabs[index]),
              ),
        body: IndexedStack(
          index: current.index,
          children: _buildPages(context, current),
        ),
      ),
    );
  }
}
