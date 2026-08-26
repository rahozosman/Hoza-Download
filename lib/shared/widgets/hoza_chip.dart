import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_typography.dart';
import 'press_scale.dart';

/// Selectable pill used for filters, media type and quality choices.
///
/// Selection animates fill, border and label weight together in one short
/// transition so the change reads as a single event. A chip that stands for
/// a kind of media carries that kind's hue when selected — blue for video,
/// green for audio, amber for images — so the rail says what it is filtering
/// before the word is read.
class HozaChip extends StatelessWidget {
  const HozaChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    this.trailingLabel,
    this.tint,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Secondary text inside the chip, e.g. an estimated size.
  final String? trailingLabel;

  /// The hue the chip takes when selected. Defaults to the brand accent.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final enabled = onTap != null;
    final hue = tint ?? palette.accent;

    final foreground = !enabled
        ? palette.textTertiary
        : selected
        ? hue
        : palette.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: PressScale.follow(
        scale: 0.96,
        active: enabled,
        // Fill and outline sit on the Material so the ripple lands on top of
        // them; Material tweens both when the selection changes.
        child: Material(
          color: selected
              ? hue.withValues(alpha: palette.accentSoft.a)
              : palette.surfaceMuted,
          animationDuration: Motion.fast,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? hue : palette.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  }
                : null,
            customBorder: const StadiumBorder(),
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: foreground),
                    const SizedBox(width: Gap.xxs + 2),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: Motion.fast,
                    curve: Motion.standard,
                    style: AppTypography.caption.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    child: Text(label),
                  ),
                  if (trailingLabel != null) ...[
                    const SizedBox(width: Gap.xs),
                    Text(
                      trailingLabel!,
                      style: AppTypography.caption.copyWith(
                        color: selected
                            ? hue.withValues(alpha: 0.8)
                            : palette.textTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
