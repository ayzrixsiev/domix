import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/plain_page.dart';

/// The Сообщения tab, held open while the feature behind it is rebuilt.
///
/// **The tab stays and the chat goes.** The support inbox was removed down to its tables, and it
/// comes back as its own thing - shop conversations included - rather than as a repair of what was
/// there. A tab that disappears and returns moves every other tab twice and teaches the habit
/// twice; a tab that says "скоро" keeps the place it already has.
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({
    super.key,
    this.showScaffold = true,
    this.bottomPadding = 36,
  });

  final bool showScaffold;

  /// Room left under the content for the shell's floating nav bar.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    final body = Column(
      children: [
        PlainPageTitle(title: strings.chatsScreenTitle),
        Expanded(
          child: EmptyStateView(
            icon: LucideIcons.message_square,
            title: strings.chatsComingSoonTitle,
            subtitle: strings.chatsComingSoonBody,
            bottomInset: bottomPadding,
          ),
        ),
      ],
    );

    if (!showScaffold) return body;
    return Scaffold(backgroundColor: AppColors.background, body: body);
  }
}
