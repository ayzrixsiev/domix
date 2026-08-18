import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/presentation/widgets/product_results_view.dart';

/// A titled page of products drawn from across every shop, cheapest first: what a category tile
/// opens.
///
/// It is an app bar and [ProductResultsView], and that split is the whole of it. Search used to be
/// the second caller of this screen; it now has [ProductSearchScreen], which needs a text field
/// where this has a title and so cannot share the app bar - but shares every state below it.
///
/// It takes a `load` callback rather than a category, which is what lets it stay ignorant of what
/// it is showing. The caller supplies the heading, the empty state and how to fetch; the view owns
/// the three states that fetch can be in.
///
/// Loading and error state live in that view rather than on [HomeController] because this is a
/// screen someone opens, reads and leaves - a failure here must not paint an error over the home
/// screen behind it.
class ProductResultsScreen extends StatefulWidget {
  const ProductResultsScreen({
    super.key,
    required this.title,
    required this.load,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    this.subtitle,
  });

  /// The heading. A category's name.
  final String title;

  /// Shown under the heading until the first load finishes, after which the result count replaces
  /// it - a number that appears out of nowhere a beat after the screen opens reads as a glitch, so
  /// there has to be something in its place from the first frame.
  final String? subtitle;

  final Future<List<CategoryProduct>> Function() load;

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;

  @override
  State<ProductResultsScreen> createState() => _ProductResultsScreenState();
}

class _ProductResultsScreenState extends State<ProductResultsScreen> {
  /// Null until a load lands, and null again if one fails. The app bar shows [widget.subtitle]
  /// while it is null.
  int? _count;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              _count == null
                  ? (widget.subtitle ?? '')
                  : strings.productsCountLabel(_count!),
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: ProductResultsView(
          strings: strings,
          load: widget.load,
          emptyIcon: widget.emptyIcon,
          emptyTitle: widget.emptyTitle,
          emptyHint: widget.emptyHint,
          // setState from a child's callback, which fires after that child's own setState has
          // already scheduled a frame. safe: it lands during the same build phase's callback, not
          // inside build itself.
          onCountChanged: (count) {
            if (mounted) setState(() => _count = count);
          },
        ),
      ),
    );
  }
}
