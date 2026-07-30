import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';

// Placeholder for the messaging feature: nothing in the app can start a conversation yet, so this
// tab has nothing to list.
//
// It used to be a single line of grey text floating in the middle of the page, which read as an
// unfinished screen rather than a designed one - the tab looked broken next to Заявки and
// Уведомления, which both had the layered empty state. It now uses the same EmptyStateView they do,
// with the "Скоро" badge, since like the tickets tab this is a feature that is not built rather than
// a list that happens to be empty.
//
// The glyph is LucideIcons.message_square, the same one the Messages tab draws in the bottom bar -
// arriving somewhere should feel like arriving at the thing you tapped.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key, this.showScaffold = true, this.bottomPadding = 36});

  final bool showScaffold;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    final body = SafeArea(
      child: EmptyStateView(
        icon: LucideIcons.message_square,
        badge: strings.comingSoonBadge,
        title: strings.messagesComingSoonTitle,
        subtitle: strings.messagesComingSoonBody,
        bottomInset: bottomPadding,
      ),
    );

    if (!showScaffold) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(backgroundColor: AppColors.background, body: body);
  }
}
