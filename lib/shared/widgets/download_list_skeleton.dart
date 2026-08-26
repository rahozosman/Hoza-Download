import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import 'skeleton.dart';

/// Placeholder rows shown while download history is read back from the
/// database.
///
/// Standing in for the real rows is honest about what is coming; showing the
/// "no downloads yet" empty state before the read finishes would not be.
class DownloadListSkeleton extends StatelessWidget {
  const DownloadListSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading downloads',
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : Gap.sm),
              child: const _SkeletonTile(),
            ),
        ],
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Container(
      padding: const EdgeInsets.all(Gap.sm),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(width: 68, height: 42),
          const SizedBox(width: Gap.sm),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton.line(),
                SizedBox(height: Gap.xs),
                Skeleton.line(width: 140),
                SizedBox(height: Gap.sm),
                Skeleton.line(width: 90),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
