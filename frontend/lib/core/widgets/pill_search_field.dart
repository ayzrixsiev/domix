import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// **The app's one search field**: a white capsule, a magnifier, a cross once there is text. Every
/// screen that searches wears this and nothing else.
///
/// [floating] is the same split `CircleIconButton` and `SegmentedTabs` make: over map tiles it takes a
/// hairline, the heavier shadow and darker glyphs, because the grey that reads as "placeholder" on the
/// page reads as "disabled" over a street.
///
/// **The whole capsule takes the tap, not only the TextField**: the magnifier is ~40px that looks like
/// a button, and a field that ignores its own icon is the whole of "the search does not work".
class PillSearchField extends StatefulWidget {
  const PillSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.clearTooltip,
    this.autofocus = false,
    this.floating = false,
    this.height,
    this.inputFormatters,
    this.trailing,
  });

  final TextEditingController controller;
  final String hint;

  /// passed only when the screen itself has to move focus about; otherwise the field owns one
  final FocusNode? focusNode;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// replaces the built-in clear, for a screen whose clear means more than emptying the field
  final VoidCallback? onClear;

  /// what a screen reader says on the cross, which has no label of its own
  final String? clearTooltip;

  final bool autofocus;

  /// Hovering over a map rather than sitting on the page - see the note above.
  final bool floating;

  /// defaults to [pageHeight] / [floatingHeight]. Passed where the field shares a line with a disc
  /// and has to match it exactly.
  final double? height;

  final List<TextInputFormatter>? inputFormatters;

  /// a spinner or a submit arrow where the clear cross would be - the two map screens need one.
  /// **It takes the cross's place rather than sitting beside it**: two controls in a 40px corner is
  /// one tap target missed every time.
  final Widget? trailing;

  /// the height of every other input on a page
  static const double pageHeight = 48;

  /// two points taller over a map: it is the only thing on screen competing with the tiles
  static const double floatingHeight = 50;

  @override
  State<PillSearchField> createState() => _PillSearchFieldState();
}

class _PillSearchFieldState extends State<PillSearchField> {
  /// null whenever the caller passed its own - [_focusNode] picks between them, and dispose only
  /// touches what this state made
  FocusNode? _owned;

  FocusNode get _focusNode => widget.focusNode ?? (_owned ??= FocusNode());

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final floating = widget.floating;

    return GestureDetector(
      // opaque, so the padding and the magnifier focus the field too. a tap on the TextField still
      // goes to the TextField: the innermost hit wins.
      behavior: HitTestBehavior.opaque,
      onTap: _focusNode.requestFocus,
      child: Container(
        height: widget.height ??
            (floating ? PillSearchField.floatingHeight : PillSearchField.pageHeight),
        // wider on the left than a rounded rectangle needed: at a capsule's radius a glyph 14px in
        // sits on the curve rather than beside it
        padding: const EdgeInsets.only(left: 18, right: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(999),
          // over a map the field and the discs either side of it read as one bar only if none of
          // them is a different kind of object, so it takes the same hairline and lift they do. on
          // the page it is flat: that shadow pooled in the capsule's corners and read as a grey backing
          border: floating ? Border.all(color: AppColors.hairline) : null,
          boxShadow: floating ? AppShadows.floating : null,
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.search,
              color: floating ? AppColors.textDark : AppColors.textMuted,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                inputFormatters: widget.inputFormatters,
                // gives the keyboard a "search" key instead of a newline
                textInputAction: TextInputAction.search,
                textCapitalization: TextCapitalization.sentences,
                cursorColor: AppColors.primaryOrange,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  // strips the ~48px of vertical padding a TextField reserves for a material label;
                  // without it the text sits low instead of centred on the magnifier
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    color: floating ? AppColors.textMuted : AppColors.textGrey,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            if (widget.trailing case final trailing?)
              trailing
            else
              // rebuilt off the field itself, so a keystroke does not rebuild the screen under it
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  // a 36px box around an 18px glyph: a cross the size of its own ink is a tap
                  // target nobody hits, and the box is where the gap before it comes from too
                  final cross = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClear ?? _clear,
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(LucideIcons.x, color: AppColors.textMuted, size: 18),
                    ),
                  );
                  return widget.clearTooltip == null
                      ? cross
                      : Tooltip(message: widget.clearTooltip!, child: cross);
                },
              ),
          ],
        ),
      ),
    );
  }
}
