import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/download_record.dart';
import '../../../../shared/widgets/hoza_bottom_sheet.dart';
import '../../../../shared/widgets/hoza_button.dart';
import '../../../../shared/widgets/hoza_card.dart';

/// What the user chose when a file with the same name already exists.
enum DuplicateChoice { openExisting, downloadAgain, cancel }

/// Asks what to do about a file that is already on the device.
///
/// Hoza never silently overwrites: the existing file stays put unless the user
/// explicitly downloads again, and a second copy is saved under a numbered
/// name rather than replacing the first.
Future<DuplicateChoice> showDuplicateSheet(
  BuildContext context,
  DownloadRecord existing,
) async {
  final choice = await showHozaSheet<DuplicateChoice>(
    context: context,
    builder: (_) => _DuplicateSheet(existing: existing),
  );
  return choice ?? DuplicateChoice.cancel;
}

class _DuplicateSheet extends StatelessWidget {
  const _DuplicateSheet({required this.existing});

  final DownloadRecord existing;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return HozaSheet(
      title: 'File already exists',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You already have this file saved. Downloading again keeps both '
            'copies — the new one gets a numbered name.',
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: Gap.md),
          HozaCard(
            padding: const EdgeInsets.all(Gap.sm),
            color: palette.surfaceMuted,
            child: Row(
              children: [
                HozaIconTile(
                  icon: Icons.insert_drive_file_outlined,
                  background: palette.successSoft,
                  foreground: palette.success,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        existing.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${Formatters.bytes(existing.totalBytes)}  •  '
                        '${Formatters.timestamp(existing.completedAt ?? existing.createdAt)}',
                        style: AppTypography.caption.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          HozaButton(
            label: 'Open existing',
            icon: Icons.play_circle_outline_rounded,
            onPressed: () =>
                Navigator.of(context).pop(DuplicateChoice.openExisting),
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              Expanded(
                child: HozaButton(
                  label: 'Cancel',
                  variant: HozaButtonVariant.ghost,
                  onPressed: () =>
                      Navigator.of(context).pop(DuplicateChoice.cancel),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: HozaButton(
                  label: 'Download again',
                  variant: HozaButtonVariant.secondary,
                  onPressed: () =>
                      Navigator.of(context).pop(DuplicateChoice.downloadAgain),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
