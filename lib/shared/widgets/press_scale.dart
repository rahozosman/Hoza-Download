import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';

/// Adds the app-wide press feedback: a small, fast scale-down.
///
/// Used on cards and custom tappable surfaces where an [InkWell] ripple alone
/// does not read as premium. Respects reduced-motion by simply not scaling.
///
/// Two forms. The default owns the tap: it is the gesture surface, and calls
/// [onTap]. [PressScale.follow] owns nothing — it only watches the pointer
/// and dips while it is down — for surfaces that already handle their own
/// taps and ripples, like buttons and chips, so every tappable thing in the
/// app answers a finger the same way.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.975,
    this.semanticLabel,
  }) : _follow = false,
       active = true;

  /// Scales with the pointer but leaves the tap to the child.
  const PressScale.follow({
    super.key,
    required this.child,
    this.scale = 0.975,
    this.active = true,
  }) : onTap = null,
       onLongPress = null,
       semanticLabel = null,
       _follow = true;

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;

  /// For [PressScale.follow]: whether the surface currently responds at all.
  /// A disabled control should not dip under a finger.
  final bool active;

  final bool _follow;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  bool get _enabled => widget._follow ? widget.active : widget.onTap != null;

  void _setPressed(bool value) {
    if (_pressed == value || !_enabled) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final target = _pressed && !context.reduceMotion ? widget.scale : 1.0;

    final scaled = AnimatedScale(
      scale: target,
      duration: Motion.fast,
      curve: Motion.standard,
      child: widget.child,
    );

    if (widget._follow) {
      // Raw pointer events sit outside the gesture arena, so the child's own
      // InkWell still wins its tap and paints its ripple.
      return Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: scaled,
      );
    }

    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: scaled,
      ),
    );
  }
}
