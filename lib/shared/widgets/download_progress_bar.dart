import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';

/// Progress track for a download.
///
/// Animates between values instead of jumping, and renders an indeterminate
/// sweep when the total size is unknown — the bar always tells the truth about
/// what is known.
///
/// Given the transfer speed, the bar also *moves* at that speed: a thin
/// highlight travels along the filled part, quick on a fast connection, slow
/// on a crawling one, still when nothing is arriving — and the leading edge
/// glows for a moment each time bytes land. "Is it moving?" is answered by
/// the bar itself, before the number beside it is read.
class DownloadProgressBar extends StatefulWidget {
  const DownloadProgressBar({
    super.key,
    required this.progress,
    this.color,
    this.height = 6,
    this.speedBytesPerSecond,
  });

  /// 0..1, or null when the total size is unknown.
  final double? progress;

  final Color? color;
  final double height;

  /// The live rate, which sets the pace of the travelling highlight. Null or
  /// zero holds it still.
  final double? speedBytesPerSecond;

  @override
  State<DownloadProgressBar> createState() => _DownloadProgressBarState();
}

class _DownloadProgressBarState extends State<DownloadProgressBar>
    with TickerProviderStateMixin {
  /// One trip of the highlight along the bar.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _periodFor(widget.speedBytesPerSecond),
  );

  /// The leading edge lighting up as bytes arrive.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  DateTime _lastPulse = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _slowest = Duration(milliseconds: 2600);
  static const Duration _fastest = Duration(milliseconds: 650);

  /// A lap of the highlight per this much speed: 1 MB/s makes for a trip of
  /// about a second, and the pace is clamped at both ends so the band never
  /// blurs into a flicker nor crawls so slowly it looks stuck.
  static Duration? _periodFor(double? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond <= 0) return null;
    final mbps = bytesPerSecond / (1000 * 1000);
    final ms = 2600 - mbps * 1600;
    return Duration(
      milliseconds: ms
          .clamp(
            _fastest.inMilliseconds.toDouble(),
            _slowest.inMilliseconds.toDouble(),
          )
          .round(),
    );
  }

  @override
  void initState() {
    super.initState();
    _syncSweep();
  }

  @override
  void didUpdateWidget(covariant DownloadProgressBar old) {
    super.didUpdateWidget(old);
    _syncSweep();

    final before = old.progress ?? 0;
    final after = widget.progress ?? 0;
    // A burst of bytes lights the edge; throttled so a stream of samples
    // reads as a steady glow rather than a strobe.
    if (after > before &&
        !context.reduceMotion &&
        DateTime.now().difference(_lastPulse) >
            const Duration(milliseconds: 260)) {
      _lastPulse = DateTime.now();
      _pulse.forward(from: 0);
    }
  }

  void _syncSweep() {
    final period = _periodFor(widget.speedBytesPerSecond);
    if (period == null || context.reduceMotion || widget.progress == null) {
      if (_sweep.isAnimating) _sweep.stop();
      return;
    }
    // Re-timed only on a real change of pace, so the band does not stutter
    // every time a sample wobbles. A controller that has never been timed —
    // the bar is built before the first speed sample, with no period at all
    // — takes the first pace it is given: repeat() with no duration throws,
    // mid-build, and leaves the block it was updating behind as a frozen
    // second copy under the live one.
    final current = _sweep.duration;
    if (current == null ||
        (current - period).abs() > const Duration(milliseconds: 180)) {
      _sweep.duration = period;
    }
    if (!_sweep.isAnimating) _sweep.repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final fill = widget.color ?? palette.accent;
    final value = widget.progress;

    return ClipRRect(
      borderRadius: Radii.pillRadius,
      child: SizedBox(
        height: widget.height,
        child: value == null
            ? LinearProgressIndicator(
                backgroundColor: palette.surfaceMuted,
                color: fill,
                minHeight: widget.height,
              )
            : TweenAnimationBuilder<double>(
                tween: Tween<double>(end: value.clamp(0.0, 1.0)),
                duration: context.motion(Motion.slow),
                curve: Motion.standard,
                builder: (context, animated, _) => AnimatedBuilder(
                  animation: Listenable.merge([_sweep, _pulse]),
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _BarPainter(
                      fraction: animated,
                      track: palette.surfaceMuted,
                      fill: fill,
                      sweep: _sweep.isAnimating ? _sweep.value : null,
                      pulse:
                          Curves.easeOut.transform(1 - _pulse.value) *
                          (_pulse.isAnimating ? 1 : 0),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.sweep,
    required this.pulse,
  });

  final double fraction;
  final Color track;
  final Color fill;

  /// 0..1 position of the travelling highlight, or null when still.
  final double? sweep;

  /// 0..1 strength of the leading-edge glow.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    if (fraction <= 0) return;

    final filled = Rect.fromLTWH(0, 0, size.width * fraction, size.height);
    // Drawn rather than delegated to LinearProgressIndicator so the fill can
    // carry a gradient: the leading edge is brighter, which makes slow
    // progress still look alive.
    canvas.drawRect(
      filled,
      Paint()
        ..shader = LinearGradient(
          colors: [fill.withValues(alpha: 0.65), fill],
        ).createShader(filled),
    );

    final t = sweep;
    if (t != null && filled.width > 4) {
      canvas.save();
      canvas.clipRect(filled);
      // A soft band a fifth of the fill wide, entering from the left and
      // leaving past the leading edge.
      final bandWidth = math.max(18.0, filled.width * 0.22);
      final x = -bandWidth + t * (filled.width + bandWidth);
      final band = Rect.fromLTWH(x, 0, bandWidth, size.height);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.38),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(band),
      );
      canvas.restore();
    }

    if (pulse > 0) {
      final edge = Offset(filled.right, size.height / 2);
      canvas.drawCircle(
        edge,
        size.height * (0.9 + 1.4 * pulse),
        Paint()
          ..color = fill.withValues(alpha: 0.55 * pulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction ||
      old.sweep != sweep ||
      old.pulse != pulse ||
      old.fill != fill ||
      old.track != track;
}
