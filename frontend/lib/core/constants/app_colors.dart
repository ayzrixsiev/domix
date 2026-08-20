import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const Color primaryOrange = Color(0xFFFF6F00);
  static const Color primaryDark = Color(0xFF1E1E2C);
  
  // Brand tints - orange used as a *surface* rather than at full strength. keeping these as named
  // tokens is what stops the ui from reaching for saturated orange every time it wants to look
  // branded, which is what made it feel heavy.
  static const Color primarySoft = Color(0xFFFFF3E9);
  static const Color primaryTint = Color(0xFFFFE4CC);

  // Backgrounds
  //
  // the page sits a real step below a white card rather than the ~3% it used to (0xFFF8F9FA). a
  // white card on a near-white page has almost nothing to separate it but its shadow, and a shadow
  // soft enough to look premium is too soft to do that job alone - the contrast has to come from
  // the surface underneath. this is roughly ios's systemGroupedBackground, which exists for the
  // same reason. it darkens every screen at once, so it is a token change, not a per-widget one.
  static const Color background = Color(0xFFEFF1F5);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color cardGrey = Color(0xFFF1F3F6);

  // the neutral ramp every fill, border and divider should come from. these replace the ~9 ad-hoc
  // greys (0xFFF2F4F7, 0xFFE2E8F0, 0xFFF8FAFC, 0xFFCBD2DA, 0xFF98A2B3 ...) that were scattered
  // inline across screens and never quite matched each other.
  static const Color surfaceMuted = Color(0xFFF7F8FA);
  static const Color hairline = Color(0xFFECEEF2);

  // the recessed track a white pill slides along - the segmented control. deliberately a step
  // *below* `background` rather than above it: the whole illusion is that the selected pill is
  // raised out of a groove, and a track lighter than the page reads as a card sitting on top
  // instead. surfaceMuted and cardGrey are both at or above the page, which is why neither works
  // here.
  static const Color trackGrey = Color(0xFFE4E7EC);

  // Text
  static const Color textDark = Color(0xFF1A1D1E);
  static const Color textGrey = Color(0xFF8C929D);
  static const Color textFaint = Color(0xFFA9AEB8);
  static const Color textLight = Color(0xFFFFFFFF);

  // the step between `textDark` and `textGrey`, and it exists for *glyphs* rather than for prose.
  // one icon at textDark is a detail; twelve of them in a grid is the darkest thing on the screen,
  // which is exactly what Популярные категории looked like - a wall of near-black marks over a pale
  // page. textGrey is the obvious softer choice and is too soft: on trackGrey it lands at about
  // 2.5:1, under the 3:1 WCAG asks of a non-text mark. This sits at ~4.3:1 on that same fill.
  //
  // A token rather than `textDark.withValues(alpha: 0.62)`, which composites to almost this colour
  // and silently changes the moment the fill behind it does.
  static const Color textMuted = Color(0xFF646B76);

  // Accents
  static const Color starYellow = Color(0xFFFFB800);
  static const Color accentBlue = Color(0xFF2A85FF);

  // Errors / validation
  static const Color danger = Color(0xFFB42318);
  static const Color dangerSoft = Color(0xFFFEF0EE);
  static const Color success = Color(0xFF0E9F6E);
  static const Color successSoft = Color(0xFFE7F6EF);

  // the middle of a three-state signal - "neither good nor bad", as in a shop priced at the market
  // average. deliberately not `starYellow` (0xFFFFB800), which is bright enough to read as a
  // highlight and is already spoken for by ratings; this is darkened until it passes as body text
  // on its own tint.
  static const Color warning = Color(0xFFB54708);
  static const Color warningSoft = Color(0xFFFEF6EE);
}
