import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';

/// The white sheet a list is drawn on, ruled like the paper form: the same object while it is being
/// filled in and when it is read back, so a sent list looks like what was written.
class WaybillSheet extends StatelessWidget {
  const WaybillSheet({
    super.key,
    required this.strings,
    required this.trailingHeading,
    required this.shopsLine,
    required this.rows,
    this.editable = false,
    this.footer,
  });

  final AppLocalizations strings;

  /// Opposite «Накладная»: its number, or the note that it does not have one yet.
  final String trailingHeading;
  final String shopsLine;
  final List<Widget> rows;

  /// Whether the rows carry the column their cross sits in, so the header has to leave room for it.
  final bool editable;
  final Widget? footer;

  /// The column widths every row of a sheet shares. Fixed, so the vertical rules run unbroken from
  /// the header to the last row the way they do on paper.
  static const double numberWidth = 30;
  static const double quantityWidth = 84;
  static const double removeWidth = 30;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      // upper-cased here rather than in the string: caps are a style, not a translation
                      strings.waybillHeading.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 13,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        trailingHeading,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  shopsLine,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _ColumnHeader(strings: strings, editable: editable),
          ...rows,
          ?footer,
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.strings, required this.editable});

  final AppLocalizations strings;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: AppColors.textMuted,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
    );

    return Container(
      height: 34,
      color: AppColors.surfaceMuted,
      child: WaybillRowFrame(
        number: const Text('№', textAlign: TextAlign.center, style: style),
        name: Align(
          alignment: Alignment.centerLeft,
          child: Text(strings.waybillColumnName, style: style),
        ),
        quantity: Align(
          alignment: Alignment.centerLeft,
          child: Text(strings.waybillColumnQuantity, style: style),
        ),
        trailing: editable ? const SizedBox.shrink() : null,
      ),
    );
  }
}

/// One row's cells between the sheet's rules. A row being typed into and one being read differ only in
/// what they put in the cells.
class WaybillRowFrame extends StatelessWidget {
  const WaybillRowFrame({
    super.key,
    required this.number,
    required this.name,
    required this.quantity,
    this.quantityTint,
    this.trailing,
  });

  final Widget number;
  final Widget name;
  final Widget quantity;

  /// A refused cell's background, while the customer fixes it.
  final Color? quantityTint;

  /// Null drops the column altogether, on a sheet being read rather than filled in.
  final Widget? trailing;

  static const _rule = BorderSide(color: AppColors.hairline);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(top: _rule)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: WaybillSheet.numberWidth,
              child: Center(child: number),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(border: Border(left: _rule)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: name,
                ),
              ),
            ),
            Container(
              width: WaybillSheet.quantityWidth,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: quantityTint,
                border: const Border(left: _rule),
              ),
              child: quantity,
            ),
            if (trailing case final widget?)
              SizedBox(width: WaybillSheet.removeWidth, child: widget),
          ],
        ),
      ),
    );
  }
}
