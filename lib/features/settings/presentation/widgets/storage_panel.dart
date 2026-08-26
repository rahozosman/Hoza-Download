import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/providers/downloads_provider.dart';
import '../../../../shared/widgets/skeleton.dart';

/// How much space Hoza's downloads take, and how much is left on the device.
///
/// Both figures are read from the device rather than estimated, and the row is
/// simply omitted when the platform cannot report them.
class StoragePanel extends ConsumerWidget {
  const StoragePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(storageUsageProvider);
    final palette = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      child: usage.when(
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton.line(width: 130),
            SizedBox(height: Gap.sm),
            Skeleton(height: 8),
          ],
        ),
        error: (_, _) => Text(
          'Storage details are unavailable.',
          style: AppTypography.caption.copyWith(color: palette.textTertiary),
        ),
        data: (value) {
          final device = value.device;
          final fraction = device.isKnown && device.totalBytes > 0
              ? (value.usedByApp / device.totalBytes).clamp(0.0, 1.0)
              : null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.pie_chart_outline_rounded,
                    size: 20,
                    color: palette.textSecondary,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      'Used by Hoza Download',
                      style: AppTypography.body.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    Formatters.bytes(value.usedByApp),
                    style: AppTypography.metric.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
              if (fraction != null) ...[
                const SizedBox(height: Gap.sm),
                ClipRRect(
                  borderRadius: Radii.pillRadius,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: fraction),
                    duration: context.motion(Motion.slow),
                    curve: Motion.standard,
                    builder: (context, animated, _) => LinearProgressIndicator(
                      value: animated,
                      minHeight: 8,
                      backgroundColor: palette.surfaceMuted,
                      color: palette.accent,
                    ),
                  ),
                ),
              ],
              if (device.isKnown) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  '${Formatters.bytes(device.freeBytes)} free of '
                  '${Formatters.bytes(device.totalBytes)} on this device',
                  style: AppTypography.caption.copyWith(
                    color: palette.textTertiary,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
