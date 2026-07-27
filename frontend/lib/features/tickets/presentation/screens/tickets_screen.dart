import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';

// Placeholder for the planned job-ticket marketplace: clients post construction work requests and
// workers or brigades pick them up (see the product vision in CLAUDE.md). It occupies the tab the
// Search screen used to hold - search itself now lives on the map and the home header, so the slot
// was doing nothing, and the roadmap feature is worth a permanent home in the navigation.
//
// Nothing here is wired to a backend yet. It exists so the tab reads as "coming", not "broken".
class TicketsScreen extends StatelessWidget {
  const TicketsScreen({
    super.key,
    this.showScaffold = true,
    this.bottomPadding = 36,
  });

  final bool showScaffold;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    final body = SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 0, 32, bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // the same nested-layer treatment the my-shops empty state uses, so "nothing here
              // yet" looks like a designed state rather than an unfinished screen
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
                    LucideIcons.hard_hat,
                    color: AppColors.primaryOrange,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  strings.comingSoonBadge,
                  style: const TextStyle(
                    color: AppColors.primaryOrange,
                    fontSize: 11,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.ticketsComingSoonTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 17,
                  height: 1.3,
                  letterSpacing: -0.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  strings.ticketsComingSoonBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!showScaffold) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(backgroundColor: AppColors.background, body: body);
  }
}
