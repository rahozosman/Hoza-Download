import 'package:flutter/widgets.dart';

/// Motion tokens.
///
/// Hoza animates to communicate state, never to decorate. Durations stay in the
/// 120–320 ms band so the app reads as fast rather than theatrical.
abstract final class Motion {
  /// Chip selection, icon swaps, press feedback.
  static const Duration fast = Duration(milliseconds: 150);

  /// The default for most transitions.
  static const Duration base = Duration(milliseconds: 220);

  /// Sheet entry, page transitions, large surface changes.
  static const Duration slow = Duration(milliseconds: 300);

  /// Staggered list entrances build on this step.
  static const Duration stagger = Duration(milliseconds: 45);

  /// Standard decelerate — the workhorse curve.
  static const Curve standard = Curves.easeOutCubic;

  /// Material 3 emphasised decelerate, for surfaces entering the screen.
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1);

  /// For something that travels from one place on screen to another.
  ///
  /// [emphasized] is almost vertical off the mark — most of the distance is
  /// covered in the first tenth of the time — which is right for a surface
  /// arriving from off screen and wrong for an object crossing the screen: it
  /// reads as a jump followed by a hover. This leaves gently, moves, and
  /// arrives gently.
  static const Curve travel = Cubic(0.2, 0, 0, 1);

  /// For elements leaving the screen.
  static const Curve exit = Curves.easeInCubic;

  /// A restrained overshoot for success confirmations only.
  static const Curve springy = Curves.easeOutBack;
}

extension MotionQuery on BuildContext {
  /// True when the platform asks for reduced motion. Decorative animations are
  /// skipped in that case; state-carrying animations simply snap instead.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// Collapses a duration to zero when the user prefers reduced motion.
  Duration motion(Duration duration) => reduceMotion ? Duration.zero : duration;
}
