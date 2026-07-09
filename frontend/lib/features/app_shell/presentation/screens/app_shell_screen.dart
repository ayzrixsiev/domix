import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/features/app_shell/presentation/widgets/floating_bottom_nav_bar.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/profile/presentation/screens/profile_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  static const _bottomPadding = 124.0;

  static const _navItems = [
    ShellNavItem(icon: LucideIcons.house, label: 'Главная'),
    ShellNavItem(icon: LucideIcons.user, label: 'Профиль'),
  ];

  final _pages = const [
    HomeScreen(showScaffold: false, bottomPadding: _bottomPadding),
    ProfileScreen(showScaffold: false, bottomPadding: _bottomPadding),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      bottomNavigationBar: FloatingBottomNavBar(
        items: _navItems,
        currentIndex: _currentIndex,
        onItemSelected: _selectTab,
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),
    );
  }
}
