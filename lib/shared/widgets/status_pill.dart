import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/status_visuals.dart';
import '../../data/models/download_status.dart';

/// Compact status badge: icon + word, tinted by state.
///
/// The word is always present so status never depends on colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.dense = false});

  final DownloadStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visuals = StatusVisuals.of(status, context.colors);

    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standard,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Gap.xs : Gap.sm,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: visuals.background,
        borderRadius: Radii.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visuals.icon, size: dense ? 11 : 13, color: visuals.foreground),
          const SizedBox(width: Gap.xxs),
          Text(
            visuals.label,
            style: AppTypography.label.copyWith(
              color: visuals.foreground,
              fontSize: dense ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }
}
