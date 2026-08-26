import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_typography.dart';

/// Title row above a list section, with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.actionLabel,
    this.onAction,
  });

  final String title;

  /// Optional badge showing how many items the section holds.
  final int? count;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        children: [
          // The same accent tick the masthead and the Settings groups carry.
          // Repeating it down the left edge is what makes a page of separate
          // blocks read as one column.
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              gradient: palette.brandGradient,
              borderRadius: Radii.pillRadius,
            ),
          ),
          const SizedBox(width: Gap.xs),
          Text(
            title,
            style: AppTypography.sectionTitle.copyWith(
              color: palette.textPrimary,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: Gap.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: palette.accentSoft,
                borderRadius: Radii.pillRadius,
              ),
              // A count that changes should be seen changing — it is the one
              // number on Home that reports work arriving.
              child: AnimatedSwitcher(
                duration: context.motion(Motion.fast),
                switchInCurve: Motion.springy,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Text(
                  '$count',
                  key: ValueKey<int>(count!),
                  style: AppTypography.label.copyWith(
                    color: palette.accent,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
