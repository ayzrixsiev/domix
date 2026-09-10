import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/features/messages/data/support_message.dart';

/// One message in the support conversation. **The user's own sit on the right in brand orange,
/// support's on the left in white**: side is the primary signal and colour the second, because side
/// survives a screenshot, a colourblind reader and bright sun.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.senderLabel,
  });

  final SupportMessage message;

  /// drawn above an incoming message only: nobody needs to be told which of these they wrote
  final String senderLabel;

  @override
  Widget build(BuildContext context) {
    final mine = !message.fromSupport;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          // capped rather than left to fill the row: a bubble that runs the full width stops reading as a
          // bubble, and the ragged right edge is what makes a thread scannable
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
              decoration: BoxDecoration(
                color: mine ? AppColors.primaryOrange : AppColors.surfaceWhite,
                border: mine ? null : Border.all(color: AppColors.hairline),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppRadius.md),
                  topRight: const Radius.circular(AppRadius.md),
                  // the one square-ish corner points at its author, the way every chat draws it
                  bottomLeft: Radius.circular(mine ? AppRadius.md : AppRadius.xs / 2),
                  bottomRight: Radius.circular(mine ? AppRadius.xs / 2 : AppRadius.md),
                ),
                boxShadow: mine ? null : AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!mine) ...[
                    Text(
                      senderLabel,
                      style: const TextStyle(
                        color: AppColors.primaryOrange,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    message.body,
                    style: TextStyle(
                      color: mine ? AppColors.textLight : AppColors.textDark,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _clock(message.sentAt),
                    style: TextStyle(
                      // white at 78% rather than a lighter grey: on orange, any grey either disappears or reads as a
                      // different colour of text
                      color: mine
                          ? AppColors.textLight.withValues(alpha: 0.78)
                          : AppColors.textFaint,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

/// The «Сегодня» / «Вчера» / «12.08.2026» chip between two days of conversation - a support thread
/// is answered over days, so without it two messages a week apart read as one exchange.
class MessageDaySeparator extends StatelessWidget {
  const MessageDaySeparator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.trackGrey,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}
