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
  static const Color background = Color(0xFFF8F9FA);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color cardGrey = Color(0xFFF1F3F6);

  // the neutral ramp every fill, border and divider should come from. these replace the ~9 ad-hoc
  // greys (0xFFF2F4F7, 0xFFE2E8F0, 0xFFF8FAFC, 0xFFCBD2DA, 0xFF98A2B3 ...) that were scattered
  // inline across screens and never quite matched each other.
  static const Color surfaceMuted = Color(0xFFF7F8FA);
  static const Color hairline = Color(0xFFECEEF2);

  // Text
  static const Color textDark = Color(0xFF1A1D1E);
  static const Color textGrey = Color(0xFF8C929D);
  static const Color textFaint = Color(0xFFA9AEB8);
  static const Color textLight = Color(0xFFFFFFFF);

  // Accents
  static const Color starYellow = Color(0xFFFFB800);
  static const Color accentBlue = Color(0xFF2A85FF);

  // Errors / validation
  static const Color danger = Color(0xFFB42318);
  static const Color dangerSoft = Color(0xFFFEF0EE);
  static const Color success = Color(0xFF0E9F6E);
  static const Color successSoft = Color(0xFFE7F6EF);
}
