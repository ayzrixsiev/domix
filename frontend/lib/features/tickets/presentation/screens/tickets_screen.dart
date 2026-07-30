import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';

// Placeholder for the planned job-ticket marketplace: clients post construction work requests and
// workers or brigades pick them up (see the product vision in CLAUDE.md). It occupies the tab the
// Search screen used to hold - search itself now lives on the map and the home header, so the slot
// was doing nothing, and the roadmap feature is worth a permanent home in the navigation.
//
// Nothing here is wired to a backend yet. It exists so the tab reads as "coming", not "broken" -
// hence the badge, which is what separates an unbuilt screen from a merely empty one.
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
      child: EmptyStateView(
        icon: LucideIcons.hard_hat,
        badge: strings.comingSoonBadge,
        title: strings.ticketsComingSoonTitle,
        subtitle: strings.ticketsComingSoonBody,
        bottomInset: bottomPadding,
      ),
    );

    if (!showScaffold) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(backgroundColor: AppColors.background, body: body);
  }
}
