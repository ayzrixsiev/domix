import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/features/tickets/data/job_ticket.dart';

/// One job, as every role sees it: **the same card in all three feeds, differing only in the button
/// at the bottom**. Three intentions and one set of facts, so three cards would be three chances for
/// the facts to be laid out differently in each.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    required this.strings,
    this.showStatus = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.doneLabel,
    this.isDone = false,
  });

  final JobTicket ticket;
  final AppLocalizations strings;

  /// Only the client's own list shows a status: on somebody else's ticket «Ищем мастера» is not
  /// information, it is the definition of being in the feed at all.
  final bool showStatus;

  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// What the button becomes once it has been pressed. **The control stays on the card instead of
  /// disappearing**, because a row that loses its button on tap reads as one that lost the answer.
  final String? doneLabel;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ticket.category.icon, size: 15, color: AppColors.primaryOrange),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  ticket.category.label(strings),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    letterSpacing: 0.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (showStatus) _StatusBadge(status: ticket.status, strings: strings),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ticket.title.of(strings),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 15.5,
              height: 1.25,
              letterSpacing: -0.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            ticket.description.of(strings),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 11),
          // the facts row: where, when, and how much competition. small and grey on purpose - it is what the
          // eye checks second, after the title has decided whether to care at all.
          Wrap(
            spacing: 12,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Meta(icon: LucideIcons.map_pin, label: ticket.district.of(strings)),
              _Meta(icon: LucideIcons.clock, label: strings.timeAgoLabel(ticket.postedAgo)),
              _Meta(
                icon: LucideIcons.user_round,
                label: strings.responsesCount(ticket.responses),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Divider(height: 1, thickness: 1, color: AppColors.hairline),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.budgetLabel,
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 11,
                        letterSpacing: 0.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      strings.fromAmount(ticket.budgetFrom),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(width: 10),
                // Flexible, not a bare child: a Row hands its non-flex children unbounded width, so a long label
                // («Предложить материалы») sized itself past the card and squeezed the price column to nothing.
                // both sides flex now, and the button shrinks before the card does.
                Flexible(
                  child: _CardAction(
                    label: isDone ? (doneLabel ?? actionLabel!) : actionLabel!,
                    icon: isDone ? LucideIcons.circle_check : actionIcon,
                    onTap: isDone ? null : onAction,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The state pill on a client's own ticket. Colour *and* a word - a colour alone would ask the
/// reader to remember which of three tints means "finished".
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.strings});

  final TicketStatus status;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = status.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        status.label(strings),
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          letterSpacing: 0.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textFaint),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// The compact call to action inside a card - **not [StoreSubmitButton]**, which is a 54px slab built
/// to be the only thing at the bottom of a form. Six of those in a feed would make it a column of
/// buttons with some text between them.
class _CardAction extends StatelessWidget {
  const _CardAction({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData? icon;

  /// Null once the action has been taken: the pill goes quiet - success tint, no shadow, no ripple -
  /// rather than vanishing.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDone = onTap == null;
    final background = isDone ? AppColors.successSoft : AppColors.primaryOrange;
    final foreground = isDone ? AppColors.success : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm - 2),
        boxShadow: isDone ? const [] : AppShadows.accent(AppColors.primaryOrange),
      ),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm - 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm - 2),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: foreground),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      letterSpacing: 0.1,
                      fontWeight: FontWeight.w700,
                    ),
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
