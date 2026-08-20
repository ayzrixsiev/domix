import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/localization/app_localizations.dart';

// the kind of shop, picked once on the "add store" form and never changed afterwards. it decides
// which ready-made product catalogue the backend seeds the new shop with (see
// backend/internal/catalog/templates.go), which is why it can't be edited later: the template has
// already been copied into the shop's products by then.
//
// [code] is what actually travels over the wire and sits in shops.category. the russian/uzbek names
// live in AppLocalizations, so the display language never leaks into the database.
enum ShopCategory {
  universal('universal', 100),
  plumbing('plumbing', 58),
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
    return tryFromCode(code) ?? ShopCategory.universal;
  }

  /// The same lookup without the fallback, for the one caller where guessing would be worse than
  /// dropping the row: the "Лучшие предложения" tabs.
  ///
  /// A shop *row* with an unknown category still renders fine, so defaulting is right there. A
  /// whole tab of shops is different - defaulting an unrecognised category to [universal] would
  /// merge a fifth category's shops into the Универсальный tab and rank them against a basket they
  /// were never priced against. Skipping the group leaves an older app showing four tabs, which is
  /// wrong only by omission.
  static ShopCategory? tryFromCode(String? code) {
    for (final category in values) {
      if (category.code == code) return category;
    }
    return null;
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

  /// What this kind of shop looks like on the map, inside its pin.
  ///
  /// Every pin used to be the same generic building, which meant the map answered "there is a shop
  /// here" and nothing else - a customer hunting for обои had to open pins one at a time to find
  /// out. The glyph turns forty identical markers into four readable groups.
  ///
  /// **Chosen as a set, not one at a time.** All four are ~20px of white stroke on an orange circle,
  /// so what matters is that no two share a silhouette: a spanner, a tub on legs, a conifer and a
  /// roller on a handle are told apart at a glance in a way that four abstract marks are not. Judge
  /// a candidate by rendering it at 22px on the orange circle, never by its name - the pipeline for
  /// that is in CLAUDE.md §8.
  ///
  /// **Three of the four are the founder's pick (2026-08-18), and each overrides an argument that
  /// used to be recorded here.** The thread running through all three: name the *material* the shop
  /// sells, not something adjacent to it.
  /// - `wrench_off` for универсальный, the founder's pick on 2026-08-20, replacing `wrench` (itself
  ///   a replacement for `hammer`, itself a replacement for `store`). **Lucide's name for it is
  ///   literal**: it is the wrench with a diagonal stroke through it, the family's "disabled"
  ///   variant, and the mark that means "no tools" everywhere else it appears. It was picked for
  ///   how it renders rather than for what the name claims - at pin size the stroke reads as a
  ///   second tool laid across the wrench, which is the crossed-tools mark a hardware shop's own
  ///   signage uses. That is the whole case for it, and it is a real one, but the risk is worth
  ///   writing down: a reader who knows the convention reads a prohibition sign.
  ///   Requires `flutter_lucide` **1.33.0 or newer** - 1.11.0, which the app was pinned to, has no
  ///   `wrench_off` at all. The bump is visually a no-op otherwise: every codepoint the app already
  ///   uses is unchanged between the two versions and every glyph renders identically.
  /// - `tree_pine` for древесные материалы, replacing `fence`. The objection on record was that a
  ///   tree is a *landmark* on a map and OSM tiles are full of them - but this glyph is white
  ///   inside an orange teardrop, which no map tile ever is, so that collision is weaker in place
  ///   than it reads on paper. A conifer also says "wood" to someone who has never parsed a picket
  ///   fence as boards.
  /// - `paint_roller` for обои, replacing `scroll`. `scroll` was accurate about the *unit* обои are
  ///   sold in (за рулон) and still had to be explained; a roller is what the trade's own signage
  ///   uses.
  ///
  /// **Known cost, accepted:** two of them still share a glyph with a [ProductCategory] tile on
  /// the home screen - `tree_pine` with Пиломатериалы, `paint_roller` with Краски. (`wrench_off`
  /// no longer collides with Инструменты, which is the one thing the slash buys.) The two lists
  /// mean different things (a kind of *shop* against a kind of *product*) and never appear on the
  /// same surface, so nothing is ambiguous in place. What it costs is that a customer who learns
  /// the home grid first arrives at the map with those two glyphs already meaning something
  /// narrower than the shop they mark.
  ///
  /// Earlier picks and why they failed, kept because the same traps come back:
  /// - **`wallpaper` is a monitor.** Lucide draws it as a screen with a picture in it - the desktop-
  ///   background sense of the word. `swatch_book` (a sample fan) was accurate and still too
  ///   abstract to read at pin size.
  /// - **`logs` is a log *file*** - three lines with bullets, the programmer's sense. There is no
  ///   timber glyph in the family at all, which is what sent древесные материалы through `axe` and
  ///   then `fence` before landing on a tree.
  /// - **`droplets` is a weather forecast.** A tub says сантехника without being told, and `bath`
  ///   is the one of the four that has never moved.
  /// - **Not `hard_hat`** for универсальный - the Заявки tab in the bottom bar already wears that
  ///   one, and the same glyph must not mean "workers" in the nav and "магазин" on the map.
  ///
  /// On the enum for the same reason [label] is: a fifth category becomes a compile error here
  /// rather than a blank pin nobody notices until it is on the map.
  IconData get icon => switch (this) {
        ShopCategory.universal => LucideIcons.wrench_off,
        ShopCategory.plumbing => LucideIcons.bath,
        ShopCategory.wood => LucideIcons.tree_pine,
        ShopCategory.wallpaper => LucideIcons.paint_roller,
      };
}
