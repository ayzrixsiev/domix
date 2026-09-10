import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const Color primaryOrange = Color(0xFFFF6F00);
  static const Color primaryDark = Color(0xFF1E1E2C);
  
  // orange used as a *surface* rather than at full strength
  static const Color primarySoft = Color(0xFFFFF3E9);
  static const Color primaryTint = Color(0xFFFFE4CC);

  // Backgrounds - the page sits a real step below a white card, since a shadow soft enough to
  // look premium cannot separate white on near-white by itself
  static const Color background = Color(0xFFEFF1F5);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color cardGrey = Color(0xFFF1F3F6);

  // the neutral ramp every fill, border and divider comes from - no more ad-hoc greys
  static const Color surfaceMuted = Color(0xFFF7F8FA);
  static const Color hairline = Color(0xFFECEEF2);

  // the recessed track a white pill slides along. a step *below* background on purpose: a track
  // lighter than the page reads as a card sitting on top instead of a groove.
  static const Color trackGrey = Color(0xFFE4E7EC);

  // Text
  static const Color textDark = Color(0xFF1A1D1E);
  static const Color textGrey = Color(0xFF8C929D);
  static const Color textFaint = Color(0xFFA9AEB8);
  static const Color textLight = Color(0xFFFFFFFF);

  // the step between textDark and textGrey, for *glyphs* rather than prose. a grid of icons at
  // textDark is the darkest thing on the screen, and textGrey lands under the 3:1 WCAG asks of a
  // non-text mark.
  static const Color textMuted = Color(0xFF646B76);

  // Accents
  static const Color starYellow = Color(0xFFFFB800);
  static const Color accentBlue = Color(0xFF2A85FF);

  // Errors / validation
  static const Color danger = Color(0xFFB42318);
  static const Color dangerSoft = Color(0xFFFEF0EE);
  static const Color success = Color(0xFF0E9F6E);
  static const Color successSoft = Color(0xFFE7F6EF);

  // the middle of a three-state signal - "neither good nor bad". not starYellow: that reads as a
  // highlight and is already spoken for by ratings.
  static const Color warning = Color(0xFFB54708);
  static const Color warningSoft = Color(0xFFFEF6EE);
}
