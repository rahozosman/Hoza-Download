import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_typography.dart';
import 'edge_glow.dart';
import 'press_scale.dart';

/// Visual weight of a [HozaButton].
enum HozaButtonVariant { primary, secondary, ghost, danger }

/// What the button is currently reporting. The state is driven by real work —
/// [HozaButtonState.success] must never be shown before the work succeeded.
enum HozaButtonState { idle, loading, success, error }

/// The one button in the app.
///
/// Handles hierarchy, press feedback, and the loading/success/error swap so no
/// screen has to re-implement it.
class HozaButton extends StatelessWidget {
  const HozaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = HozaButtonVariant.primary,
    this.state = HozaButtonState.idle,
    this.expand = true,
    this.successLabel = 'Done',
    this.errorLabel = 'Try again',
    this.edgeGlow = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final HozaButtonVariant variant;
  final HozaButtonState state;

  /// Stretch to the available width. Off for inline actions in a row.
  final bool expand;

  final String successLabel;
  final String errorLabel;

  /// Whether a primary action carries the travelling edge light. Turn it off
  /// where two primaries share a row, so only one thing pulls the eye.
  final bool edgeGlow;

  bool get _busy => state == HozaButtonState.loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !_busy;

    // A primary action rises into its brand colours as it becomes available
    // and sinks back out of them when it does not. That change is the clearest
    // signal the app has for "you can press this now" — worth easing between
    // rather than cutting between two fills, which is what a form with one
    // field is really waiting to tell you.
    if (variant != HozaButtonVariant.primary) {
      return _frame(context, enabled, enabled || _busy ? 1 : 0);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: enabled || _busy ? 1 : 0),
      duration: context.motion(Motion.base),
      curve: Motion.standard,
      builder: (context, lit, _) => _frame(context, enabled, lit),
    );
  }

  /// The button at a given point between resting and fully lit.
  Widget _frame(BuildContext context, bool enabled, double lit) {
    final palette = context.colors;
    final isPrimary = variant == HozaButtonVariant.primary;

    final (bg, baseForeground, border) = _colors(palette);

    // Where a primary action rests when it cannot be pressed: the same inset
    // well every other unavailable control in the app sits in, rather than a
    // faded version of the live colour, which only ever reads as "faded".
    final fg = isPrimary
        ? Color.lerp(palette.textTertiary, baseForeground, lit)!
        : (enabled || _busy
              ? baseForeground
              : baseForeground.withValues(alpha: 0.5));

    // The fill lives on the Material itself, so the ink ripple paints above it
    // rather than behind a decorated child. Material animates colour and shape
    // changes on its own, which covers the enabled/disabled swap.
    final shape = RoundedRectangleBorder(
      borderRadius: Radii.cardRadius,
      side: border == null ? BorderSide.none : BorderSide(color: border),
    );

    // Only the primary action wears the brand gradient — that is what makes it
    // read as the primary action. Its two stops travel out of the resting well
    // and into the brand ramp together.
    final gradient = isPrimary
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(palette.surfaceMuted, palette.accent, lit)!,
              Color.lerp(palette.surfaceMuted, palette.accentAlt, lit)!,
            ],
          )
        : null;

    // A primary action casts light onto the page it sits on, and the light
    // comes up with the fill. Only while it is actually pressable: a disabled
    // button that still glows is a lie.
    final halo = isPrimary && enabled && lit > 0
        ? [
            BoxShadow(
              color: palette.glow.withValues(alpha: palette.glow.a * lit),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ]
        : null;

    Widget buttonWith(VoidCallback? pulse) => Semantics(
      button: true,
      enabled: enabled,
      // Announce the busy state; the visual spinner alone is not enough.
      label: _busy ? '$label, in progress' : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: Radii.cardRadius,
          boxShadow: halo,
        ),
        child: Material(
          color: gradient != null
              ? Colors.transparent
              : (enabled || _busy ? bg : bg.withValues(alpha: 0.4)),
          shape: shape,
          animationDuration: Motion.fast,
          // Ink paints the gradient onto the Material itself, so the ripple still
          // lands on top of it instead of behind it.
          child: Ink(
            decoration: gradient == null
                ? null
                : BoxDecoration(
                    gradient: gradient,
                    borderRadius: Radii.cardRadius,
                  ),
            child: InkWell(
              onTap: enabled
                  ? () {
                      pulse?.call();
                      onPressed!();
                    }
                  : null,
              customBorder: shape,
              splashColor: fg.withValues(alpha: 0.10),
              highlightColor: fg.withValues(alpha: 0.05),
              child: Container(
                height: Layout.minTouchTarget + 4,
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                alignment: Alignment.center,
                child: _content(context, fg),
              ),
            ),
          ),
        ),
      ),
    );

    // A primary press is confirmed with a beat: the button compresses,
    // springs back, and a ring of its own colour leaves it and dissolves —
    // the visible twin of the haptic, so the tap reads as having *done*
    // something before the app has answered.
    final button = isPrimary
        ? _PressPulse(
            color: palette.accent,
            borderRadius: Radii.cardRadius,
            builder: buttonWith,
          )
        : buttonWith(null);

    // The edge light belongs to the primary action only, and only while it can
    // actually be pressed — on a busy or disabled button it would promise
    // something that is not there.
    // Every pressable thing in the app dips the same way under a finger.
    final pressable = PressScale.follow(
      scale: 0.98,
      active: enabled,
      child: button,
    );

    final glowed = isPrimary && edgeGlow
        ? EdgeGlow(active: enabled, child: pressable)
        : pressable;

    return expand ? SizedBox(width: double.infinity, child: glowed) : glowed;
  }

  (Color, Color, Color?) _colors(HozaPalette p) {
    switch (variant) {
      case HozaButtonVariant.primary:
        return (p.accent, p.onAccent, null);
      case HozaButtonVariant.secondary:
        return (p.surfaceMuted, p.textPrimary, p.borderStrong);
      case HozaButtonVariant.ghost:
        return (Colors.transparent, p.textSecondary, null);
      case HozaButtonVariant.danger:
        return (p.dangerSoft, p.danger, p.danger.withValues(alpha: 0.4));
    }
  }

  Widget _content(BuildContext context, Color fg) {
    final palette = context.colors;

    final (text, leading) = switch (state) {
      HozaButtonState.loading => (
        label,
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: fg),
        ),
      ),
      HozaButtonState.success => (
        successLabel,
        Icon(Icons.check_rounded, size: 18, color: palette.success),
      ),
      HozaButtonState.error => (
        errorLabel,
        Icon(Icons.refresh_rounded, size: 18, color: fg),
      ),
      HozaButtonState.idle => (
        label,
        icon == null ? null : Icon(icon, size: 18, color: fg),
      ),
    };

    return AnimatedSwitcher(
      duration: Motion.fast,
      switchInCurve: Motion.standard,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Row(
        key: ValueKey<String>('${state.name}|$text'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: Gap.xs)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.button.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// The confirmation beat on a primary button.
///
/// Compress to 0.96 in the first third, spring back over the rest, and send
/// a ring out from the edge that widens and fades in about 200 ms. One
/// controller, one curve, no state left behind.
class _PressPulse extends StatefulWidget {
  const _PressPulse({
    required this.color,
    required this.borderRadius,
    required this.builder,
  });

  final Color color;
  final BorderRadius borderRadius;
  final Widget Function(VoidCallback pulse) builder;

  @override
  State<_PressPulse> createState() => _PressPulseState();
}

class _PressPulseState extends State<_PressPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  void _pulse() {
    if (context.reduceMotion) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Down fast, back with a little overshoot.
        final scale = t < 0.3
            ? 1 - 0.04 * Curves.easeOut.transform(t / 0.3)
            : 0.96 + 0.04 * Curves.elasticOut.transform((t - 0.3) / 0.7);
        // The ring sets off as the button rebounds.
        final ringT = ((t - 0.22) / 0.78).clamp(0.0, 1.0);
        final ringEased = Curves.easeOut.transform(ringT);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.scale(
              scale: _controller.isAnimating ? scale : 1,
              child: child,
            ),
            if (_controller.isAnimating && ringT > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 1 + 0.24 * ringEased,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: widget.borderRadius,
                        border: Border.all(
                          color: widget.color.withValues(
                            alpha: 0.6 * (1 - ringEased),
                          ),
                          width: 2 - ringEased,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: widget.builder(_pulse),
    );
  }
}
