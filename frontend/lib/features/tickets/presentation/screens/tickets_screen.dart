import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/plain_page.dart';

/// The Заявки tab, held open while the job marketplace waits its turn.
///
/// **The tab stays and the screen goes.** Phase one is shops and customers; workers are phase three,
/// and everything that was here was a fixture in memory rather than a feature. A tab that disappears
/// and comes back moves every other tab twice.
class TicketsScreen extends StatelessWidget {
  const TicketsScreen({super.key, this.showScaffold = true, this.bottomPadding = 36});

  final bool showScaffold;

  /// Room left under the content for the shell's floating nav bar.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    final body = Column(
      children: [
        PlainPageTitle(title: strings.ticketsTab),
        Expanded(
          child: EmptyStateView(
            icon: LucideIcons.clipboard_list,
            title: strings.ticketsComingSoonTitle,
            subtitle: strings.ticketsComingSoonBody,
            bottomInset: bottomPadding,
          ),
        ),
      ],
    );

    if (!showScaffold) return body;
    return Scaffold(backgroundColor: AppColors.background, body: body);
  }
}
