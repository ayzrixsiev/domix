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

  // a card reads as "slightly above the page", not as an object with a shadow under it: one very
  // soft layer, ~4% black.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A0D1220), blurRadius: 14, offset: Offset(0, 3)),
  ];

  // one step above `card`, for content the eye is meant to pick out of the page. two soft layers
  // rather than one hard one - a single dark shadow reads as a cheap drop shadow.
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x140D1220), blurRadius: 20, offset: Offset(0, 5)),
    BoxShadow(color: Color(0x0A0D1220), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // what holds a header surface off the page scrolling under it. two layers and no line: the tight
  // one is the edge itself, the wide one is the fall-off that stops it reading as a rule. weaker
  // than `card` on purpose - the tonal step between the two surfaces does most of the work.
  static const List<BoxShadow> header = [
    BoxShadow(color: Color(0x0F101828), blurRadius: 1, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D101828), blurRadius: 14, offset: Offset(0, 4)),
  ];

  // for things that genuinely hover over other content: the nav bar, map overlays
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x14101828), blurRadius: 30, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x0A101828), blurRadius: 3, offset: Offset(0, 1)),
  ];

  // a coloured glow under a primary button - the one place the brand colour bleeds outside its shape
  static List<BoxShadow> accent(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.26), blurRadius: 18, offset: const Offset(0, 6)),
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
