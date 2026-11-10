import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The one-time sign-in code, drawn as one box per digit.
///
/// **Six boxes over one field, not six fields.** pasting, the keyboard's autofill suggestion and a
/// held backspace all arrive as a single edit against a single value, so the boxes are decoration
/// over one hidden [TextField] - which is also what makes [AutofillHints.oneTimeCode] work at all.
///
/// **Nothing is submitted here**: «Подтвердить» spends the attempt, because a code that verifies
/// itself as the sixth digit lands gives the reader no moment to check what they typed.
class CodeInputField extends StatefulWidget {
  const CodeInputField({
    super.key,
    required this.controller,
    this.onChanged,
    this.length = 6,
    this.autofocus = true,
  });

  /// Owned by the flow, which also clears it on «Изменить номер» and on a resend.
  final TextEditingController controller;

  /// Fired on every edit - the flow clears its error line on the first keystroke after a refusal.
  final ValueChanged<String>? onChanged;

  final int length;
  final bool autofocus;

  @override
  State<CodeInputField> createState() => _CodeInputFieldState();
}

class _CodeInputFieldState extends State<CodeInputField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // the active box is only lit while the keyboard is up, so the row does not sit there pretending
    // to be waiting for a digit after the field has been dismissed
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  /// The gap between two boxes.
  static const double _gap = 8;

  /// Tall enough that the row reads as six fields rather than six chips, and the same height as the
  /// flow's other inputs.
  static const double _boxHeight = 58;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) => _boxes(value.text),
        ),
        // the field itself: invisible, and stretched over the whole row so a tap on any box opens
        // the keyboard
        Positioned.fill(child: _hiddenField()),
      ],
    );
  }

  Widget _boxes(String code) {
    return Row(
      children: [
        for (var index = 0; index < widget.length; index++) ...[
          if (index > 0) const SizedBox(width: _gap),
          Expanded(
            child: _CodeBox(
              digit: index < code.length ? code[index] : null,
              // the box the next digit will land in, which is one past the last one typed
              isActive: _focusNode.hasFocus && index == code.length,
              height: _boxHeight,
            ),
          ),
        ],
      ],
    );
  }

  Widget _hiddenField() {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(widget.length),
      ],
      // the boxes draw the digits; this field only has to hold the value and take the taps. the
      // caret and the selection handles go with the glyphs, or they would float over the boxes with
      // no text under them.
      showCursor: false,
      enableInteractiveSelection: false,
      style: const TextStyle(color: Colors.transparent, fontSize: 1, height: 1),
      decoration: const InputDecoration(
        border: InputBorder.none,
        isCollapsed: true,
        counterText: '',
      ),
      onChanged: (value) {
        // a tap lands the caret wherever it lands, and in an invisible field that is a digit
        // inserted where the eye sees nothing. typing is always at the end here.
        widget.controller.selection = TextSelection.collapsed(
          offset: value.length,
        );
        widget.onChanged?.call(value);
      },
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.digit,
    required this.isActive,
    required this.height,
  });

  final String? digit;
  final bool isActive;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // a filled box goes white: the row then shows at a glance how much of the code is in
        color: digit == null ? AppColors.surfaceMuted : AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isActive ? AppColors.primaryOrange : AppColors.hairline,
          width: isActive ? 1.6 : 1,
        ),
      ),
      child: Text(
        digit ?? '',
        style: const TextStyle(
          color: AppColors.textDark,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
