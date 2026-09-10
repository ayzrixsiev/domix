import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/presentation/widgets/product_results_view.dart';
import 'package:frontend/core/widgets/circle_back_button.dart';

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
  });

  /// The heading. A category's name.
  final String title;

  /// shown under the heading until the first load finishes, after which the result count replaces it
  /// - a number appearing out of nowhere a beat after the screen opens reads as a glitch
  final String? subtitle;

  final Future<List<CategoryProduct>> Function() load;

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;

  @override
  State<ProductResultsScreen> createState() => _ProductResultsScreenState();
}

class _ProductResultsScreenState extends State<ProductResultsScreen> {
  /// Null until a load lands, and null again if one fails; the app bar shows [widget.subtitle] then.
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
        leading: const CircleBackButton(),
        leadingWidth: CircleBackButton.leadingWidth,
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
          // safe: this lands during the child's own post-setState callback, not inside build itself
          onCountChanged: (count) {
            if (mounted) setState(() => _count = count);
          },
        ),
      ),
    );
  }
}
