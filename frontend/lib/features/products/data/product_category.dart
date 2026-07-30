import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/localization/app_localizations.dart';

/// The one list of product categories in the app.
///
/// It is deliberately shared by two things that used to have nothing to do with each other: the
/// "Популярные категории" grid on the home screen, and the category a shop owner picks when adding
/// or editing a product. Before this, the grid had eight hardcoded labels while a product's category
/// was free text typed into a box - so "Крепёж" the tile and "крепеж" the typed string were
/// unrelated values that only looked alike, and no home tile could ever have been wired to real
/// products.
///
/// [code] is what actually crosses the wire and lands in `products.category`; it mirrors
/// `ProductCategory` in backend/internal/catalog/categories.go one for one. The Russian/Uzbek names
/// live in [label] and never leave the app, which is why switching the app to Uzbek now translates
/// a product's category - it used to stay Russian, because the Russian word *was* the stored value.
///
/// The order here is the order both the grid and the dropdown render in: roughly the order of a
/// build, structure first and finishes last.
enum ProductCategory {
  mixes('mixes'),
  blocks('blocks'),
  lumber('lumber'),
  metal('metal'),
  fasteners('fasteners'),
  roofing('roofing'),
  insulation('insulation'),
  electrical('electrical'),
  plumbing('plumbing'),
  paints('paints'),
  finishing('finishing'),
  tools('tools');

  const ProductCategory(this.code);

  /// the locale-neutral value stored in the database and sent to the backend
  final String code;

  /// The category for a stored code, or null if it isn't one of ours.
  ///
  /// Nullable rather than falling back to a default, unlike `ShopCategory.fromCode`: a shop always
  /// has one of four valid categories because the database constrains the column, whereas
  /// `products.category` can still hold free text left over from before migration 000006. Silently
  /// calling such a product "Смеси" would be inventing a fact; the callers below show the raw stored
  /// value instead, which is at least true.
  static ProductCategory? tryFromCode(String code) {
    for (final category in values) {
      if (category.code == code) return category;
    }
    return null;
  }

  /// The display name for a stored code, falling back to the code itself when it is unrecognised.
  ///
  /// This is what makes a legacy product still render sensibly: a row created before the shared
  /// vocabulary existed holds something like "Крепёж", and showing that beats showing nothing. The
  /// first time such a product is edited the fallback goes away, since the form offers a fixed list.
  static String labelForCode(String code, AppLocalizations strings) =>
      tryFromCode(code)?.label(strings) ?? code;

  // an exhaustive switch, so adding a thirteenth category is a compile error in this file rather
  // than a blank label discovered in the running app. same reason ShopCategory does it this way.
  String label(AppLocalizations strings) => switch (this) {
        ProductCategory.mixes => strings.categoryMixes,
        ProductCategory.blocks => strings.categoryBlocks,
        ProductCategory.lumber => strings.categoryLumber,
        ProductCategory.metal => strings.categoryMetal,
        ProductCategory.fasteners => strings.categoryFasteners,
        ProductCategory.roofing => strings.categoryRoofing,
        ProductCategory.insulation => strings.categoryInsulation,
        ProductCategory.electrical => strings.categoryElectrical,
        ProductCategory.plumbing => strings.categoryPlumbing,
        ProductCategory.paints => strings.categoryPaints,
        ProductCategory.finishing => strings.categoryFinishing,
        ProductCategory.tools => strings.categoryTools,
      };

  /// Lucide only, one family and one stroke weight - see PopularCategoriesGrid's note on why the
  /// Hugeicons pass was reverted. The glyph belongs on the enum rather than in the grid widget now
  /// that two screens draw the same categories and would otherwise pick different icons for them.
  IconData get icon => switch (this) {
        ProductCategory.mixes => LucideIcons.container,
        ProductCategory.blocks => LucideIcons.brick_wall,
        ProductCategory.lumber => LucideIcons.tree_pine,
        ProductCategory.metal => LucideIcons.columns_3,
        ProductCategory.fasteners => LucideIcons.bolt,
        ProductCategory.roofing => LucideIcons.house,
        ProductCategory.insulation => LucideIcons.layers,
        ProductCategory.electrical => LucideIcons.zap,
        ProductCategory.plumbing => LucideIcons.droplets,
        ProductCategory.paints => LucideIcons.paint_roller,
        ProductCategory.finishing => LucideIcons.grid_2x2,
        ProductCategory.tools => LucideIcons.wrench,
      };
}
