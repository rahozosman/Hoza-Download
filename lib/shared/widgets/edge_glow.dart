import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';

/// A slow light that travels around the edge of a surface.
///
/// It marks the one control the user is meant to reach for next — the focused
/// search field, the primary action — with a single accent highlight riding the
/// outline. The sweep fades in when [active] turns on, stops its ticker once it
/// has faded out, and never starts at all under reduced motion, where the
/// theme's own focus border already carries the state.
class EdgeGlow extends StatefulWidget {
  const EdgeGlow({
    super.key,
    required this.child,
    this.active = true,
    this.borderRadius = Radii.cardRadius,
    this.thickness = 3,
    this.period = const Duration(milliseconds: 15200),
  });

  final Widget child;

  /// Whether the light should be travelling right now.
  final bool active;

  /// Must match the radius of the surface underneath, or the light rides off
  /// the corners.
  final BorderRadius borderRadius;

  /// How wide the core of the light is. A hairline on purpose: the light is
  /// meant to be noticed on the second glance, not to outline the card.
  final double thickness;

  /// One full lap. Slow on purpose — ambient, not urgent. Long enough that the
  /// eye reads it as a surface catching the light rather than as something
  /// circling the card, which is what a quick lap turns into once a screen
  /// carries more than one of them.
  final Duration period;

  @override
  State<EdgeGlow> createState() => _EdgeGlowState();
}

class _EdgeGlowState extends State<EdgeGlow> with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: Motion.slow,
    value: widget.active ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    _fade.addStatusListener(_onFadeStatus);
    if (widget.active) _sweep.repeat();
  }

  /// Nothing is painted at zero intensity, so the lap ticker can stand down.
  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _sweep.stop();
  }

  @override
  void didUpdateWidget(covariant EdgeGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      if (!_sweep.isAnimating) _sweep.repeat();
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  @override
  void dispose() {
    _fade.removeStatusListener(_onFadeStatus);
    _fade.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;

    final palette = context.colors;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_sweep, _fade]),
        builder: (context, child) => CustomPaint(
          foregroundPainter: _EdgeGlowPainter(
            progress: _sweep.value,
            intensity: Curves.easeOut.transform(_fade.value),
            borderRadius: widget.borderRadius,
            thickness: widget.thickness,
            head: palette.accent,
            tail: palette.accentAlt,
          ),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

class _EdgeGlowPainter extends CustomPainter {
  const _EdgeGlowPainter({
    required this.progress,
    required this.intensity,
    required this.borderRadius,
    required this.thickness,
    required this.head,
    required this.tail,
  });

  final double progress;
  final double intensity;
  final BorderRadius borderRadius;
  final double thickness;
  final Color head;
  final Color tail;

  /// How much of the lap the light occupies. The rest of the ring is clear, so
  /// the effect reads as one moving highlight rather than a glowing outline.
  static const List<double> _stops = [0, 0.07, 0.15, 0.32, 1];

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity < 0.01 || size.isEmpty) return;

    final rect = Offset.zero & size;
    final ring = borderRadius.toRRect(rect).deflate(thickness / 2);
    final rotation = GradientRotation(progress * 2 * math.pi);

    Shader shaderAt(double alpha) => SweepGradient(
      colors: [
        head.withValues(alpha: 0),
        head.withValues(alpha: alpha * intensity),
        tail.withValues(alpha: alpha * intensity * 0.8),
        tail.withValues(alpha: 0),
        head.withValues(alpha: 0),
      ],
      stops: _stops,
      transform: rotation,
    ).createShader(rect);

    // Two strokes stand in for a blur — a wide faint halo under a crisp core.
    // Cheaper than a MaskFilter and safe on every GPU the app ships to.
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 3.5
        ..shader = shaderAt(0.16),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..shader = shaderAt(0.95),
    );
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.intensity != intensity ||
      oldDelegate.thickness != thickness ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.head != head ||
      oldDelegate.tail != tail;
}

/// Slides a gradient sideways by a fraction of the box it paints into.
///
/// Shared by every travelling-light effect in the app so they all drift at the
/// same rate and in the same direction.
@immutable
class SlideGradient extends GradientTransform {
  const SlideGradient(this.fraction);

  final double fraction;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fraction, 0, 0);
}

/// A hairline of brand light travelling along the top edge of a surface.
///
/// Used where a full lap makes no sense — a sheet whose bottom half is off the
/// screen — so the light runs the one edge the user can actually see.
class RimLight extends StatefulWidget {
  const RimLight({
    super.key,
    this.thickness = 2,
    this.period = const Duration(milliseconds: 5200),
  });

  final double thickness;
  final Duration period;

  @override
  State<RimLight> createState() => _RimLightState();
}

class _RimLightState extends State<RimLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    if (context.reduceMotion) {
      return SizedBox(
        height: widget.thickness,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: palette.brandGradient),
        ),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        height: widget.thickness,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.accent.withValues(alpha: 0),
                  palette.accent,
                  palette.accentAlt,
                  palette.accentAlt.withValues(alpha: 0),
                ],
                stops: const [0, 0.16, 0.3, 0.46],
                transform: SlideGradient(-0.5 + _controller.value * 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
