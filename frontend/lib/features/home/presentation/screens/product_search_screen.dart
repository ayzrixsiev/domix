import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/widgets/product_results_view.dart';

/// The screen the home screen's search bar opens: a field at the top, and below it every priced
/// product whose name contains the query, from every shop, cheapest first.
///
/// **A screen rather than an inline field, and that is the fix as much as the feature.** The search
/// bar on the home feed used to be a live `TextField` sitting in the middle of a scroll view.
/// Tapping it raised the keyboard over the feed, and then there was no way to put the keyboard
/// away again: nothing on the home screen unfocuses on tap, the system back button pops routes and
/// there was no route to pop, and the feed simply scrolled underneath it. The user was stuck with
/// a keyboard covering half the app.
///
/// Giving search its own route fixes that by construction. Back - the button or the system gesture
/// - pops the route, and popping a route drops the focus with it; dragging the results dismisses
/// the keyboard on the way; and the home screen no longer owns a focusable control at all.
///
/// **The empty state is the point of the screen today.** There is nothing here until something is
/// searched, and that blank is deliberate: it is where as-you-type results will land. Wiring that
/// up is one change - call [_run] from `onChanged` behind a debounce instead of from `onSubmitted`
/// - and it is not made yet on purpose, because every keystroke past two characters would be an
/// `ILIKE '%q%'` sequential scan (see CLAUDE.md §8) and the shape of that bill is worth knowing
/// before signing it.
class ProductSearchScreen extends StatefulWidget {
  const ProductSearchScreen({super.key});

  /// The shortest query worth sending.
  ///
  /// Mirrors `minSearchQueryLen` in `backend/internal/endpoints/home.go`; the server is the one that
  /// enforces it and this copy only avoids a doomed round trip. One character matches a large share
  /// of the catalogue, so the backend answers 400.
  static const int minQueryLength = 2;

  /// Whether a query is worth running. Trimmed and counted in *characters* - Dart's `String.length`
  /// counts UTF-16 code units, which for Cyrillic is one per letter, so this agrees with the
  /// server's rune count for every alphabet the app ships in.
  static bool isSearchable(String query) => query.trim().length >= minQueryLength;

  @override
  State<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends State<ProductSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// The query currently on screen, which is **not** what is in the field.
  ///
  /// They differ from the moment the user starts editing a query they have already run: the results
  /// below stay put until the search key is pressed again, rather than blanking on the first
  /// keystroke. Null means nothing has been searched yet, which is the prompt state.
  String? _submitted;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Runs the query, if it is long enough to be worth running.
  ///
  /// A query that is too short leaves the field focused and does nothing - the sentence under the
  /// magnifier has already said why, and an error over a user who is mid-word would be noise.
  void _run(String raw) {
    final trimmed = raw.trim();
    if (!ProductSearchScreen.isSearchable(trimmed)) return;
    if (trimmed == _submitted) return;

    // dropped before the results draw, so the first screenful is not half-hidden behind a keyboard
    // the user then has to dismiss by hand. re-focusing to edit the query is one tap on the field.
    _focusNode.unfocus();
    setState(() => _submitted = trimmed);
  }

  void _clear() {
    _controller.clear();
    // back to the prompt, not to the last results. an empty field showing a list of цемент is the
    // field and the page disagreeing about what the screen is showing.
    setState(() => _submitted = null);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // the field wants the whole bar, so the default 16px of title padding beside the leading
        // button goes; the Row below spaces it itself
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: _SearchField(
            controller: _controller,
            focusNode: _focusNode,
            hintText: strings.searchHint,
            onSubmitted: _run,
            onClear: _clear,
          ),
        ),
      ),
      body: SafeArea(top: false, child: _body(strings)),
    );
  }

  Widget _body(AppLocalizations strings) {
    final home = context.read<HomeController>();
    final query = _submitted;

    if (query == null) {
      // tapping the prompt puts the keyboard away, the same way tapping the map does. it is the
      // only large surface on this screen while nothing has been searched, so it is where a thumb
      // lands when somebody changes their mind.
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            // listens to the field so the hint can change under it without this screen calling
            // setState on every keystroke - the same reason the clear button does
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => EmptyStateView(
                icon: LucideIcons.search,
                title: strings.searchPromptTitle,
                // once a character is in, the reason the search key does nothing is the interesting
                // sentence; before that, how to use the screen is
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
      // a new key per query is what re-runs the load. ProductResultsView fetches once from its own
      // initState and holds the result, so changing the query means building a fresh State rather
      // than racing a second request against the first inside the old one.
      key: ValueKey(query),
      strings: strings,
      load: () => home.searchProducts(query),
      // a magnifier rather than a category glyph: there is no category here, and the empty state
      // should look like the thing that failed to find anything
      emptyIcon: LucideIcons.search,
      emptyTitle: strings.searchNoResults,
      emptyHint: strings.searchNoResultsHint,
    );
  }
}

/// The pill the query is typed into. Deliberately the same white surface, radius and hairline as
/// [SearchAndLikeBar] on the home feed, so tapping that one and arriving here reads as the control
/// moving up into the app bar rather than as a different screen with a different field.
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
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.textFaint, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              // the keyboard comes up with the screen. the user tapped a search bar to get here, so
              // making them tap a second one would be asking twice for the same intent.
              autofocus: true,
              // makes the phone's keyboard show a "search" key instead of a newline, which is what
              // fires onSubmitted. without it there is no way to submit from the keyboard at all.
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: AppColors.primaryOrange,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 14.5,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                // isCollapsed strips the ~48px of default vertical padding a TextField reserves for
                // a material label. without it the field cannot fit inside a 42px row and the text
                // sits low instead of centred on the magnifier.
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
              onSubmitted: onSubmitted,
            ),
          ),
          // rebuilds only this button as the text changes, rather than calling setState and
          // rebuilding the whole bar (and the TextField inside it) on every keystroke.
          // ValueListenableBuilder listens to the controller, which *is* a ValueNotifier.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                onTap: onClear,
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
    );
  }
}
