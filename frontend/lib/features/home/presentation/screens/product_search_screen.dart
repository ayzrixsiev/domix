import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/pill_search_field.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/widgets/product_results_view.dart';
import 'package:frontend/core/widgets/app_page_header.dart';

/// The screen the home search bar opens: a field, and below it every priced product whose name
/// contains every word of the query.
///
/// **A screen rather than an inline field**: a live `TextField` on the home feed has no way to put the
/// keyboard away - nothing there unfocuses on tap and there is no route to pop.
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
        child: PillSearchField(
          controller: _controller,
          focusNode: _focusNode,
          hint: strings.searchHint,
          // the user tapped a search bar to get here; asking them to tap a second one asks twice
          autofocus: true,
          onSubmitted: _run,
          // the server's ceiling, applied where it can be seen - see maxQueryLength
          inputFormatters: [
            LengthLimitingTextInputFormatter(ProductSearchScreen.maxQueryLength),
          ],
          onClear: _clear,
          clearTooltip: strings.searchClear,
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
