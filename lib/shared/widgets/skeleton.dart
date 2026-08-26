import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';

/// A shimmering placeholder block.
///
/// Skeletons stand in for content whose shape is already known, which reads as
/// faster than a spinner. Under reduced-motion the shimmer stops but the block
/// still shows, so the loading state is never lost.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = Radii.tileRadius,
  });

  /// A single line of placeholder text.
  const Skeleton.line({super.key, this.width, this.height = 12})
    : borderRadius = const BorderRadius.all(Radius.circular(6));

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    if (context.reduceMotion) {
      return _block(palette.skeletonBase, null);
    }

    // The highlight runs in reading direction — it is the eye's own sweep —
    // so it flips with the layout instead of running against Arabic text.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // On the light surface the full highlight flashes; a softer one reads as
    // the same shimmer without the glare.
    final light = Theme.of(context).brightness == Brightness.light;
    final highlight = light
        ? Color.lerp(palette.skeletonBase, palette.skeletonHighlight, 0.55)!
        : palette.skeletonHighlight;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final begin = Alignment(-1 - 2 * (1 - t), 0);
        final end = Alignment(1 - 2 * (1 - t), 0);
        return _block(
          palette.skeletonBase,
          LinearGradient(
            begin: rtl ? Alignment(-end.x, 0) : begin,
            end: rtl ? Alignment(-begin.x, 0) : end,
            colors: [palette.skeletonBase, highlight, palette.skeletonBase],
            stops: const [0.35, 0.5, 0.65],
          ),
        );
      },
    );
  }

  Widget _block(Color base, Gradient? gradient) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: base,
        gradient: gradient,
        borderRadius: widget.borderRadius,
      ),
    );
  }
}
