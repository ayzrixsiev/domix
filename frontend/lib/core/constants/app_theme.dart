import 'package:flutter/material.dart';

// shared visual tokens. before this file existed every widget invented its own radius (6, 10, 12,
// 14, 16, 18, 20, 24 and 28 were all in use at once) and its own shadow, which is the main reason
// screens felt unrelated to each other. new ui should pull from these scales instead of adding
// another one-off value - that consistency is most of what makes an interface read as "designed".

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

  // a card should read as "slightly above the page", not as an object with a drop shadow under it.
  // one very soft layer, ~4% black, is enough to separate white-on-near-white.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A0D1220), blurRadius: 14, offset: Offset(0, 3)),
  ];

  // one step above `card`, for content the eye is meant to pick out of the page: the shop cards.
  // still two soft layers rather than one hard one - a single dark shadow reads as a cheap drop
  // shadow, whereas an ambient blur plus a tight contact shadow reads as a real object on a surface.
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x140D1220), blurRadius: 20, offset: Offset(0, 5)),
    BoxShadow(color: Color(0x0A0D1220), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // for things that genuinely hover over other content (nav bar, map overlays). two layers: a wide
  // ambient one for the lift, and a tight one so the edge stays anchored instead of drifting.
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x14101828), blurRadius: 30, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x0A101828), blurRadius: 3, offset: Offset(0, 1)),
  ];

  // a coloured glow under a primary button - the one place the brand colour is allowed to bleed
  // outside its own shape, which is what separates a "premium" cta from a flat rectangle.
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

  // starts quickly then settles gently, the way ios transitions do. deliberately not easeOutBack:
  // its overshoot reads as playful/bouncy, which is the opposite of the calm feel we want here.
  static const Curve easing = Cubic(0.22, 1, 0.36, 1);
}
