import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_motion.dart';

/// The line drawings that stand in for an icon on empty and error states.
///
/// Drawn, not shipped as images, so they take the theme's own blue and violet
/// in both modes and never blur on a large screen. Each one draws itself in —
/// a single stroke travelling the path — which turns an empty screen from a
/// dead end into a small moment.
enum StateArt {
  /// An empty tray with an arrow that would fill it.
  emptyTray,

  /// Two chain links that have come apart.
  brokenLink,

  /// A message with nothing to open in it.
  noLink,

  /// A cloud with a line through it.
  offline,

  /// A funnel that let everything through.
  filter,

  /// A magnifier that found nothing.
  search,
}

class StateIllustration extends StatelessWidget {
  const StateIllustration(this.art, {super.key, this.width = 128, this.tone});

  final StateArt art;
  final double width;

  /// The stroke colour; the palette's accent when unset.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final primary = tone ?? palette.accent;
    final secondary = tone == null ? palette.accentAlt : tone!;

    return SizedBox(
      width: width,
      height: width * 0.72,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: context.reduceMotion ? 1 : 0, end: 1),
        duration: context.motion(const Duration(milliseconds: 720)),
        curve: Curves.easeInOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _ArtPainter(
            art: art,
            primary: primary,
            secondary: secondary,
            wash: primary.withValues(alpha: 0.10),
            t: t,
          ),
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  const _ArtPainter({
    required this.art,
    required this.primary,
    required this.secondary,
    required this.wash,
    required this.t,
  });

  final StateArt art;
  final Color primary;
  final Color secondary;
  final Color wash;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is drawn in a 128 × 92 box and scaled, so the strokes keep
    // their weight whatever size the illustration is shown at.
    final scale = size.width / 128;
    canvas.scale(scale, scale);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // A soft disc behind the drawing gives it a stage.
    canvas.drawCircle(
      const Offset(64, 48),
      44 * (0.85 + 0.15 * t),
      Paint()..color = wash,
    );

    final layers = switch (art) {
      StateArt.emptyTray => _emptyTray(),
      StateArt.brokenLink => _brokenLink(),
      StateArt.noLink => _noLink(),
      StateArt.offline => _offline(),
      StateArt.filter => _filter(),
      StateArt.search => _search(),
    };

    // Layers draw one after the other across the animation, so the picture
    // assembles rather than appearing.
    final slice = 1 / layers.length;
    for (var i = 0; i < layers.length; i++) {
      final local = ((t - i * slice) / slice).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final layer = layers[i];
      stroke.color = layer.secondary ? secondary : primary;
      _drawPartial(canvas, layer.path, local, stroke);
    }
  }

  void _drawPartial(Canvas canvas, Path path, double fraction, Paint paint) {
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * fraction), paint);
    }
  }

  List<_Layer> _emptyTray() {
    final tray = Path()
      ..moveTo(28, 52)
      ..lineTo(36, 74)
      ..lineTo(92, 74)
      ..lineTo(100, 52)
      ..lineTo(84, 52)
      ..lineTo(80, 60)
      ..lineTo(48, 60)
      ..lineTo(44, 52)
      ..close();
    final arrow = Path()
      ..moveTo(64, 18)
      ..lineTo(64, 46)
      ..moveTo(54, 37)
      ..lineTo(64, 47)
      ..lineTo(74, 37);
    final sparkles = Path()
      ..addPath(_sparkle(const Offset(96, 24), 4), Offset.zero)
      ..addPath(_sparkle(const Offset(34, 30), 3), Offset.zero);
    return [_Layer(tray), _Layer(arrow, secondary: true), _Layer(sparkles)];
  }

  List<_Layer> _brokenLink() {
    final left = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(26, 38, 34, 20),
          const Radius.circular(10),
        ),
      );
    final right = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(68, 38, 34, 20),
          const Radius.circular(10),
        ),
      );
    final crack = Path()
      ..moveTo(60, 30)
      ..lineTo(65, 36)
      ..lineTo(61, 41)
      ..moveTo(68, 62)
      ..lineTo(63, 58)
      ..lineTo(66, 53);
    return [_Layer(left), _Layer(right), _Layer(crack, secondary: true)];
  }

  List<_Layer> _noLink() {
    final bubble = Path()
      ..moveTo(30, 26)
      ..lineTo(98, 26)
      ..quadraticBezierTo(104, 26, 104, 32)
      ..lineTo(104, 58)
      ..quadraticBezierTo(104, 64, 98, 64)
      ..lineTo(52, 64)
      ..lineTo(38, 76)
      ..lineTo(38, 64)
      ..lineTo(30, 64)
      ..quadraticBezierTo(24, 64, 24, 58)
      ..lineTo(24, 32)
      ..quadraticBezierTo(24, 26, 30, 26)
      ..close();
    final dots = Path()
      ..addOval(Rect.fromCircle(center: const Offset(48, 45), radius: 2.2))
      ..addOval(Rect.fromCircle(center: const Offset(64, 45), radius: 2.2))
      ..addOval(Rect.fromCircle(center: const Offset(80, 45), radius: 2.2));
    return [_Layer(bubble), _Layer(dots, secondary: true)];
  }

  List<_Layer> _offline() {
    final cloud = Path()
      ..moveTo(40, 66)
      ..lineTo(88, 66)
      ..cubicTo(100, 66, 104, 50, 92, 46)
      ..cubicTo(94, 30, 72, 26, 66, 38)
      ..cubicTo(58, 30, 42, 36, 44, 48)
      ..cubicTo(32, 48, 30, 66, 40, 66)
      ..close();
    final slash = Path()
      ..moveTo(34, 78)
      ..lineTo(96, 20);
    return [_Layer(cloud), _Layer(slash, secondary: true)];
  }

  List<_Layer> _filter() {
    final funnel = Path()
      ..moveTo(30, 22)
      ..lineTo(98, 22)
      ..lineTo(72, 52)
      ..lineTo(72, 74)
      ..lineTo(56, 68)
      ..lineTo(56, 52)
      ..close();
    final drops = Path()
      ..moveTo(64, 80)
      ..lineTo(64, 84)
      ..moveTo(58, 86)
      ..lineTo(70, 86);
    return [_Layer(funnel), _Layer(drops, secondary: true)];
  }

  List<_Layer> _search() {
    final glass = Path()
      ..addOval(Rect.fromCircle(center: const Offset(58, 42), radius: 22))
      ..moveTo(74, 58)
      ..lineTo(96, 80);
    final nothing = Path()
      ..moveTo(50, 34)
      ..lineTo(66, 50)
      ..moveTo(66, 34)
      ..lineTo(50, 50);
    return [_Layer(glass), _Layer(nothing, secondary: true)];
  }

  static Path _sparkle(Offset centre, double r) => Path()
    ..moveTo(centre.dx - r, centre.dy)
    ..lineTo(centre.dx + r, centre.dy)
    ..moveTo(centre.dx, centre.dy - r)
    ..lineTo(centre.dx, centre.dy + r);

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.t != t ||
      old.art != art ||
      old.primary != primary ||
      old.secondary != secondary;
}

class _Layer {
  const _Layer(this.path, {this.secondary = false});

  final Path path;
  final bool secondary;
}
