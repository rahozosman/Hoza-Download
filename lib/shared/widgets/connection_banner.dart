import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_typography.dart';
import '../../data/providers/downloads_provider.dart';

/// A slim strip that appears when downloads cannot run.
///
/// Covers both causes — no connection at all, and mobile data while Wi-Fi-only
/// is on — so the user is never left guessing why the queue is sitting still.
/// It slides away by itself the moment work can continue.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hold = ref.watch(downloadHoldProvider);
    final palette = context.colors;

    return AnimatedSize(
      duration: context.motion(Motion.base),
      curve: Motion.standard,
      alignment: Alignment.topCenter,
      child: hold == null
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: Gap.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: Gap.xs,
                ),
                decoration: BoxDecoration(
                  color: palette.warningSoft,
                  borderRadius: Radii.tileRadius,
                  border: Border.all(
                    color: palette.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: palette.warning,
                    ),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: Text(
                        hold,
                        style: AppTypography.caption.copyWith(
                          color: palette.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
