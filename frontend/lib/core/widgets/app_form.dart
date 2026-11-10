import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The pieces every multi-step form in the app is built from: a field's decoration, the label over
/// it, the refusal or the note under it, and the full-width button at the foot.
///
/// **They live here because two flows wear them**: registration and the profile editor ask for the
/// same name and number, and a second copy of an input's border colours is how two screens that must
/// look identical stop looking identical.

/// Filled, hairline-bordered, orange when focused. Used for every free-text field in a form.
InputDecoration appFieldDecoration({required String hint, Widget? prefix}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: BorderSide(color: color),
  );

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: AppColors.textFaint,
      fontWeight: FontWeight.w500,
    ),
    filled: true,
    fillColor: AppColors.surfaceMuted,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(AppColors.hairline),
    enabledBorder: border(AppColors.hairline),
    focusedBorder: border(AppColors.primaryOrange),
    prefixIcon: prefix,
    prefixIconConstraints: prefix == null
        ? null
        : const BoxConstraints(minWidth: 0, minHeight: 0),
  );
}

/// The `+998` in front of a phone field. **Drawn, never typed**: the field takes the nine national
/// digits alone, so there is one spelling to type and nothing to strip.
const Widget appPhonePrefix = Padding(
  padding: EdgeInsets.fromLTRB(14, 0, 8, 0),
  child: Text(
    '+998',
    style: TextStyle(
      color: AppColors.textDark,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
  ),
);

/// What a phone field's own text looks like - wider tracking, so nine digits can be checked against
/// the number in somebody's head.
const TextStyle appPhoneTextStyle = TextStyle(
  color: AppColors.textDark,
  fontSize: 16,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.4,
);

/// `998901234567` as `+998 90 123 45 67`.
///
/// **Grouped rather than raw**: a twelve-digit run is not something a reader can check their own
/// number against at a glance, and every place this number is shown - the profile header, a waybill -
/// is asking them to do exactly that. Anything that is not twelve digits is handed
/// back untouched, since a number we cannot parse is still better shown than hidden.
String formatUzPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 12) return phone;

  return '+${digits.substring(0, 3)} ${digits.substring(3, 5)} '
      '${digits.substring(5, 8)} ${digits.substring(8, 10)} ${digits.substring(10)}';
}

class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textDark,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// A refusal, in danger colours on a tinted strip. Not a SnackBar: it answers the button it sits
/// near and has to stay on screen while the user fixes the field.
class AppErrorLine extends StatelessWidget {
  const AppErrorLine(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.circle_alert,
              size: 16,
              color: AppColors.danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet line under a control: what a choice costs, why something is fixed, or why a door is shut
/// for now. Deliberately not [AppErrorLine]: nothing has gone wrong, and danger colours would read as
/// a mistake the reader has to fix.
class AppNoteLine extends StatelessWidget {
  const AppNoteLine(this.text, {super.key, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A form's primary button: full width, and it holds its own spinner.
///
/// Full width rather than [PrimaryActionButton], which sizes to its label - the one control that is
/// always in the same place on every step of a flow, and a button that changes width with its
/// caption moves under the thumb between steps.
class AppWideButton extends StatelessWidget {
  const AppWideButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final radius = BorderRadius.circular(AppRadius.sm);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: enabled ? AppShadows.accent(AppColors.primaryOrange) : null,
      ),
      child: Material(
        color: enabled ? AppColors.primaryOrange : AppColors.trackGrey,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Center(
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: enabled ? Colors.white : AppColors.textFaint,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
