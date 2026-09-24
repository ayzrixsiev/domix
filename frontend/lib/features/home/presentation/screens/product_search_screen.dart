import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/widgets/product_results_view.dart';
import 'package:frontend/core/widgets/app_page_header.dart';

/// The screen the home search bar opens: a field, and below it every priced product whose name
/// contains every word of the query.
///
/// **A screen rather than an inline field**: the bar used to be a live `TextField` on the home feed
/// with no way to put the keyboard away - nothing there unfocuses on tap and there was no route to
/// pop.
///
/// Nothing is searched until the search key is pressed: as-you-type would turn every keystroke into a
/// request against the api's most expensive read.
class ProductSearchScreen extends StatefulWidget {
  const ProductSearchScreen({super.key});

  /// Mirrors `minSearchWordLen` on the server: one word of three characters, the shortest the search
  /// index can look up. This copy only avoids a doomed round trip.
  static const int minQueryLength = 3;

  /// Mirrors `maxSearchQueryLen`. Enforced at the keyboard: a longer query is a 400 the results screen
  /// could only report as a failed load, with a retry that never works.
  static const int maxQueryLength = 60;

  /// Counted in *characters*: Dart's `String.length` is UTF-16 code units, one per letter for every
  /// alphabet the app ships in, so it agrees with the server's rune count.
  static bool isSearchable(String query) =>
      query.trim().split(RegExp(r'\s+')).any((word) => word.length >= minQueryLength);

  @override
  State<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends State<ProductSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// The query currently on screen, which is **not** what is in the field: the results stay put while
  /// an already-run query is edited, until the search key is pressed again. Null is the prompt state.
  String? _submitted;

  /// Bumped on every search, and the results are keyed on it: a fresh key is what re-runs the load -
  /// see [ProductResultsView].
  int _runs = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// A query too short to run does nothing: the sentence under the magnifier has already said why.
  /// The same text runs again, since pressing search twice is the retry people reach for.
  void _run(String raw) {
    final trimmed = raw.trim();
    if (!ProductSearchScreen.isSearchable(trimmed)) return;

    // dropped before the results draw, so the first screenful is not half-hidden behind a keyboard
    _focusNode.unfocus();
    setState(() {
      _submitted = trimmed;
      _runs++;
    });
  }

  void _clear() {
    _controller.clear();
    // back to the prompt, not to the last results: an empty field over a list of цемент is the field
    // and the page disagreeing about what the screen is showing
    setState(() => _submitted = null);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppPageHeader.custom(
        // the field *is* the title here - there is nothing to call this screen that the field does
        // not already say
        child: _SearchField(
          controller: _controller,
          focusNode: _focusNode,
          hintText: strings.searchHint,
          onSubmitted: _run,
          onClear: _clear,
        ),
      ),
      body: SafeArea(top: false, child: _body(strings)),
    );
  }

  Widget _body(AppLocalizations strings) {
    final home = context.read<HomeController>();
    final query = _submitted;

    if (query == null) {
      // tapping the prompt puts the keyboard away - it is the only large surface while nothing has been
      // searched, so it is where a thumb lands when somebody changes their mind
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            // listens to the field so the hint can change without a setState on every keystroke
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => EmptyStateView(
                icon: LucideIcons.search,
                title: strings.searchPromptTitle,
                // once a character is in, the reason the search key does nothing is the interesting sentence;
                // before that, how to use the screen is
                subtitle: value.text.trim().isEmpty
                    ? strings.searchPromptHint
                    : strings.searchMinLengthHint,
              ),
            ),
          ),
        ),
      );
    }

    return ProductResultsView(
      // a new key per search is what re-runs the load: ProductResultsView fetches from its own initState
      // and holds the result, so a fresh State beats racing a second request inside the old one
      key: ValueKey(_runs),
      strings: strings,
      load: () => home.searchProducts(query),
      // a magnifier rather than a category glyph: the empty state should look like what failed to find
      emptyIcon: LucideIcons.search,
      emptyTitle: strings.searchNoResults,
      emptyHint: strings.searchNoResultsHint,
    );
  }
}

/// The pill the query is typed into: the same shape and height as the home feed's bar, **in the
/// other of that bar's two states**.
///
/// On the feed the bar is a recessed grey well - it is one row of a page, and a white card there
/// would read as the first item of the feed. Here it is the screen: it gets the white fill, the
/// `trackGrey` ring and the soft lift [CircleBackButton] wears, so the two controls beside each
/// other are visibly the same material instead of a white disc glued to a grey slab.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    // the whole well takes the tap, not only the TextField - the magnifier and its padding are ~40px
    // that looks like a button. a tap on the field still goes to the field: the innermost wins.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focusNode.requestFocus,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        // white needs the ring *and* the lift to separate from the page: #EFF1F5 against #FFFFFF is
        // too small a step for a fill alone to read as a raised surface - the same reason the back
        // button has both.
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.trackGrey),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            // the back button's chevron is textDark; the magnifier is one step under it so the two
            // glyphs read as a pair without the field looking like it has a second button in it
            const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                // the user tapped a search bar to get here; asking them to tap a second one asks twice
                autofocus: true,
                // gives the keyboard a "search" key instead of a newline - without it there is no way to submit
                textInputAction: TextInputAction.search,
                textCapitalization: TextCapitalization.sentences,
                // the server's ceiling, applied where it can be seen - see ProductSearchScreen.maxQueryLength
                inputFormatters: [
                  LengthLimitingTextInputFormatter(ProductSearchScreen.maxQueryLength),
                ],
                cursorColor: AppColors.primaryOrange,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                ),
                decoration: InputDecoration(
                  // strips the ~48px of vertical padding a TextField reserves for a material label; without it the
                  // field cannot fit the row and the text sits low instead of centred on the magnifier
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hintText,
                  // textMuted, not the feed bar's textGrey: that shade was picked to sit on the grey
                  // well, and on white it is the palest thing on the screen
                  hintStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                onSubmitted: onSubmitted,
              ),
            ),
            // rebuilds only this button as the text changes, rather than the whole bar and its TextField
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
