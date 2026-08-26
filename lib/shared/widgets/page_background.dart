import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_motion.dart';

/// Page canvas: the flat background, lit from three directions, with two
/// soft lights slowly drifting through it.
///
/// Blue enters from the top left and violet answers from the bottom right,
/// with the broad brand tint sitting behind the masthead between them. Keeping
/// the two brand hues on opposite corners is what gives the page a direction
/// to be lit from — a single centred wash just looks like a stain.
///
/// On top of that, two very soft blobs — one of each brand hue — wander on a
/// sixty-second loop and lean a little against the page's scroll, so the dark
/// theme reads as depth with air in it rather than flat navy. They are radial
/// gradients, not blur filters: nothing here costs a filter pass, and under
/// reduced motion they simply hold still.
class PageBackground extends StatefulWidget {
  const PageBackground({super.key, required this.child});

  final Widget child;

  /// One full wander of the drifting lights.
  static const Duration drift = Duration(seconds: 60);

  /// How far the lights lean per pixel of scroll, and the most they will.
  static const double _parallax = 0.06;
  static const double _parallaxLimit = 36;

  @override
  State<PageBackground> createState() => _PageBackgroundState();
}

class _PageBackgroundState extends State<PageBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: PageBackground.drift,
  );

  /// How far the page under this canvas has scrolled, damped for parallax.
  final ValueNotifier<double> _lean = ValueNotifier<double>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    _lean.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    // Only the page's own vertical scroll moves the lights; a chip rail
    // sliding sideways is not the page moving.
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.depth != 0) return false;
    final pixels = notification.metrics.pixels;
    _lean.value = (pixels * PageBackground._parallax).clamp(
      -PageBackground._parallaxLimit,
      PageBackground._parallaxLimit,
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return DecoratedBox(
      // One field of light under the whole app: blue at the top, violet at the
      // floor, both a few per cent off the base colour so the page still reads
      // as a background and not as a picture.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(palette.background, palette.accent, 0.07)!,
            palette.background,
            Color.lerp(palette.background, palette.accentAlt, 0.11)!,
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: Stack(
        children: [
          // Broad brand tint behind the masthead — the widest, softest layer,
          // and the one doing most of the work.
          Positioned(
            top: -180,
            left: -110,
            right: -60,
            height: 440,
            child: _wash(palette.backgroundTint, 0.62),
          ),
          // Blue, entering from the top left.
          Positioned(
            top: -140,
            left: -170,
            width: 380,
            height: 380,
            child: _wash(palette.accent, 0.13),
          ),
          // Violet, answering from the bottom right, well below the fold so it
          // reads as the page having a floor rather than a second headline.
          Positioned(
            bottom: -250,
            right: -150,
            width: 460,
            height: 460,
            child: _wash(palette.accentAlt, 0.15),
          ),
          // A second, smaller violet on the opposite side keeps the lower half
          // from tipping to one corner.
          Positioned(
            bottom: -160,
            left: -190,
            width: 340,
            height: 340,
            child: _wash(palette.accentAlt, 0.08),
          ),

          // The two wandering lights, on their own layer so their motion never
          // repaints the page above them.
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: _DriftingLights(drift: _drift, lean: _lean),
              ),
            ),
          ),

          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ],
      ),
    );
  }

  Widget _wash(Color color, double alpha) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        radius: 0.72,
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

/// Two soft blobs on slow, unequal orbits, leaning with the scroll.
class _DriftingLights extends StatelessWidget {
  const _DriftingLights({required this.drift, required this.lean});

  final Animation<double> drift;
  final ValueListenable<double> lean;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return AnimatedBuilder(
          animation: Listenable.merge([drift, lean]),
          builder: (context, _) {
            final t = drift.value * 2 * math.pi;
            final offset = lean.value;

            // Two orbits at different rates and phases, so the pair never
            // falls into step and the movement never reads as a loop.
            final blue = Offset(
              width * 0.18 + math.sin(t) * width * 0.16,
              height * 0.22 + math.cos(t * 0.7) * height * 0.09 - offset,
            );
            final violet = Offset(
              width * 0.82 + math.cos(t * 0.8 + 1.3) * width * 0.14,
              height * 0.68 +
                  math.sin(t * 0.6 + 0.4) * height * 0.08 -
                  offset * 0.6,
            );

            return Stack(
              children: [
                _Light(
                  centre: blue,
                  radius: width * 0.62,
                  color: palette.accent,
                  alpha: 0.11,
                ),
                _Light(
                  centre: violet,
                  radius: width * 0.70,
                  color: palette.accentAlt,
                  alpha: 0.12,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// One blob: a radial falloff from the hue to nothing, feathered wide enough
/// that its edge is never seen.
class _Light extends StatelessWidget {
  const _Light({
    required this.centre,
    required this.radius,
    required this.color,
    required this.alpha,
  });

  final Offset centre;
  final double radius;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: centre.dx - radius,
      top: centre.dy - radius,
      width: radius * 2,
      height: radius * 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.45),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.38, 1],
          ),
        ),
      ),
    );
  }
}
