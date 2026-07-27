import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';

// A real text field, where this used to be a `Text` widget styled to look like one.
//
// The fake version could not be tapped, focused or typed into - it was a picture of a search bar.
// Nothing is searched yet (there is no product search endpoint), so submitting does nothing on
// purpose; what matters is that the control behaves like the thing it looks like.
//
// Stateful because a `TextEditingController` and a `FocusNode` are long-lived objects that must be
// disposed with the widget. A `StatelessWidget` would construct a fresh controller on every
// rebuild, losing the caret position and leaking the old one.
class SearchAndLikeBar extends StatefulWidget {
  const SearchAndLikeBar({super.key});

  static const double _height = 48;

  @override
  State<SearchAndLikeBar> createState() => _SearchAndLikeBarState();
}

class _SearchAndLikeBarState extends State<SearchAndLikeBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: SearchAndLikeBar._height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: _surface,
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.textFaint, size: 19),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.search,
                    cursorColor: AppColors.primaryOrange,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: InputDecoration(
                      // isCollapsed strips the ~48px of default vertical padding a TextField
                      // reserves for a material label. without it the field cannot fit inside a
                      // 48px row and the text sits low instead of centred on the magnifier.
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: strings.searchHint,
                      hintStyle: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    // no product search endpoint yet - the field is real, the query has nowhere to go
                    onSubmitted: (_) {},
                  ),
                ),
                // rebuilds only this button as the text changes, rather than calling setState and
                // rebuilding the whole bar (and the TextField inside it) on every keystroke.
                // ValueListenableBuilder listens to the controller, which *is* a ValueNotifier.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return GestureDetector(
                      onTap: _clear,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.close_rounded, color: AppColors.textFaint, size: 18),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // both halves now share one decoration. previously only the filter button carried a shadow,
        // so the two sat at visibly different depths despite being one control strip.
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () {},
            child: Container(
              height: SearchAndLikeBar._height,
              width: SearchAndLikeBar._height,
              alignment: Alignment.center,
              decoration: _surface,
              child: const Icon(Icons.tune_rounded, color: AppColors.primaryOrange, size: 19),
            ),
          ),
        ),
      ],
    );
  }

  static final BoxDecoration _surface = BoxDecoration(
    color: AppColors.surfaceWhite,
    borderRadius: BorderRadius.circular(AppRadius.sm),
    border: Border.all(color: AppColors.hairline),
    boxShadow: AppShadows.card,
  );
}
