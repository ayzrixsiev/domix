import 'package:flutter/widgets.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// Press feedback: the child shrinks under a finger. Used instead of an InkWell ripple, which
/// spreads *inside* the shape and is a faint wash on a large tile that never moves.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.97,
  });

  final Widget child;

  /// null disables the whole thing - a disabled control that animates reads as accepting the tap
  final VoidCallback? onTap;

  /// 0.97 on a full-width tile is a couple of pixels: felt, not watched. smaller shapes want more.
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
      // opaque, so the tile's padding is tappable too and not only where a child paints something
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      // onTapCancel matters as much as onTapUp: without it, dragging the feed while touching a tile
      // leaves it shrunk forever
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
