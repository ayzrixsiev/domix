import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The catalogue names offered under the product search field while it is being typed. Tapping one
/// fills the field and runs the real search; the search key still works exactly as it did.
///
/// **It owns the asking, so the screen above it never rebuilds on a keystroke.** Three things keep
/// the traffic down to what the server would see from somebody typing slowly:
/// - the field has to hold a word of three characters, the shortest the catalogue can be looked up on
/// - a keystroke only arms a timer, so a burst of them is one request ([_debounceDelay])
/// - every answer is remembered for the session, so a backspace or a corrected letter is free
///
/// An answer is applied only while the field still holds the query it was asked for, which is what
/// makes a slow reply harmless rather than a list that contradicts the text above it.
class ProductSuggestionsPanel extends StatefulWidget {
  const ProductSuggestionsPanel({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isSearchable,
    required this.suggest,
    required this.onPicked,
    required this.submittedQuery,
  });

  /// the search field's own controller and focus - the panel reads the text and shows itself only
  /// while that field has the keyboard
  final TextEditingController controller;
  final FocusNode focusNode;

  /// the app's "long enough to look up" rule, passed in rather than copied: the screen, the results
  /// screen and the server all answer to the same one
  final bool Function(String query) isSearchable;

  final Future<List<String>> Function(String query) suggest;
  final ValueChanged<String> onPicked;

  /// the query whose results are on screen, if any. the panel hides over them: a list of names on
  /// top of the products they lead to is the same answer twice.
  final String? submittedQuery;

  @override
  State<ProductSuggestionsPanel> createState() =>
      _ProductSuggestionsPanelState();
}

class _ProductSuggestionsPanelState extends State<ProductSuggestionsPanel> {
  /// long enough that a word typed at speed is one request, short enough that a pause to think is
  /// answered before the thumb moves again
  static const _debounceDelay = Duration(milliseconds: 250);

  /// keeps the panel from covering the results it is offered over
  static const _maxPanelHeight = 300.0;

  /// a session's worth of answers - one search is a few dozen at most, each a handful of names
  static const _memoLimit = 40;

  Timer? _debounce;

  /// the query [_names] were looked up for, lowercased
  String _shownQuery = '';
  List<String> _names = const [];

  /// what the last notification carried: a TextEditingController also notifies when only the cursor
  /// moves, and that must not spend a request
  String _lastSeen = '';

  final Map<String, List<String>> _memo = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    // the panel draws only while the field has focus, so a focus change has to rebuild it
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  void _onTextChanged() {
    final query = widget.controller.text.trim();
    if (query == _lastSeen) return;
    _lastSeen = query;

    _debounce?.cancel();

    if (!widget.isSearchable(query)) {
      _forget();
      return;
    }
    if (query.toLowerCase() == _shownQuery) return;

    if (_memo[query.toLowerCase()] case final remembered?) {
      setState(() {
        _names = remembered;
        _shownQuery = query.toLowerCase();
      });
      return;
    }

    // the names already on screen stay while the next answer is on its way, as long as the query is
    // still growing out of theirs: a list that blinks out on every keystroke reads as broken, and a
    // longer query can only ever narrow this one
    if (!query.toLowerCase().startsWith(_shownQuery)) _forget();

    _debounce = Timer(_debounceDelay, () => _fetch(query));
  }

  void _forget() {
    if (_names.isEmpty && _shownQuery.isEmpty) return;
    setState(() {
      _names = const [];
      _shownQuery = '';
    });
  }

  Future<void> _fetch(String query) async {
    List<String> names;
    try {
      names = await widget.suggest(query);
    } catch (e) {
      // **a suggestion that fails says nothing.** it is a convenience over a field that works
      // without it, and an error card under it would report a failure the customer did not ask for
      debugPrint('ProductSuggestionsPanel: suggest failed for "$query": $e');
      return;
    }
    if (!mounted) return;

    _remember(query, names);

    // typed on while it was in flight: this answer is for text the field no longer holds
    if (widget.controller.text.trim() != query) return;

    setState(() {
      _names = names;
      _shownQuery = query.toLowerCase();
    });
  }

  /// People type forward, back one, then forward again, so the query before this one is the one most
  /// likely to be asked for next. Holding the answers makes that round trip free.
  void _remember(String query, List<String> names) {
    if (_memo.length >= _memoLimit) _memo.remove(_memo.keys.first);
    _memo[query.toLowerCase()] = names;
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.controller.text.trim();
    final show =
        widget.focusNode.hasFocus &&
        _names.isNotEmpty &&
        query != widget.submittedQuery &&
        widget.isSearchable(query) &&
        query.toLowerCase().startsWith(_shownQuery);

    return AnimatedSize(
      duration: AppMotion.base,
      curve: AppMotion.easing,
      alignment: Alignment.topCenter,
      // **TextFieldTapRegion is what makes a click on a row reach the row**: on desktop a pointer-down
      // outside the field drops its focus, which hides this panel before the click completes
      child: show
          ? TextFieldTapRegion(child: _card())
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _card() {
    return Container(
      constraints: const BoxConstraints(maxHeight: _maxPanelHeight),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.floating,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: _names.length,
          separatorBuilder: (_, _) => const Divider(
            height: 1,
            thickness: 1,
            // starts under the text, so the glyphs read as one column
            indent: 42,
            color: AppColors.hairline,
          ),
          itemBuilder: (context, index) => _SuggestionRow(
            name: _names[index],
            onTap: () => widget.onPicked(_names[index]),
          ),
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // without this, tapping a row pulls focus off the field, which hides the panel before the
        // tap is delivered - the row would look like it did nothing
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              const Icon(
                LucideIcons.search,
                size: 16,
                color: AppColors.textGrey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
