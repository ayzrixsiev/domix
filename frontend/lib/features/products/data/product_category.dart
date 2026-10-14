import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/localization/app_localizations.dart';

/// The one list of product categories in the app, shared by the "Популярные категории" grid and the
/// category a shop owner picks on a product.
///
/// [code] crosses the wire into `products.category` and mirrors `ProductCategory` in
/// backend/internal/catalog/categories.go; the ru/uz names live in [label] and never leave the app.
/// The order is the order both the grid and the dropdown render in.
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
  /// Nullable rather than defaulting, unlike `ShopCategory.fromCode`: `products.category` can still
  /// hold free text left over from before migration 000006, and calling such a product "Смеси" would
  /// be inventing a fact. The callers show the raw stored value instead.
  static ProductCategory? tryFromCode(String code) {
    for (final category in values) {
      if (category.code == code) return category;
    }
    return null;
  }

  /// The display name for a stored code, falling back to the code itself when unrecognised - which is
  /// what makes a legacy product still render sensibly. The first time one is edited the fallback
  /// goes away, since the form offers a fixed list.
  static String labelForCode(String code, AppLocalizations strings) =>
      tryFromCode(code)?.label(strings) ?? code;

  // an exhaustive switch, so a thirteenth category is a compile error here rather than a blank label
  // discovered in the running app
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

  /// The product shot the home screen's category tile is built on, or null for a category that has
  /// no artwork yet.
  ///
  /// **Nullable, and that nullability is the rule that picks the grid's categories** (see
  /// [PopularCategoriesGrid]): a tile whose whole design is a photograph cannot fall back to a glyph,
  /// so a category without a shot is not on the grid and is reached through search instead.
  ///
  /// Still an exhaustive switch: a new category has to say here whether it has a photo rather than
  /// silently inheriting a default.
  String? get photo => switch (this) {
        ProductCategory.mixes => 'assets/decorations/categories/building_materials.webp',
        ProductCategory.blocks => null,
        ProductCategory.lumber => 'assets/decorations/categories/lumber.webp',
        ProductCategory.metal => null,
        ProductCategory.fasteners => 'assets/decorations/categories/fasteners.webp',
        ProductCategory.roofing => 'assets/decorations/categories/roofing.webp',
        ProductCategory.insulation => null,
        ProductCategory.electrical => 'assets/decorations/categories/electrical.webp',
        ProductCategory.plumbing => 'assets/decorations/categories/plumbing.webp',
        ProductCategory.paints => 'assets/decorations/categories/paints_and_finishing.webp',
        ProductCategory.finishing => null,
        ProductCategory.tools => 'assets/decorations/categories/tools.webp',
      };

  /// Lucide only, one family and one stroke weight. The glyph belongs on the enum now that two
  /// screens draw the same categories and would otherwise pick different icons for them.
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
