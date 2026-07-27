import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/app_shell/presentation/widgets/floating_bottom_nav_bar.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/map/presentation/screens/map_screen.dart';
import 'package:frontend/features/messages/presentation/screens/messages_screen.dart';
import 'package:frontend/features/profile/presentation/screens/profile_screen.dart';
import 'package:frontend/features/tickets/presentation/screens/tickets_screen.dart';
import 'package:frontend/features/stores/presentation/screens/add_store_screen.dart';
import 'package:frontend/features/stores/presentation/screens/my_shops_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  static const _bottomPadding = 96.0;

  List<ShellNavItem> _buildNavItems(AppLocalizations strings) => [
    ShellNavItem(icon: LucideIcons.house, label: strings.homeTab),
    // the job-ticket marketplace takes the slot search used to hold: search now lives on the map
    // and the home header, and a hard hat says "workers" faster than any other glyph here
    ShellNavItem(icon: LucideIcons.hard_hat, label: strings.ticketsTab),
    ShellNavItem(icon: LucideIcons.map_pin, label: strings.mapTab),
    ShellNavItem(icon: LucideIcons.message_square, label: strings.messagesTab),
    ShellNavItem(icon: LucideIcons.user, label: strings.profileTab),
  ];

  // built per-frame (like _buildNavItems below) rather than as a static field, since ProfileScreen
  // needs a BuildContext to navigate to AddStoreScreen when its "add store" row is tapped
  List<Widget> _buildPages(BuildContext context) => [
    const HomeScreen(showScaffold: false, bottomPadding: _bottomPadding),
    const TicketsScreen(showScaffold: false, bottomPadding: _bottomPadding),
    const MapScreen(showScaffold: false, bottomPadding: _bottomPadding),
    const MessagesScreen(showScaffold: false, bottomPadding: _bottomPadding),
    ProfileScreen(
      showScaffold: false,
      bottomPadding: _bottomPadding,
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
    if (_currentIndex == index) return;

    setState(() {
      _currentIndex = index;
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
