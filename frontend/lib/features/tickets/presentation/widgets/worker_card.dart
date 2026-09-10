import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/features/tickets/data/job_ticket.dart';

/// One worker, as a client scrolls past them - and, with [isPreview], as the worker sees their own
/// анкета. **The preview is the same widget, not a mock-up of it**: a form that shows an
/// approximation of your listing lies about the one thing it exists to control.
class WorkerCard extends StatelessWidget {
  const WorkerCard({
    super.key,
    required this.worker,
    required this.strings,
    this.onContact,
    this.isPreview = false,
  });

  final WorkerProfile worker;
  final AppLocalizations strings;

  /// Null on the preview: no sense in offering somebody a button to message themselves.
  final VoidCallback? onContact;

  final bool isPreview;

  @override
  Widget build(BuildContext context) {
    final name = worker.name.of(strings);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
        // the preview is outlined in brand orange so a worker can tell at a glance which of the two cards
        // on that screen is theirs and which is an example
        border: isPreview ? Border.all(color: AppColors.primaryTint, width: 1.4) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(name: name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15.5,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        // an unrated worker gets a word, not a 0.0 next to a star: new is not bad, and a zero rating is the
                        // one number that says the opposite
                        if (worker.isNew)
                          const Icon(LucideIcons.sparkles, size: 13, color: AppColors.accentBlue)
                        else
                          const Icon(LucideIcons.star, size: 13, color: AppColors.starYellow),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            worker.isNew
                                ? strings.newWorkerLabel
                                : '${worker.rating.toStringAsFixed(1)} · ${strings.reviewsCount(worker.reviews)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _AvailabilityDot(availableNow: worker.availableNow, strings: strings),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final skill in worker.skills)
                _SkillChip(icon: skill.icon, label: skill.label(strings)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            worker.about.of(strings),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 11),
          const Divider(height: 1, thickness: 1, color: AppColors.hairline),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${strings.somAmount(worker.priceFrom)} ${strings.perDaySuffix}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14.5,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${worker.district.of(strings)} · ${strings.experienceLabel(worker.experienceYears)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (onContact != null) ...[
                const SizedBox(width: 10),
                _ContactButton(label: strings.contactWorker, onTap: onContact!),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Initials on a tint. **Not a photo**: nobody has uploaded one, and a grey silhouette repeated six
/// times down a list is worse than no picture at all - initials at least differ from each other.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isEmpty ? '?' : name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials,
        style: const TextStyle(
          color: AppColors.primaryOrange,
          fontSize: 15,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// «Свободен» / «Занят» - the single most decision-relevant fact on the card, which is why it sits
/// at the top right where a price would on a product tile.
class _AvailabilityDot extends StatelessWidget {
  const _AvailabilityDot({required this.availableNow, required this.strings});

  final bool availableNow;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final color = availableNow ? AppColors.success : AppColors.textFaint;
    final background = availableNow ? AppColors.successSoft : AppColors.surfaceMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(
            availableNow ? strings.workerAvailable : strings.workerBusy,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined rather than filled: a list of six workers with six orange buttons has six primary
/// actions, which is none.
class _ContactButton extends StatelessWidget {
  const _ContactButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceWhite,
      borderRadius: BorderRadius.circular(AppRadius.sm - 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm - 2),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm - 2),
            border: Border.all(color: AppColors.trackGrey, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.message_square, size: 15, color: AppColors.textDark),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 13,
                  letterSpacing: 0.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
