import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';
import '../../data/models/download_status.dart';

/// A short wash of colour over a surface the moment its status changes.
///
/// A row that goes from queued to downloading to done changes a pill and a
/// bar, which the eye can miss in a list. The pulse — the new status's own
/// colour, in for 120 ms and gone in 300 — is what makes the change a moment
/// rather than a difference to notice later. Nothing happens on first build,
/// and nothing under reduced motion.
class StatusPulse extends StatefulWidget {
  const StatusPulse({
    super.key,
    required this.status,
    required this.color,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });

  final DownloadStatus status;

  /// The hue of the new status, washed over the surface at low opacity.
  final Color color;
  final Widget child;
  final BorderRadius borderRadius;

  static const Duration _rise = Duration(milliseconds: 120);
  static const Duration _fall = Duration(milliseconds: 300);
  static const double _peak = 0.16;

  @override
  State<StatusPulse> createState() => _StatusPulseState();
}

class _StatusPulseState extends State<StatusPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: StatusPulse._rise,
    reverseDuration: StatusPulse._fall,
  );

  @override
  void didUpdateWidget(StatusPulse old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status && !context.reduceMotion) {
      _controller
        ..stop()
        ..forward(from: 0).then((_) {
          if (mounted) _controller.reverse();
        });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_controller.value);
                if (t == 0) return const SizedBox.shrink();
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color.withValues(
                      alpha: StatusPulse._peak * t,
                    ),
                    borderRadius: widget.borderRadius,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
