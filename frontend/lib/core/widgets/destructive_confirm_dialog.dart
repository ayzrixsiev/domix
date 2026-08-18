import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The "are you sure?" in front of anything that destroys data and cannot be undone.
///
/// It started life private inside `edit_store_screen.dart` for deleting a shop, and moved here when
/// account deletion needed the identical thing. Copying it would have been three lines of work and
/// the wrong three: two dialogs asking the same question is how one of them ends up with the
/// confirm button on the left, and the one time that matters is the time somebody destroys their
/// catalogue by muscle memory.
///
/// Two rules it encodes, and both are about which way a hurried tap goes wrong:
///
///   - **Cancel is first and cancel is heavier.** The safe choice sits where the thumb rests and
///     reads as the default. Confirm is the red one on the right, which is the side you have to
///     reach for.
///   - **The body names what disappears.** A bare "удалить?" gives the reader nothing to check their
///     intent against, which is precisely the moment people confirm the wrong thing. Callers pass a
///     sentence naming the shop, or the catalogue, or whatever is actually about to go.
///
/// Pops `true` on confirm and `false` on cancel; a tap outside pops nothing, so callers must treat
/// null as a cancel - `confirmed != true`, never `!confirmed`.
class DestructiveConfirmDialog extends StatelessWidget {
  const DestructiveConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    this.icon = CupertinoIcons.trash_fill,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;

  /// Shows the dialog and resolves to whether the user confirmed. Null (dismissed by tapping the
  /// barrier) collapses to false here so callers never have to think about three states.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required String cancelLabel,
    IconData icon = CupertinoIcons.trash_fill,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => DestructiveConfirmDialog(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon,
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.dangerSoft, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.danger, size: 22),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 17,
                height: 1.3,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: cancelLabel,
                    background: AppColors.surfaceMuted,
                    foreground: AppColors.textDark,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DialogButton(
                    label: confirmLabel,
                    background: AppColors.danger,
                    foreground: Colors.white,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontSize: 14.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
