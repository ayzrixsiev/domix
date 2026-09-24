/// The layout a tab wears when it has **no navigation zone**: no back button, no title that changes
/// with a route, nothing to pop. A big title written straight on the page, and content in bands
/// under it.
///
/// This is the alternative to `AppPageHeader`, not a replacement for it. That header earns its
/// tonal surface on a *pushed* screen, where the eye has to find the way back before it reads
/// anything; on a root tab the same surface reads as a lid bolted onto the page. Both exist and the
/// choice between them is one question - is there navigation in the top of this screen.
///
/// Three pieces, meant to be used together: [PlainPageTitle], [PageBand], [BandRow].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';


/// The page's own title, and the thing every other element on the screen lines up against.
///
/// **It carries the status bar style and the top inset.** Those came free with `AppPageHeader`; a
/// screen that drops the header and forgets them gets white icons on a pale page and a title under
/// the notch. Putting both here means no caller can forget - there is nothing to wrap by hand.
class PlainPageTitle extends StatelessWidget {
  const PlainPageTitle({super.key, required this.title, this.action});

  final String title;

  /// One control opposite the title - the role pill on Заявки. Never a row of them: the point of
  /// this layout is a page that opens with a word, not a toolbar.
  final Widget? action;

  /// Where the content column starts. The title, the band labels and the rows all sit on it - with
  /// no card to hold an edge, this gutter *is* the layout.
  static const double gutter = 20;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 10, gutter, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 28,
                    height: 1.15,
                    letterSpacing: -0.7,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (action case final trailing?) ...[
                const SizedBox(width: 12),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A band of rows on the page: an optional label, a rule under it, the rows, and a closing rule.
///
/// **The rules are [AppColors.trackGrey], not [AppColors.hairline].** Hairline is a border for
/// things drawn on white; against the warm page it is three units away from the background and
/// disappears on a phone in daylight. Track grey is the step *below* the page, which is what a
/// divider lying directly on it has to be.
///
/// A band with no rows still draws itself and says why it is empty - that is how a screen holding
/// one live band admits to the ones it will hold later, instead of looking like the whole feature.
class PageBand extends StatelessWidget {
  const PageBand({
    super.key,
    required this.children,
    this.label,
    this.emptyTitle,
    this.emptyBody,
  });

  final List<Widget> children;

  /// Null on a band that is the only one on its screen - a label over a list of three is a heading
  /// explaining a heading.
  final String? label;

  /// Shown in place of the rows while the band is empty. Null for a band that cannot be empty.
  final String? emptyTitle;
  final String? emptyBody;

  /// Where a divider between two rows starts: past the glyph tile and the gap after it. A line
  /// running the full width cuts the column of tiles in half and makes the band read as a table.
  static const double _textInset = BandRow.tileSize + BandRow.tileGap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label case final heading?) ...[
          Text(
            // upper-cased here rather than in the string: caps are a style, not a translation
            heading.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 11,
              height: 1.2,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
        ],
        const _Rule(),
        if (children.isEmpty)
          _EmptyBand(title: emptyTitle, body: emptyBody)
        else ...[
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const _Rule(indent: _textInset),
            children[i],
          ],
          const _Rule(),
        ],
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: const SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: AppColors.trackGrey),
      ),
    );
  }
}

/// What a band says while it has no rows: centred prose and no illustration. Deliberately not
/// `EmptyStateView` - that widget owns a whole screen and its 96px glyph, and one inside a band
/// with a live band above it would outweigh the content the reader actually has.
class _EmptyBand extends StatelessWidget {
  const _EmptyBand({this.title, this.body});

  final String? title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    if (title == null && body == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 52, 8, 16),
      child: Column(
        children: [
          if (title case final line?)
            Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 15,
                height: 1.3,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (body case final line?) ...[
            const SizedBox(height: 8),
            // capped measure: help text set to the full screen width is hard to read
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One row of a [PageBand]: a tinted glyph tile, a name, a line of what it is, whatever the caller
/// puts on the right, and the chevron that says the row opens something.
///
/// **Written with no idea what its rows mean** - a conversation, a role, a shop - because what must
/// not differ between them is the layout. A list where one row is taller than another looks broken
/// before it is read.
class BandRow extends StatelessWidget {
  const BandRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.subtitleMaxLines = 1,
    this.emphasizeSubtitle = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Two for a message preview, one for a line that describes a fixed thing.
  final int subtitleMaxLines;

  /// Darker and heavier - for a row whose second line is news rather than description.
  final bool emphasizeSubtitle;

  /// Drawn before the chevron: a time, a badge, a status dot.
  final Widget? trailing;

  final VoidCallback onTap;

  static const double tileSize = 44;
  static const double tileGap = 12;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.sm);

    // transparency rather than a colour: the row sits on the page, and a Material painted with the
    // page colour would hide any band rule running under it. ink still paints.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Container(
                width: tileSize,
                height: tileSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: radius),
                child: Icon(icon, size: 20, color: AppColors.primaryOrange),
              ),
              const SizedBox(width: tileGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: emphasizeSubtitle ? AppColors.textDark : AppColors.textGrey,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: emphasizeSubtitle ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ?trailing,
              const SizedBox(width: 4),
              const Icon(LucideIcons.chevron_right, size: 18, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
