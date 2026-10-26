import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'product_model.dart';

/// The groups a shop's «Категории» sheet splits its grid by. [code] mirrors `catalog.IsValidSection`
/// on the backend; the order is the sheet's order, so a template lists its sections together.
///
/// **Not a [ProductCategory]**: a category is what the home screen browses across every shop, a
/// section only splits one shop's own catalogue. The universal and plumbing templates have them.
enum ProductSection {
  tapesAbrasives('tapes_abrasives'),
  drillsHandTools('drills_hand_tools'),
  electricalLighting('electrical_lighting'),
  fastenersMounting('fasteners_mounting'),
  mixesPaints('mixes_paints'),
  filmsSheets('films_sheets'),

  pipesInsulation('pipes_insulation'),
  pprFittings('ppr_fittings'),
  valvesVero('valves_vero'),
  sewer('sewer'),
  threadedFittings('threaded_fittings'),
  ktmFittings('ktm_fittings'),
  valvesKas('valves_kas'),
  cisternToilet('cistern_toilet'),
  siphons('siphons'),
  drains('drains'),
  washingMachine('washing_machine'),
  filtersCartridges('filters_cartridges'),
  mixerParts('mixer_parts'),
  hoses('hoses'),
  mixers('mixers');

  const ProductSection(this.code);

  final String code;

  static ProductSection? tryFromCode(String code) {
    for (final section in values) {
      if (section.code == code) return section;
    }
    return null;
  }

  String fullLabel(AppLocalizations strings) => switch (this) {
    ProductSection.tapesAbrasives => strings.sectionFullTapesAbrasives,
    ProductSection.drillsHandTools => strings.sectionFullDrillsHandTools,
    ProductSection.electricalLighting => strings.sectionFullElectricalLighting,
    ProductSection.fastenersMounting => strings.sectionFullFastenersMounting,
    ProductSection.mixesPaints => strings.sectionFullMixesPaints,
    ProductSection.filmsSheets => strings.sectionFullFilmsSheets,
    ProductSection.pipesInsulation => strings.sectionFullPipesInsulation,
    ProductSection.pprFittings => strings.sectionFullPprFittings,
    ProductSection.valvesVero => strings.sectionFullValvesVero,
    ProductSection.sewer => strings.sectionFullSewer,
    ProductSection.threadedFittings => strings.sectionFullThreadedFittings,
    ProductSection.ktmFittings => strings.sectionFullKtmFittings,
    ProductSection.valvesKas => strings.sectionFullValvesKas,
    ProductSection.cisternToilet => strings.sectionFullCisternToilet,
    ProductSection.siphons => strings.sectionFullSiphons,
    ProductSection.drains => strings.sectionFullDrains,
    ProductSection.washingMachine => strings.sectionFullWashingMachine,
    ProductSection.filtersCartridges => strings.sectionFullFiltersCartridges,
    ProductSection.mixerParts => strings.sectionFullMixerParts,
    ProductSection.hoses => strings.sectionFullHoses,
    ProductSection.mixers => strings.sectionFullMixers,
  };

  IconData get icon => switch (this) {
    ProductSection.tapesAbrasives => LucideIcons.disc_3,
    ProductSection.drillsHandTools => LucideIcons.drill,
    ProductSection.electricalLighting => LucideIcons.zap,
    ProductSection.fastenersMounting => LucideIcons.bolt,
    ProductSection.mixesPaints => LucideIcons.paint_bucket,
    ProductSection.filmsSheets => LucideIcons.layers,
    ProductSection.pipesInsulation => LucideIcons.cylinder,
    ProductSection.pprFittings => LucideIcons.split,
    ProductSection.valvesVero => LucideIcons.circle_gauge,
    ProductSection.sewer => LucideIcons.waves_horizontal,
    ProductSection.threadedFittings => LucideIcons.cog,
    ProductSection.ktmFittings => LucideIcons.unplug,
    ProductSection.valvesKas => LucideIcons.gauge,
    ProductSection.cisternToilet => LucideIcons.toilet,
    ProductSection.siphons => LucideIcons.funnel,
    ProductSection.drains => LucideIcons.grip,
    ProductSection.washingMachine => LucideIcons.washing_machine,
    ProductSection.filtersCartridges => LucideIcons.droplets,
    ProductSection.mixerParts => LucideIcons.wrench,
    ProductSection.hoses => LucideIcons.cable,
    ProductSection.mixers => LucideIcons.shower_head,
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
