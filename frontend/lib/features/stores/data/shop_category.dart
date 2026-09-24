import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/localization/app_localizations.dart';

// the kind of shop, picked once on the "add store" form and never changed: it decides which
// ready-made catalogue is seeded, and by the time it could be edited that has already been copied
// in. [code] travels over the wire; the ru/uz names live in AppLocalizations.
enum ShopCategory {
  universal('universal', 100),
  plumbing('plumbing', 100),
  wood('wood', 5),
  wallpaper('wallpaper', 10);

  const ShopCategory(this.code, this.templateSize);

  final String code;

  /// how many products a shop of this kind starts with. duplicated from the backend's catalog package
  /// on purpose - it is only shown *before* the shop exists, so there is nothing to fetch it from. if
  /// a template grows, this number has to be updated by hand alongside it.
  final int templateSize;

  /// an unrecognised value falls back to [universal] rather than throwing: a shop row is still
  /// displayable without knowing its category, and a category added on the server before the app is
  /// updated must not crash an old build
  static ShopCategory fromCode(String? code) {
    return tryFromCode(code) ?? ShopCategory.universal;
  }

  /// The same lookup without the fallback, for the one caller where guessing is worse than dropping
  /// the row: defaulting a whole "Лучшие предложения" *tab* to [universal] would merge a fifth
  /// category's shops in and rank them against a basket they were never priced against.
  static ShopCategory? tryFromCode(String? code) {
    for (final category in values) {
      if (category.code == code) return category;
    }
    return null;
  }

  // an exhaustive switch rather than a map: the analyzer flags a missing case, so a fifth category is
  // a compile error instead of a silently untranslated label
  String label(AppLocalizations strings) => switch (this) {
        ShopCategory.universal => strings.shopCategoryUniversal,
        ShopCategory.plumbing => strings.shopCategoryPlumbing,
        ShopCategory.wood => strings.shopCategoryWood,
        ShopCategory.wallpaper => strings.shopCategoryWallpaper,
      };

  String description(AppLocalizations strings) => switch (this) {
        ShopCategory.universal => strings.shopCategoryUniversalHint,
        ShopCategory.plumbing => strings.shopCategoryPlumbingHint,
        ShopCategory.wood => strings.shopCategoryWoodHint,
        ShopCategory.wallpaper => strings.shopCategoryWallpaperHint,
      };

  /// What this kind of shop looks like on the map, inside its pin.
  ///
  /// **Chosen as a set, not one at a time**: all four are ~20px of white stroke on an orange circle,
  /// so what matters is that no two share a silhouette. Judge a candidate by rendering it at 22px,
  /// never by its name - `wallpaper` is a monitor, `logs` is a log *file*, `droplets` is a forecast.
  ///
  /// `wrench_off` requires **flutter_lucide 1.33.0 or newer**. Not `hard_hat`, which marks the
  /// worker role. `tree_pine` and `paint_roller` also mark [ProductCategory] tiles - accepted, since a kind
  /// of *shop* and a kind of *product* never share a surface.
  IconData get icon => switch (this) {
        ShopCategory.universal => LucideIcons.wrench_off,
        ShopCategory.plumbing => LucideIcons.bath,
        ShopCategory.wood => LucideIcons.tree_pine,
        ShopCategory.wallpaper => LucideIcons.paint_roller,
      };
}
