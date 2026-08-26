import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';

/// Reveals its child the first time it scrolls into view.
///
/// Unlike a plain entrance animation, the reveal is driven by the enclosing
/// scrollable: rows further down the page wait until they are actually about to
/// be read, so a long list keeps producing motion as the user scrolls instead of
/// firing everything at once on the first frame. Outside a scrollable — a sheet,
/// a dialog — it degrades to a straight entrance.
class ScrollReveal extends StatefulWidget {
  const ScrollReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 26,
    this.scaleFrom = 0.98,
    this.duration = Motion.slow,
  });

  final Widget child;

  /// Stagger step for the first screenful only; items revealed later by an
  /// actual scroll play immediately, because the user is already looking.
  final int index;

  /// How far the child travels up into place.
  final double offset;

  final double scaleFrom;
  final Duration duration;

  static const int _maxStaggeredItems = 6;

  /// The child reveals once its top edge is this far inside the viewport, so
  /// the motion finishes before it reaches comfortable reading height.
  static const double _revealMargin = 40;

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.emphasized,
  );

  ScrollableState? _scrollable;
  ScrollPosition? _position;
  bool _revealed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_revealed) return;

    if (context.reduceMotion) {
      _revealed = true;
      _detach();
      _controller.value = 1;
      return;
    }

    final scrollable = Scrollable.maybeOf(context);
    if (identical(scrollable?.position, _position)) return;

    _detach();
    _scrollable = scrollable;
    _position = scrollable?.position;

    if (_position == null) {
      _reveal(staggered: true);
      return;
    }

    _position!.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check(staggered: true);
    });
  }

  void _onScroll() => _check(staggered: false);

  void _check({required bool staggered}) {
    if (_revealed || !mounted) return;
    if (_isInView()) _reveal(staggered: staggered);
  }

  bool _isInView() {
    final box = context.findRenderObject();
    final viewport = _scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return false;
    }

    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    return top < viewport.size.height - ScrollReveal._revealMargin;
  }

  void _reveal({required bool staggered}) {
    if (_revealed) return;
    _revealed = true;
    _detach();

    final steps = staggered
        ? widget.index.clamp(0, ScrollReveal._maxStaggeredItems)
        : 0;
    final delay = Motion.stagger * steps;
    if (delay == Duration.zero) {
      _controller.forward();
      return;
    }
    Future<void>.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  void _detach() {
    _position?.removeListener(_onScroll);
    _position = null;
  }

  @override
  void dispose() {
    _detach();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;

    // A child can be laid out without another scroll event ever arriving — a
    // list that shrinks, a tab that becomes visible. Re-checking after every
    // build of an unrevealed child means it can never be left at zero opacity.
    if (!_revealed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _check(staggered: false);
      });
    }

    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - t)),
            child: Transform.scale(
              scale: lerpDouble(widget.scaleFrom, 1, t),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
