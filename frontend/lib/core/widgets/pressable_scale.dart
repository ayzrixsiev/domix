import 'package:flutter/widgets.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// Press feedback: the child shrinks slightly while a finger is down and springs back on release.
///
/// This is the app's answer to "that control feels dead". A Material `InkWell` ripple was the
/// alternative and is what several of these surfaces used to have - but a ripple spreads *inside*
/// the shape, so on a large tile with a border and a fill it is a faint grey wash somewhere in the
/// middle of a box that otherwise doesn't move. Scaling moves the whole control, which is what
/// reads as "this thing responded to me", and it is the gesture language the rest of iOS uses.
///
/// The animation is deliberately asymmetric in feel: [AppMotion.fast] is 140ms, short enough that
/// the shrink lands before the finger lifts. Anything slower and the press appears to lag behind the
/// touch, which is worse than no animation at all.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.97,
  });

  final Widget child;

  /// null disables the whole thing - a disabled control must not animate, or it reads as accepting
  /// a tap it then ignores
  final VoidCallback? onTap;

  /// how far down it goes. 0.97 on a full-width tile is a couple of pixels: felt, not watched.
  /// smaller shapes want a little more, which is why this is a parameter rather than a constant.
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    return GestureDetector(
      // opaque, so the gesture is caught anywhere on the tile including its padding - not only
      // where a child widget happens to paint something
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      // both of these have to reset the state: onTapUp fires on a completed tap, onTapCancel when
      // the finger slides off or a parent scroll claims the gesture. without the second, dragging
      // the feed while touching a tile would leave it shrunk forever.
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.easing,
        child: widget.child,
      ),
    );
  }
}
