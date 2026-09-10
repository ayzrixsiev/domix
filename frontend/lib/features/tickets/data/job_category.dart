import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/localization/app_localizations.dart';

/// The kind of work a ticket asks for, and the trade a worker sells - **one enum for both**, because
/// they are the two ends of the same match and two enums meant to agree eventually will not.
/// Modelled on [ShopCategory]: a stable [code] for the wire, labels in [AppLocalizations], a glyph.
enum JobCategory {
  finishing('finishing'),
  plumbing('plumbing'),
  electric('electric'),
  tiling('tiling'),
  masonry('masonry'),
  carpentry('carpentry');

  const JobCategory(this.code);

  final String code;

  String label(AppLocalizations strings) => switch (this) {
        JobCategory.finishing => strings.jobCategoryFinishing,
        JobCategory.plumbing => strings.jobCategoryPlumbing,
        JobCategory.electric => strings.jobCategoryElectric,
        JobCategory.tiling => strings.jobCategoryTiling,
        JobCategory.masonry => strings.jobCategoryMasonry,
        JobCategory.carpentry => strings.jobCategoryCarpentry,
      };

  IconData get icon => switch (this) {
        JobCategory.finishing => LucideIcons.paint_roller,
        JobCategory.plumbing => LucideIcons.droplets,
        JobCategory.electric => LucideIcons.zap,
        JobCategory.tiling => LucideIcons.grid_2x2,
        JobCategory.masonry => LucideIcons.brick_wall,
        JobCategory.carpentry => LucideIcons.hammer,
      };
}
