import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const Color primaryOrange = Color(0xFFFF6F00);
  static const Color primaryDark = Color(0xFF2A2320);
  
  // one step under primaryOrange, for a glyph that has to stay legible on primarySoft
  static const Color primaryDeep = Color(0xFFE65D00);

  // orange used as a *surface* rather than at full strength
  static const Color primarySoft = Color(0xFFFFF3E9);
  static const Color primaryTint = Color(0xFFFFE4CC);

  // **The whole neutral ramp is warm.** Every one of these used to be a blue-grey - #EFF1F5 and its
  // relatives - which is the default a UI lands on when nobody chooses, and which reads as cold next
  // to a brand whose one colour is orange. These are the same values rotated to the warm side of
  // neutral at the same lightness: nothing got darker or lighter, so every contrast ratio and every
  // shadow that was tuned against the old ramp still holds. The page now carries a trace of the
  // brand without any screen spending orange on it.
  //
  // Backgrounds - the page sits a real step below a white card, since a shadow soft enough to
  // look premium cannot separate white on near-white by itself
  static const Color background = Color(0xFFF5F1EB);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color cardGrey = Color(0xFFF7F4EE);

  // the neutral ramp every fill, border and divider comes from - no more ad-hoc greys.
  // also the header surface: one step *above* `background`, which is the whole of how a navigation
  // zone separates itself from the content area - see AppPageHeader.
  static const Color surfaceMuted = Color(0xFFFBF9F5);
  static const Color hairline = Color(0xFFF0EBE3);

  // what floats *over* content rather than sitting in the page: the bottom nav bar. deliberately
  // not white - a pure white bar over a warm page reads as a cut-out, and the whole point of a
  // floating surface is that it looks like it belongs to the same material as everything else.
  static const Color surfaceRaised = Color(0xFFFCFAF7);

  // the recessed track a white pill slides along. a step *below* background on purpose: a track
  // lighter than the page reads as a card sitting on top instead of a groove.
  static const Color trackGrey = Color(0xFFE9E3DA);

  // Text
  static const Color textDark = Color(0xFF1F1B18);
  static const Color textGrey = Color(0xFF938C84);
  static const Color textFaint = Color(0xFFAFA79E);
  static const Color textLight = Color(0xFFFFFFFF);

  // the step between textDark and textGrey, for *glyphs* rather than prose. a grid of icons at
  // textDark is the darkest thing on the screen, and textGrey lands under the 3:1 WCAG asks of a
  // non-text mark.
  static const Color textMuted = Color(0xFF6E665E);

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
