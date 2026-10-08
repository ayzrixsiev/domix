import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'product_model.dart';

/// The chips over one shop's grid. [code] mirrors `catalog.IsValidSection` on the backend.
///
/// **Not a [ProductCategory]**: a category is what the home screen browses across every shop, a
/// section only splits one shop's own catalogue. Only the universal template has them so far.
enum ProductSection {
  tapesAbrasives('tapes_abrasives'),
  drillsHandTools('drills_hand_tools'),
  electricalLighting('electrical_lighting'),
  fastenersMounting('fasteners_mounting'),
  mixesPaints('mixes_paints'),
  filmsSheets('films_sheets');

  const ProductSection(this.code);

  final String code;

  static ProductSection? tryFromCode(String code) {
    for (final section in values) {
      if (section.code == code) return section;
    }
    return null;
  }

  String label(AppLocalizations strings) => switch (this) {
    ProductSection.tapesAbrasives => strings.sectionTapesAbrasives,
    ProductSection.drillsHandTools => strings.sectionDrillsHandTools,
    ProductSection.electricalLighting => strings.sectionElectricalLighting,
    ProductSection.fastenersMounting => strings.sectionFastenersMounting,
    ProductSection.mixesPaints => strings.sectionMixesPaints,
    ProductSection.filmsSheets => strings.sectionFilmsSheets,
  };

  /// the whole name, for the sheet - a chip has the short one
  String fullLabel(AppLocalizations strings) => switch (this) {
    ProductSection.tapesAbrasives => strings.sectionFullTapesAbrasives,
    ProductSection.drillsHandTools => strings.sectionFullDrillsHandTools,
    ProductSection.electricalLighting => strings.sectionFullElectricalLighting,
    ProductSection.fastenersMounting => strings.sectionFullFastenersMounting,
    ProductSection.mixesPaints => strings.sectionFullMixesPaints,
    ProductSection.filmsSheets => strings.sectionFullFilmsSheets,
  };

  IconData get icon => switch (this) {
    ProductSection.tapesAbrasives => LucideIcons.disc_3,
    ProductSection.drillsHandTools => LucideIcons.drill,
    ProductSection.electricalLighting => LucideIcons.zap,
    ProductSection.fastenersMounting => LucideIcons.bolt,
    ProductSection.mixesPaints => LucideIcons.paint_bucket,
    ProductSection.filmsSheets => LucideIcons.layers,
  };
}

/// The sections [products] actually use, in chip order.
List<ProductSection> sectionsOf(List<Product> products) {
  final used = {for (final product in products) product.section};
  return [
    for (final section in ProductSection.values)
      if (used.contains(section)) section,
  ];
}

/// [products] grouped by section, catalogue order kept inside each, rows without one last - so
/// «Все товары» reads in the same order as the chips. [only] narrows to a single section.
List<Product> productsBySection(List<Product> products, {ProductSection? only}) {
  if (only != null) {
    return [
      for (final product in products)
        if (product.section == only) product,
    ];
  }
  int rank(Product p) => p.section?.index ?? ProductSection.values.length;
  // List.sort is not stable, so the original position breaks ties
  final indexed = products.indexed.toList()
    ..sort((a, b) {
      final bySection = rank(a.$2).compareTo(rank(b.$2));
      return bySection != 0 ? bySection : a.$1.compareTo(b.$1);
    });
  return [for (final (_, product) in indexed) product];
}
