import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/widgets/app_form.dart';

/// The two halves of every sign-in screen: a step's content, and the footer under it. **Shared so
/// the telegram flow and the phone route cannot drift**: the phone route is pushed over the last
/// step, and a footer a few pixels off reads as the button jumping.

/// Clear air under the footer's lowest control, over the system inset.
const double _footerGap = 24;

/// One step's content.
///
/// **The error is drawn here and not in the footer**: in the footer it changed the footer's height,
/// which moved the primary button up and down between steps.
///
/// [body] is for the steps that have something to say. The others are the controls alone, because
/// "выберите язык" above a list of two languages explains nothing the list does not.
///
/// **Centred when it fits, scrolled when it does not**: the minimum height is the viewport's, so two
/// controls centre themselves instead of hanging off the top edge, and the long step and a raised
/// keyboard fall back to an ordinary scroll.
class FlowStepBody extends StatelessWidget {
  const FlowStepBody({
    super.key,
    this.error,
    this.body,
    required this.children,
  });

  /// Already localized, because the thing that produced it knew the error code and this does not.
  final String? error;
  final String? body;
  final List<Widget> children;

  static const _padding = EdgeInsets.fromLTRB(20, 20, 20, 8);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _padding,
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - _padding.vertical,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                AppErrorLine(error!),
                const SizedBox(height: 16),
              ],
              if (body != null) ...[
                Text(
                  body!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// The primary button and, under it, the row for one step back.
///
/// **Both rows are always drawn**, the back one empty on a first step, and the error lives in the
/// scrolling content - otherwise the footer is a different height on every step and the primary
/// button walks up and down the screen. The bottom inset is the system's own plus [_footerGap], so
/// the back button does not sit on the bar the phone draws over it.
///
/// [aside] shares the back row, on its right: a second way forward that must stay clearly below the
/// primary button and must not grow the footer by a row.
class FlowFooter extends StatelessWidget {
  const FlowFooter({
    super.key,
    required this.label,
    required this.onPrimary,
    this.busy = false,
    this.backLabel,
    this.onBack,
    this.aside,
  });

  final String label;
  final VoidCallback onPrimary;
  final bool busy;
  final String? backLabel;

  /// Null draws the row empty, which is what keeps the footer one height.
  final VoidCallback? onBack;
  final Widget? aside;

  @override
  Widget build(BuildContext context) {
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, systemInset + _footerGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppWideButton(
            label: label,
            busy: busy,
            onTap: busy ? null : onPrimary,
          ),
          // the two were touching: a TextButton's own padding is the only thing that was between
          // them, which read as one control with a caption stuck under it
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                if (onBack != null && backLabel != null)
                  TextButton(
                    onPressed: busy ? null : onBack,
                    child: Text(backLabel!, style: flowSecondaryStyle),
                  ),
                if (aside != null)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: aside,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The text of a control under the primary button.
const TextStyle flowSecondaryStyle = TextStyle(
  color: AppColors.textMuted,
  fontSize: 13.5,
  fontWeight: FontWeight.w600,
);
