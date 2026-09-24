import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/app_page_header.dart';

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
      appBar: AppPageHeader(title: strings.notificationsTitle),
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
