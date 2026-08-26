import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_typography.dart';
import 'hoza_button.dart';
import 'state_art.dart';

/// Shared layout for the "nothing here" and "something went wrong" states.
///
/// Every empty state answers three questions: what is empty, why, and what the
/// user can do next.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.tone = StateTone.neutral,
    this.compact = false,
    this.art,
  });

  /// A line drawing shown in place of the icon mark. The icon still names the
  /// state for assistive tech.
  final StateArt? art;

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final StateTone tone;

  /// Tighter spacing when the view sits inside a card rather than a page.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final (fg, bg) = switch (tone) {
      StateTone.neutral => (palette.textSecondary, palette.surfaceMuted),
      StateTone.accent => (palette.accent, palette.accentSoft),
      StateTone.error => (palette.danger, palette.dangerSoft),
    };

    return Semantics(
      container: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: compact ? Gap.lg : Gap.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (art != null)
              StateIllustration(
                art!,
                width: compact ? 104 : 136,
                tone: tone == StateTone.error ? palette.danger : null,
              )
            else
              _PulseMark(icon: icon, foreground: fg, background: bg),
            SizedBox(height: compact ? Gap.md : Gap.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.title.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? Gap.md : Gap.lg),
              HozaButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: tone == StateTone.error
                    ? HozaButtonVariant.secondary
                    : HozaButtonVariant.primary,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum StateTone { neutral, accent, error }

/// A small icon mark that fades and scales in once, then rests.
///
/// Deliberately restrained: no looping animation competing with the content.
class _PulseMark extends StatefulWidget {
  const _PulseMark({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  State<_PulseMark> createState() => _PulseMarkState();
}

class _PulseMarkState extends State<_PulseMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.slow,
  );

  late final Animation<double> _in = CurvedAnimation(
    parent: _controller,
    curve: Motion.emphasized,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.background,
        shape: BoxShape.circle,
      ),
      child: Icon(widget.icon, size: 28, color: widget.foreground),
    );

    if (context.reduceMotion) return mark;

    return FadeTransition(
      opacity: _in,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.82, end: 1).animate(_in),
        child: mark,
      ),
    );
  }
}
