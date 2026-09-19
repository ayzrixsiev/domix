import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/circle_back_button.dart';
import 'package:frontend/core/widgets/screen_header.dart';

// The destination behind the home header's bell. Nothing produces a notification yet, so this is
// permanently empty - but an icon that does nothing when tapped reads as broken, whereas an empty
// list reads as "nothing yet".
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        iconTheme: const IconThemeData(color: AppColors.textDark, size: 22),
        // the disc, not a bare chevron. leadingWidth must move with it or flutter keeps its own 56 and
        // the title sits wrong.
        leading: const CircleBackButton(),
        leadingWidth: CircleBackButton.leadingWidth,
        title: Text(
          strings.notificationsTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        // the same edge the tabs and the category pages draw under their titles
        bottom: ScreenHeader.appBarRule(),
      ),
      body: SafeArea(
        child: EmptyStateView(
          icon: LucideIcons.bell,
          title: strings.noNotifications,
          subtitle: strings.noNotificationsHint,
          // lifted off the bottom edge so the block sits optically centred under the app bar
          bottomInset: 60,
        ),
      ),
    );
  }
}
