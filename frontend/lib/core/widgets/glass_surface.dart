import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';

/// **The one switch that takes the shader out of the build.** `ImageFilter.shader` is Impeller-only
/// and new enough that a bad frame on some GPU is a plausible way to lose a release; flipping this
/// to false leaves the blur, the tint and the rim, which is still glass, just without the bend at
/// the edge. Nothing else has to change.
const bool _refraction = true;

/// A sheet of frosted glass: it blurs what is behind it, bends it at the rim, and tints the result
/// so the thing on top of it stays readable.
///
/// **Glass is not a colour, it is a relationship with what is underneath**, so this is only worth
/// using over something that moves - the nav bar with the feed scrolling under it, an overlay on the
/// map. Put it on a flat page and it is an expensive way to draw [AppColors.surfaceRaised].
///
/// Three draws stack inside the clip, in this order: the backdrop filter, the tint that makes the
/// blur legible, and the sheen that gives the pane a lit top edge.
///
/// **A platform view is not part of Flutter's backdrop.** On the Карта tab the Yandex map is a
/// native view, so the filter has nothing of it to sample and the bar falls back to its tint alone -
/// which is why [tint] carries real opacity instead of a trace.
class GlassSurface extends StatefulWidget {
  const GlassSurface({
    super.key,
    required this.borderRadius,
    required this.child,
    this.blur = 22,
    this.tint = const Color(0x8CFFFFFF),
    this.border = const Color(0x73FFFFFF),
  });

  final BorderRadius borderRadius;
  final Widget child;

  /// Sigma, not a radius: 22 is about an iOS "systemThickMaterial".
  final double blur;

  /// White at partial alpha rather than a colour - the page's own warmth is what should come
  /// through, and a tinted pane over a photo goes grey.
  final Color tint;

  /// The lit hairline around the pane. The glass has no edge of its own without it.
  final Color border;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  /// Compiled once for the whole app: a FragmentProgram is a GPU resource, not a widget's property.
  static Future<ui.FragmentProgram>? _program;
  static ui.FragmentProgram? _loaded;

  final _key = GlobalKey();

  /// Where this pane sits as a fraction of the window. The shader needs it because Impeller binds
  /// the *whole* render pass as the filter's input, not just the part under the clip.
  Rect? _slot;

  ui.FragmentShader? _shader;

  /// **The generation before the current one, freed one generation late.** The raster thread runs
  /// behind the widget tree, so a shader replaced during this build may still be inside the frame
  /// being drawn - disposing it there is a use-after-free with no stack trace pointing here.
  ui.FragmentShader? _retired;

  /// Kept across builds: rebuilding the filter every frame would churn a GPU resource for geometry
  /// that only changes when the pane moves.
  ui.ImageFilter? _cached;
  Object? _cachedFor;

  bool get _canRefract => _refraction && ui.ImageFilter.isShaderFilterSupported;

  @override
  void initState() {
    super.initState();
    if (!_canRefract) return;
    if (_loaded != null) return;
    (_program ??= ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag')).then((program) {
      _loaded = program;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    _retired?.dispose();
    super.dispose();
  }

  /// Measured after layout rather than computed from the padding above, so the pane is free to move -
  /// a keyboard pushing it up, a tablet changing its width - without the rim drifting off its edge.
  void _measure() {
    if (!_canRefract || _loaded == null) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    // **the window, not MediaQuery.** localToGlobal reports where this box is on the real surface,
    // which is also what the filter samples; MediaQuery is a value the tree can override - and
    // device_preview does exactly that, which would put the rim somewhere off the pane.
    final window = _window(context);
    if (window.isEmpty) return;

    final origin = box.localToGlobal(Offset.zero);
    final slot = Rect.fromLTWH(
      origin.dx / window.width,
      origin.dy / window.height,
      box.size.width / window.width,
      box.size.height / window.height,
    );

    // a threshold rather than equality: a rect recomputed every frame would setState every frame
    final previous = _slot;
    if (previous != null &&
        (previous.topLeft - slot.topLeft).distance < 0.001 &&
        (previous.bottomRight - slot.bottomRight).distance < 0.001) {
      return;
    }
    setState(() => _slot = slot);
  }

  static Size _window(BuildContext context) {
    final view = View.of(context);
    return view.physicalSize / view.devicePixelRatio;
  }

  ui.ImageFilter _filter(Size window) {
    final program = _loaded;
    final slot = _slot;
    if (!_canRefract || program == null || slot == null) {
      return ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur);
    }

    final key = Object.hash(slot, window, widget.blur, widget.borderRadius);
    if (_cachedFor == key) return _cached!;

    // a fresh shader per geometry change: ImageFilter.shader reads its uniforms once, when the
    // filter is built, so mutating the old one would leave the rim where the pane used to be
    _retired?.dispose();
    _retired = _shader;
    final shader = _shader = program.fragmentShader();
    // index 0 and 1 are the vec2 Impeller fills in itself
    shader.setFloat(2, slot.left);
    shader.setFloat(3, slot.top);
    shader.setFloat(4, slot.right);
    shader.setFloat(5, slot.bottom);
    // the three lengths, each as a fraction of the window's height - see the shader's header
    shader.setFloat(6, widget.borderRadius.topLeft.x / window.height);
    shader.setFloat(7, _rimDepth / window.height);
    shader.setFloat(8, _rimStrength / window.height);

    // inner first: the blur frosts the backdrop, then the rim bends the frosted result
    _cachedFor = key;
    return _cached = ui.ImageFilter.compose(
      outer: ui.ImageFilter.shader(shader),
      inner: ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
    );
  }

  /// How far in from the edge the bend reaches, and how far it displaces, in logical pixels. Small
  /// on purpose: past about 12 the rim stops reading as thickness and starts reading as a smudge.
  static const double _rimDepth = 11;
  static const double _rimStrength = 7;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });

    return ClipRRect(
      key: _key,
      borderRadius: widget.borderRadius,
      child: BackdropFilter(
        filter: _filter(_window(context)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.tint,
            borderRadius: widget.borderRadius,
            border: Border.all(color: widget.border, width: 1),
          ),
          // the lit top edge. a pane with an even tint reads as plastic; the gradient is the one
          // cue that says light is falling on it from above.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
                stops: [0, 0.45],
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
