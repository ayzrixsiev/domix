import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/presentation/widgets/product_results_view.dart';
import 'package:frontend/features/home/presentation/screens/product_search_screen.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';

/// A titled page of products from across every shop - what a category tile opens: an app bar and
/// [ProductResultsView], and that split is the whole of it.
///
/// It takes a `load` callback rather than a category, which keeps it ignorant of what it is showing.
/// Loading and error state live in the view, so a failure cannot reach the home screen behind it.
class ProductResultsScreen extends StatefulWidget {
  const ProductResultsScreen({
    super.key,
    required this.title,
    required this.load,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    this.subtitle,
    this.onSearch,
  });

  /// The heading. A category's name.
  final String title;

  /// shown under the heading until the first load finishes, after which the result count replaces it
  /// - a number appearing out of nowhere a beat after the screen opens reads as a glitch
  final String? subtitle;

  final Future<List<CategoryProduct>> Function() load;

  /// Searches **every** category, for the field in the app bar.
  ///
  /// Optional: without it the field only narrows what [load] returned. With it, pressing the search
  /// key leaves the category entirely - which is the point of having a field on a category page at
  /// all, since a user who knows the product name should not have to guess which tile it lives under.
  final Future<List<CategoryProduct>> Function(String query)? onSearch;

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;

  @override
  State<ProductResultsScreen> createState() => _ProductResultsScreenState();
}

class _ProductResultsScreenState extends State<ProductResultsScreen> {
  /// Null until a load lands, and null again if one fails; the app bar shows [widget.subtitle] then.
  int? _count;

  final TextEditingController _filter = TextEditingController();

  /// What the field currently holds. Held here rather than read off the controller at build time so
  /// that [ProductResultsView] is rebuilt with a new `query` on every keystroke.
  String _typed = '';

  /// The query whose **catalogue-wide** results are on screen, or null while this is still the
  /// category's own list. Not the same as [_typed]: the field can be edited without re-running the
  /// search, exactly as on [ProductSearchScreen].
  String? _submitted;

  /// Bumped per search so the results view is re-keyed, which is what re-runs its load.
  int _runs = 0;

  /// Whether the field has taken the title's place - see [_openSearch].
  bool _searching = false;

  final FocusNode _filterFocus = FocusNode();

  @override
  void dispose() {
    _filter.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  /// **The field is not on the header until it is asked for.** A category page opens to say which
  /// category it is, and a search bar permanently parked under that title is a control taking a
  /// quarter of the navigation zone to do nothing on arrival. The magnifier trades places with the
  /// title instead: one tap, the heading steps aside, the field is already focused.
  void _openSearch() {
    setState(() => _searching = true);
    // after the frame: the node has no attached field until this build lands
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _filterFocus.requestFocus();
    });
  }

  /// Back to the title, and back to the category - a field being put away has nothing left to say
  /// about what is on screen.
  void _closeSearch() {
    _filterFocus.unfocus();
    // a catalogue-wide search is a different list under a different view key: closing it reloads the
    // category, which reports its own count. a local filter never left the category, so the count it
    // had is still about the right list until the view recomputes it - nulling it there would blank
    // the subtitle of a screen nothing had changed.
    final wasCatalogueWide = _submitted != null;
    _filter.clear();
    setState(() {
      _searching = false;
      _typed = '';
      _submitted = null;
      if (wasCatalogueWide) _count = null;
    });
  }

  /// Leaves the category and searches the whole catalogue.
  ///
  /// **On the search key, never per keystroke** - this one is a request against the api's most
  /// expensive read, which is the same reason [ProductSearchScreen] waits for it. The live narrowing
  /// as you type is the free half; this is the half that costs something.
  void _search(String raw) {
    final trimmed = raw.trim();
    // too short for the server's index to answer - the local narrowing is already showing what it can
    if (!ProductSearchScreen.isSearchable(trimmed)) return;

    _filterFocus.unfocus();
    setState(() {
      _submitted = trimmed;
      // the field collapses back into a title, which now names the query rather than the category -
      // the keyboard is gone, the results have the screen, and the header still says what they are
      _searching = false;
      _runs++;
      _count = null;
    });
  }

  /// Back to the category's own list, with the field still up - the × inside the field empties it,
  /// the × on the header puts it away.
  void _clearSearch() {
    _filter.clear();
    setState(() {
      _typed = '';
      _submitted = null;
      _count = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _searching
          ? AppPageHeader.custom(
              // keyed, or the header sees one CircleIconButton throughout and swaps the glyph
              // without the cross-fade the title beside it is getting
              action: CircleIconButton(
                key: const ValueKey('close-search'),
                icon: Icons.close_rounded,
                tooltip: strings.cancelButton,
                onTap: _closeSearch,
              ),
              child: _FilterField(
                controller: _filter,
                focusNode: _filterFocus,
                hint: strings.categoryFilterHint,
                onChanged: (value) => setState(() => _typed = value),
                onSubmitted: widget.onSearch == null ? null : _search,
                onClear: _clearSearch,
              ),
            )
          : AppPageHeader(
              // after a catalogue-wide search the heading is the query: the results are no longer
              // this category's, and leaving "Смеси" over them would be a false claim
              title: _submitted ?? widget.title,
              subtitle: _submitted != null
                  ? (_count == null
                        ? strings.searchAcrossCategories
                        : '${strings.searchAcrossCategories} · ${strings.productsCountLabel(_count!)}')
                  : (_count == null
                        ? widget.subtitle
                        : strings.productsCountLabel(_count!)),
              // a magnifier while there is nothing to undo, an × once the screen is showing the
              // answer to a search - one control, saying the only thing there is to do next
              action: _submitted == null
                  ? CircleIconButton(
                      key: const ValueKey('open-search'),
                      icon: Icons.search_rounded,
                      tooltip: strings.searchHint,
                      onTap: _openSearch,
                    )
                  : CircleIconButton(
                      key: const ValueKey('close-search'),
                      icon: Icons.close_rounded,
                      tooltip: strings.cancelButton,
                      onTap: _closeSearch,
                    ),
            ),
      body: SafeArea(
        top: false,
        child: ProductResultsView(
          // a fresh key is what re-runs the load: the view fetches from its own initState and holds
          // the result, so a new State beats racing a second request inside the old one
          key: ValueKey(_submitted == null ? 'category' : 'search-$_runs'),
          strings: strings,
          load: _submitted == null
              ? widget.load
              : () => widget.onSearch!(_submitted!),
          // catalogue-wide results are not narrowed again by the text still sitting in the field -
          // they already are its answer
          query: _submitted == null ? _typed : '',
          canSearchWider: widget.onSearch != null,
          emptyIcon: widget.emptyIcon,
          emptyTitle: widget.emptyTitle,
          emptyHint: widget.emptyHint,
          // safe: this lands during the child's own post-setState callback, not inside build itself
          onCountChanged: (count) {
            if (mounted) setState(() => _count = count);
          },
        ),
      ),
    );
  }
}

/// The filter over a category's products.
///
/// **A live field, unlike the home screen's search bar**, which is a button that opens a screen. The
/// difference is what each one costs: that one runs a query against the api's most expensive read,
/// so it waits for the search key; this one walks a list already in memory, so waiting for anything
/// would only make it feel slow.
class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;

  /// Held by the screen, which focuses it the frame after the magnifier opens this.
  final FocusNode focusNode;

  final String hint;
  final ValueChanged<String> onChanged;

  /// null when this screen has no catalogue-wide search to offer, which leaves the field a pure filter
  final ValueChanged<String>? onSubmitted;

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    // the home feed's search bar exactly - same height, radius, white fill and ring - since this is
    // the same gesture arriving one screen deeper
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.trackGrey),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              // focus is given by the screen rather than by `autofocus`, because this field is not in
              // the tree until the magnifier puts it there - and when it is, it was asked for
              textCapitalization: TextCapitalization.sentences,
              // gives the keyboard a "search" key rather than a newline - without it there is no way
              // to ask for the wider search at all
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              cursorColor: AppColors.primaryOrange,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                // strips the ~48px a TextField reserves for a material label, which this row cannot fit
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          // rebuilds only this button as the text changes, rather than the field beside it
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                key: const ValueKey('clear-filter'),
                behavior: HitTestBehavior.opaque,
                // clears the text *and* drops back out of a catalogue-wide search into the category
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close_rounded, color: AppColors.textMuted, size: 17),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
