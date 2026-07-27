import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';

// The destination behind the home header's bell.
//
// Nothing in the app produces a notification yet, so this is permanently empty - but an icon that
// does nothing when tapped reads as broken, whereas an empty list reads as "nothing yet". It uses
// the same nested-layer empty state as the tickets tab and the my-shops list rather than inventing
// a third one, so all three "nothing here" screens look like the same app.
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
        title: Text(
          strings.notificationsTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: AppShadows.card,
                    ),
                    child: const Icon(
                      LucideIcons.bell,
                      color: AppColors.primaryOrange,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  strings.noNotifications,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 17,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  strings.noNotificationsHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
