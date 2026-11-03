import 'package:flutter/material.dart';

// shared visual tokens. new ui pulls from these scales instead of inventing another one-off
// value - that consistency is most of what makes an interface read as designed.

class AppRadius {
  AppRadius._();

  /// chips, badges, the small numbered squares in the upload guide
  static const double xs = 8;

  /// buttons, inputs, avatars, tiles nested inside a card
  static const double sm = 14;

  /// cards, banners, the upload dropzone
  static const double md = 20;

  /// surfaces that float over the page: the nav bar and bottom sheets
  static const double lg = 28;
}

class AppShadows {
  AppShadows._();

  // a card reads as "slightly above the page", not as an object with a shadow under it. two soft
  // layers: the wide one is the glow that separates white from the off-white page, the tight one
  // stops the edge going soft.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F101828), blurRadius: 20, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x08101828), blurRadius: 3, offset: Offset(0, 1)),
  ];

  // one step above `card`, for content the eye is meant to pick out of the page
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x14101828), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A101828), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // for things that genuinely hover over other content: map overlays, the add-product button
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x1A101828), blurRadius: 30, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x0A101828), blurRadius: 3, offset: Offset(0, 1)),
  ];

  // a coloured glow under a primary button - the one place the brand colour bleeds outside its shape
  static List<BoxShadow> accent(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.26),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
}

class AppMotion {
  AppMotion._();

  /// press feedback - has to land before the finger lifts or it feels laggy
  static const Duration fast = Duration(milliseconds: 140);

  /// the default for anything the user watches move
  static const Duration base = Duration(milliseconds: 260);

  // starts quickly then settles. deliberately not easeOutBack: its overshoot reads as bouncy.
  static const Curve easing = Cubic(0.22, 1, 0.36, 1);
}
