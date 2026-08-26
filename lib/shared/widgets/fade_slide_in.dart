import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';

/// Entrance animation for list items and page sections.
///
/// One short fade + upward slide, optionally staggered by [index]. The stagger
/// is capped so a long list never delays its last row noticeably.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 12,
    this.duration = Motion.base,
    this.step = Motion.stagger,
  });

  final Widget child;
  final int index;
  final double offset;
  final Duration duration;

  /// The gap between one item's entrance and the next's. Tighter for a grid
  /// of small tiles, looser for a column of cards.
  final Duration step;

  static const int _maxStaggeredItems = 8;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// Built once, not per build: a [CurvedAnimation] subscribes to its parent,
  /// so creating one on every rebuild would pile listeners onto the controller
  /// each time the theme or a provider repaints the tree.
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: Motion.emphasized,
  );

  @override
  void initState() {
    super.initState();
    final steps = widget.index.clamp(0, FadeSlideIn._maxStaggeredItems);
    final delay = widget.step * steps;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;

    return FadeTransition(
      opacity: _curved,
      child: AnimatedBuilder(
        animation: _curved,
        builder: (context, child) {
          final remaining = 1 - _curved.value;
          return Transform.translate(
            offset: Offset(0, widget.offset * remaining),
            // A whisper of scale on the way in; enough to feel like the card
            // settles, not enough to read as a zoom.
            child: Transform.scale(scale: 1 - 0.012 * remaining, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}
