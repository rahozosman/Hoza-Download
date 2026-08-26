import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';

/// Places on screen that things fly to.
///
/// Held as global keys because the sender — a sheet, a list tile — and the
/// receiver — the nav bar — never share a parent that could hand the position
/// down. A key with no live widget behind it simply means "nothing to fly to",
/// and the flight lands on a fallback instead.
abstract final class FlightTargets {
  /// The Downloads icon in the bottom bar.
  static final GlobalKey downloadsTab = GlobalKey(debugLabel: 'downloadsTab');

  /// The Hoza mark in the Home masthead, where the splash's mark lands.
  static final GlobalKey homeMark = GlobalKey(debugLabel: 'homeMark');

  /// True while the splash's mark is still in the air, so the masthead keeps
  /// its own mark hidden until the flying one lands on it.
  static final ValueNotifier<bool> homeMarkInFlight = ValueNotifier(false);
}

/// Moves a picture of something from one place on screen to another.
///
/// Hero animations only run between page routes, and Hoza's sheets are not
/// pages — so this is the hero for a sheet: an overlay copy of the thumbnail
/// that rises out of where it was and settles where it is going, on an arc,
/// shrinking or growing to fit. Two moments use it: a download starting (the
/// poster flies into the Downloads tab, which then bumps its badge) and a
/// list tile opening (its poster becomes the sheet's poster).
abstract final class Flight {
  /// The global rectangle of the widget behind [key], or null when it is not
  /// on screen right now.
  static Rect? rectOf(GlobalKey? key) {
    final context = key?.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  /// Flies [child] from [from] to wherever [key] turns out to be.
  ///
  /// For a destination that is not on screen yet — the Home masthead while
  /// the shell is still being pushed. The copy holds at [from] and asks after
  /// the key every frame for up to [wait]; the moment it has a rectangle, it
  /// flies. If it never gets one it fades where it stands.
  static Future<void> runToKey(
    BuildContext context, {
    required Rect from,
    required GlobalKey key,
    required Widget child,
    Duration wait = const Duration(milliseconds: 900),
    Duration duration = const Duration(milliseconds: 560),
    Curve curve = Motion.emphasized,
    BorderRadius borderRadius = Radii.tileRadius,
    double lift = 0,
  }) async {
    if (context.reduceMotion) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final target = ValueNotifier<Rect?>(null);
    final done = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _HeldFlightWidget(
        from: from,
        target: target,
        duration: duration,
        curve: curve,
        borderRadius: borderRadius,
        lift: lift,
        onDone: () {
          entry.remove();
          if (!done.isCompleted) done.complete();
        },
        child: child,
      ),
    );
    overlay.insert(entry);

    // Look for the landing spot frame by frame; it appears as soon as the
    // shell has laid out once.
    final deadline = DateTime.now().add(wait);
    while (target.value == null && DateTime.now().isBefore(deadline)) {
      await WidgetsBinding.instance.endOfFrame;
      target.value = rectOf(key);
    }
    if (target.value == null) target.value = from;
    return done.future;
  }

  /// Flies [child] from [from] to [to]. Resolves when it has landed. Under
  /// reduced motion it resolves at once and nothing is drawn.
  static Future<void> run(
    BuildContext context, {
    required Rect from,
    required Rect to,
    required Widget child,
    Duration duration = const Duration(milliseconds: 520),
    Curve curve = Motion.emphasized,
    BorderRadius borderRadius = Radii.tileRadius,
    double endOpacity = 1,
    double lift = 36,
  }) async {
    if (context.reduceMotion) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final done = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlightWidget(
        from: from,
        to: to,
        duration: duration,
        curve: curve,
        borderRadius: borderRadius,
        endOpacity: endOpacity,
        lift: lift,
        onDone: () {
          entry.remove();
          if (!done.isCompleted) done.complete();
        },
        child: child,
      ),
    );
    overlay.insert(entry);
    return done.future;
  }
}

class _FlightWidget extends StatefulWidget {
  const _FlightWidget({
    required this.from,
    required this.to,
    required this.duration,
    required this.curve,
    required this.borderRadius,
    required this.endOpacity,
    required this.lift,
    required this.onDone,
    required this.child,
  });

  final Rect from;
  final Rect to;
  final Duration duration;
  final Curve curve;
  final BorderRadius borderRadius;
  final double endOpacity;
  final double lift;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_FlightWidget> createState() => _FlightWidgetState();
}

class _FlightWidgetState extends State<_FlightWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = widget.curve.transform(_controller.value);
          final rect = Rect.lerp(widget.from, widget.to, t)!;
          // Rises first, then descends onto the target: an arc reads as
          // "carried", where a straight line reads as "slid".
          final arc = math.sin(t * math.pi) * widget.lift;
          final opacity = widget.endOpacity == 1
              ? 1.0
              : 1 - (1 - widget.endOpacity) * Curves.easeIn.transform(t);

          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect.shift(Offset(0, -arc)),
                child: Opacity(
                  opacity: opacity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: widget.borderRadius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28 * (1 - t)),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: widget.borderRadius,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: widget.from.width,
                          height: widget.from.height,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A flight whose destination arrives after it has taken off.
///
/// Holds at [from] — breathing slightly, so it never looks frozen — until
/// [target] is set, then flies there. A target equal to [from] means "no
/// landing spot was found": the copy simply fades out in place.
class _HeldFlightWidget extends StatefulWidget {
  const _HeldFlightWidget({
    required this.from,
    required this.target,
    required this.duration,
    required this.curve,
    required this.borderRadius,
    required this.lift,
    required this.onDone,
    required this.child,
  });

  final Rect from;
  final ValueNotifier<Rect?> target;
  final Duration duration;
  final Curve curve;
  final BorderRadius borderRadius;
  final double lift;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_HeldFlightWidget> createState() => _HeldFlightWidgetState();
}

class _HeldFlightWidgetState extends State<_HeldFlightWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Rect? _to;

  @override
  void initState() {
    super.initState();
    widget.target.addListener(_onTarget);
    _onTarget();
  }

  void _onTarget() {
    final to = widget.target.value;
    if (to == null || _to != null) return;
    setState(() => _to = to);
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    widget.target.removeListener(_onTarget);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final to = _to;
    final fading = to != null && to == widget.from;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = widget.curve.transform(_controller.value);
          final rect = to == null
              ? widget.from
              : Rect.lerp(widget.from, to, t)!;
          final arc = math.sin(t * math.pi) * widget.lift;
          final opacity = fading ? 1 - t : 1.0;
          final radius = to == null
              ? widget.borderRadius
              : BorderRadius.lerp(
                  BorderRadius.circular(widget.from.shortestSide * 0.22),
                  BorderRadius.circular(to.shortestSide * 0.22),
                  t,
                )!;

          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect.shift(Offset(0, -arc)),
                child: Opacity(
                  opacity: opacity,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: widget.from.width,
                        height: widget.from.height,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}
