import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_motion.dart';

/// A number that moves to its new value instead of jumping there.
///
/// Speed, size and time left all arrive as a fresh sample several times a
/// second; shown raw they flicker, and a flickering number is one nobody
/// trusts. This tweens between samples over a few hundred milliseconds — long
/// enough to read as a steady gauge, short enough to still be live — and
/// keeps the digits in tabular figures so the text never wobbles sideways.
class AnimatedMetric extends StatelessWidget {
  const AnimatedMetric({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.unknown = '—',
    this.duration = const Duration(milliseconds: 450),
  });

  /// The latest sample, or null when nothing honest can be shown.
  final double? value;

  /// Turns the tweened value into text.
  final String Function(double value) format;
  final TextStyle style;
  final String unknown;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final current = value;
    final resolved = style.copyWith(
      fontFeatures: [
        ...?style.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
    );
    if (current == null) return Text(unknown, style: resolved);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: current),
      duration: context.motion(duration),
      curve: Motion.standard,
      builder: (context, animated, _) =>
          Text(format(animated), style: resolved),
    );
  }
}

/// The colour a transfer speed is shown in: lit when it is fast, quiet when
/// it is crawling, dim when it has stopped — so the number's tone says what
/// the number says.
Color speedColor(HozaPalette palette, double? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond <= 0) {
    return palette.textTertiary;
  }
  if (bytesPerSecond >= 1000 * 1000) return palette.accent;
  if (bytesPerSecond < 100 * 1000) return palette.textTertiary;
  return palette.textSecondary;
}
