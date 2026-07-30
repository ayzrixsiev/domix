import 'package:frontend/core/localization/app_localizations.dart';

// the kind of shop, picked once on the "add store" form and never changed afterwards. it decides
// which ready-made product catalogue the backend seeds the new shop with (see
// backend/internal/catalog/templates.go), which is why it can't be edited later: the template has
// already been copied into the shop's products by then.
//
// [code] is what actually travels over the wire and sits in shops.category. the russian/uzbek names
// live in AppLocalizations, so the display language never leaks into the database.
enum ShopCategory {
  universal('universal', 50),
  plumbing('plumbing', 50),
  wood('wood', 10),
  wallpaper('wallpaper', 10);

  const ShopCategory(this.code, this.templateSize);

  final String code;

  /// how many products a shop of this kind starts with. duplicated from the backend's catalog
  /// package on purpose: it is only ever shown as a hint *before* the shop exists ("Готовый
  /// каталог: 50 товаров"), so there is nothing to fetch it from yet, and an endpoint just to
  /// serve four numbers that change once a year is not worth the round trip. if a template grows,
  /// this number has to be updated by hand alongside it.
  final int templateSize;

  /// decodes what the backend sent. an unrecognised value falls back to [universal] rather than
  /// throwing: a shop row is still perfectly displayable if we don't know its category, and a
  /// category added on the server before the app is updated must not crash an old build.
  static ShopCategory fromCode(String? code) {
    for (final category in values) {
      if (category.code == code) return category;
    }
    return ShopCategory.universal;
  }

  // an exhaustive switch rather than a map or an added constructor field: dart's analyzer flags a
  // switch that misses a case, so adding a fifth category makes this a compile error instead of a
  // silently untranslated label - the exact bug that left the home screen's categories in russian.
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
}
