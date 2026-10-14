import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const Color primaryOrange = Color(0xFFFF6F00);
  static const Color primaryDark = Color(0xFF27272E);

  // one step under primaryOrange, for a glyph that has to stay legible on primarySoft
  static const Color primaryDeep = Color(0xFFE65D00);

  // orange used as a *surface* rather than at full strength
  static const Color primarySoft = Color(0xFFFFF3E9);
  static const Color primaryTint = Color(0xFFFFE4CC);

  // **The iOS look is a cool off-white page under pure-white cards** - #F2F2F6 is iOS's own
  // grouped-list background, and the point of it is that white cards read as white *objects* on it
  // rather than as the page itself. The ramp below is that one neutral at several lightnesses; the
  // brand's orange is the only warm thing on screen, which is what keeps it premium rather than
  // beige. Cards still need `AppShadows.card`: the step is deliberately small.
  static const Color background = Color(0xFFF2F2F6);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color cardGrey = Color(0xFFF7F7FA);

  // fills for things *inside* a white card (an input, a tile in a list) and the hairline between rows
  static const Color surfaceMuted = Color(0xFFF8F8FB);
  static const Color hairline = Color(0xFFEAEAF0);

  // what floats *over* content rather than sitting in the page: the bottom nav bar. a hair off
  // white, so it reads as the same material as the page lifted off it.
  static const Color surfaceRaised = Color(0xFFFCFCFE);

  // the recessed track a white pill slides along. a step *below* background on purpose: a track
  // lighter than the page reads as a card sitting on top instead of a groove.
  static const Color trackGrey = Color(0xFFE3E3EA);

  // **the colour every catalogue photo is shot on.** the photo sits `contain`ed on this panel, so
  // the bars either side of a shot are invisible only if the background matches to the digit.
  // deliberately its own token and not `background`: the page can be retuned without a reshoot.
  static const Color photoPanel = Color(0xFFEFF0F5);

  // Text
  static const Color textDark = Color(0xFF17171C);
  static const Color textGrey = Color(0xFF8A8A93);
  static const Color textFaint = Color(0xFFAFAFB8);
  static const Color textLight = Color(0xFFFFFFFF);

  // the step between textDark and textGrey, for *glyphs* rather than prose. a grid of icons at
  // textDark is the darkest thing on the screen, and textGrey lands under the 3:1 WCAG asks of a
  // non-text mark.
  static const Color textMuted = Color(0xFF66666F);

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
