import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_motion.dart';
import '../../data/models/download_status.dart';

/// A small ring that says how far a download is without a word being read.
///
/// The arc fills clockwise in the media's own hue with the percent inside;
/// when the size is unknown it sweeps; when the download finishes the ring
/// closes and a check draws itself in — one stroke, about 400 ms — so the
/// moment of completion is seen, not inferred from a label changing.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.status,
    required this.progress,
    this.color,
    this.size = 30,
    this.stroke = 2.6,
  });

  final DownloadStatus status;

  /// 0..1, or null when the total is unknown.
  final double? progress;
  final Color? color;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final tint = color ?? palette.accent;
    final ground = palette.surface;

    final Widget ring = switch (status) {
      DownloadStatus.completed => _CheckRing(
        color: palette.success,
        ground: ground,
        size: size,
        stroke: stroke,
      ),
      DownloadStatus.failed => _MarkRing(
        color: palette.danger,
        ground: ground,
        size: size,
        stroke: stroke,
        glyph: '!',
      ),
      DownloadStatus.cancelled => _MarkRing(
        color: palette.textTertiary,
        ground: ground,
        size: size,
        stroke: stroke,
        glyph: '×',
      ),
      _ => _ArcRing(
        color: status == DownloadStatus.paused ? palette.warning : tint,
        track: palette.borderStrong,
        ground: ground,
        size: size,
        stroke: stroke,
        progress: status == DownloadStatus.queued ? 0 : progress,
        // A queued download has a size but no motion yet; the empty ring says
        // "not started" better than a sweep that promises activity.
        sweeping: status == DownloadStatus.downloading && progress == null,
      ),
    };

    return Semantics(
      label: switch (status) {
        DownloadStatus.completed => 'Completed',
        DownloadStatus.failed => 'Failed',
        DownloadStatus.cancelled => 'Cancelled',
        _ =>
          progress == null
              ? status.name
              : '${(progress! * 100).round()} percent',
      },
      child: SizedBox(width: size, height: size, child: ring),
    );
  }
}

class _ArcRing extends StatefulWidget {
  const _ArcRing({
    required this.color,
    required this.track,
    required this.ground,
    required this.size,
    required this.stroke,
    required this.progress,
    required this.sweeping,
  });

  final Color color;
  final Color track;
  final Color ground;
  final double size;
  final double stroke;
  final double? progress;
  final bool sweeping;

  @override
  State<_ArcRing> createState() => _ArcRingState();
}

class _ArcRingState extends State<_ArcRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _syncSweep();
  }

  @override
  void didUpdateWidget(covariant _ArcRing old) {
    super.didUpdateWidget(old);
    if (old.sweeping != widget.sweeping) _syncSweep();
  }

  void _syncSweep() {
    if (widget.sweeping && !context.reduceMotion) {
      _sweep.repeat();
    } else {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = (widget.progress ?? 0).clamp(0.0, 1.0);
    final percent = widget.progress == null
        ? null
        : (widget.progress! * 100).round();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      duration: context.motion(Motion.slow),
      curve: Motion.standard,
      builder: (context, value, _) => AnimatedBuilder(
        animation: _sweep,
        builder: (context, _) => CustomPaint(
          painter: _RingPainter(
            color: widget.color,
            track: widget.track,
            ground: widget.ground,
            stroke: widget.stroke,
            fraction: widget.sweeping ? 0.28 : value,
            startTurn: widget.sweeping ? _sweep.value : 0,
          ),
          child: Center(
            child: widget.sweeping || percent == null
                ? null
                : Text(
                    '$percent',
                    style: TextStyle(
                      fontSize: widget.size * 0.3,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: widget.color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The ring closing and the check drawing in, once.
class _CheckRing extends StatelessWidget {
  const _CheckRing({
    required this.color,
    required this.ground,
    required this.size,
    required this.stroke,
  });

  final Color color;
  final Color ground;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: context.reduceMotion ? 1 : 0, end: 1),
      duration: context.motion(const Duration(milliseconds: 420)),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => CustomPaint(
        painter: _CheckPainter(
          color: color,
          ground: ground,
          stroke: stroke,
          t: t,
        ),
      ),
    );
  }
}

/// A closed ring with one character in it, for the states with nothing left
/// to measure.
class _MarkRing extends StatelessWidget {
  const _MarkRing({
    required this.color,
    required this.ground,
    required this.size,
    required this.stroke,
    required this.glyph,
  });

  final Color color;
  final Color ground;
  final double size;
  final double stroke;
  final String glyph;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingPainter(
        color: color,
        track: color.withValues(alpha: 0.35),
        ground: ground,
        stroke: stroke,
        fraction: 0,
        startTurn: 0,
      ),
      child: Center(
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: size * 0.46,
            fontWeight: FontWeight.w800,
            height: 1,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.color,
    required this.track,
    required this.ground,
    required this.stroke,
    required this.fraction,
    required this.startTurn,
  });

  final Color color;
  final Color track;
  final Color ground;
  final double stroke;
  final double fraction;

  /// Where the arc begins, in turns; moves while sweeping.
  final double startTurn;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // A solid disc behind the ring, so it stays legible over any thumbnail.
    canvas.drawCircle(
      centre,
      radius + stroke / 2,
      Paint()..color = ground.withValues(alpha: 0.92),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (fraction <= 0) return;

    final start = -math.pi / 2 + startTurn * 2 * math.pi;
    canvas.drawArc(
      rect,
      start,
      2 * math.pi * fraction,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * math.pi,
          transform: GradientRotation(start),
          colors: [color.withValues(alpha: 0.55), color],
          stops: const [0, 1],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.startTurn != startTurn ||
      old.color != color ||
      old.track != track;
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({
    required this.color,
    required this.ground,
    required this.stroke,
    required this.t,
  });

  final Color color;
  final Color ground;
  final double stroke;

  /// 0..1: the first half closes the ring, the second draws the check.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke;

    canvas.drawCircle(
      centre,
      radius + stroke / 2,
      Paint()..color = ground.withValues(alpha: 0.92),
    );
    final ringT = (t / 0.55).clamp(0.0, 1.0);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * ringT,
      false,
      paint,
    );

    final checkT = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    if (checkT <= 0) return;
    final s = size.shortestSide;
    final path = Path()
      ..moveTo(s * 0.30, s * 0.52)
      ..lineTo(s * 0.44, s * 0.66)
      ..lineTo(s * 0.71, s * 0.37);
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * checkT), paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}
