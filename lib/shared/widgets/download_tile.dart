import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/status_visuals.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/download_record.dart';
import '../../data/models/download_status.dart';
import 'animated_metric.dart';
import 'download_progress_bar.dart';
import 'progress_ring.dart';
import 'hoza_card.dart';
import 'media_thumbnail.dart';
import 'status_pill.dart';
import 'status_pulse.dart';

/// Actions offered by a tile's overflow menu.
enum DownloadTileAction { open, openSource, share, rename, retry, delete }

/// One download in a list.
///
/// Shows metadata for finished items and live transfer figures while a download
/// is running, from the same record — the tile never fabricates progress.
class DownloadTile extends StatelessWidget {
  const DownloadTile({
    super.key,
    required this.record,
    this.onTap,
    this.onAction,
    this.allowedActions = DownloadTileAction.values,
    this.posterKey,
  });

  final DownloadRecord record;
  final VoidCallback? onTap;
  final void Function(DownloadTileAction action)? onAction;

  /// Identifies the artwork so a sheet opening from this row can lift it
  /// out of the row and land it in the sheet.
  final GlobalKey? posterKey;

  /// Actions the caller can actually carry out. The menu lists nothing it
  /// cannot perform.
  final List<DownloadTileAction> allowedActions;

  bool get _showsProgress =>
      record.status == DownloadStatus.downloading ||
      record.status == DownloadStatus.paused ||
      record.status == DownloadStatus.queued;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final visuals = MediaVisuals.of(record.mediaType, palette);

    // The row wears the hue of what it holds on its edge — blue, green or
    // amber — and flashes its new status colour for a moment when it moves.
    return StatusPulse(
      status: record.status,
      color: StatusVisuals.of(record.status, palette).foreground,
      borderRadius: Radii.cardRadius,
      child: HozaCard(
        onTap: onTap,
        borderColor: Color.alphaBlend(
          visuals.tint.withValues(alpha: 0.28),
          palette.border,
        ),
        semanticLabel:
            '${record.title}, ${record.quality} '
            '${record.format.label}, '
            'status ${record.status.name}',
        padding: const EdgeInsets.all(Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Poster(record: record, posterKey: posterKey),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: Gap.xxs),
                      Text(
                        _metaLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onAction != null)
                  _MoreMenu(
                    record: record,
                    allowedActions: allowedActions,
                    onAction: onAction!,
                  ),
              ],
            ),
            AnimatedSize(
              duration: context.motion(Motion.base),
              curve: Motion.standard,
              alignment: Alignment.topCenter,
              child: _showsProgress
                  ? Padding(
                      padding: const EdgeInsets.only(top: Gap.sm),
                      child: _ProgressBlock(record: record),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: Gap.xs),
            Row(
              children: [
                StatusPill(status: record.status, dense: true),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Text(
                    _trailingLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppTypography.caption.copyWith(
                      color: record.status == DownloadStatus.failed
                          ? palette.danger
                          : palette.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _metaLine {
    final parts = <String>[
      record.quality,
      record.format.label,
      if (record.totalBytes != null) Formatters.bytes(record.totalBytes),
      record.source,
    ];
    return parts.join('  •  ');
  }

  String get _trailingLine {
    if (record.status == DownloadStatus.failed) {
      return record.errorMessage ?? 'Download failed';
    }
    return Formatters.timestamp(record.completedAt ?? record.createdAt);
  }
}

/// The artwork, marked with what kind of file the row is.
///
/// A list of thumbnails all looks like video; the dot is what lets an album of
/// saved audio be picked out of it at a glance. Same mark, same hues as the
/// download sheet, so a row and the sheet it opens agree.
class _Poster extends StatelessWidget {
  const _Poster({required this.record, this.posterKey});

  final DownloadRecord record;
  final GlobalKey? posterKey;

  static const double _width = 68;

  @override
  Widget build(BuildContext context) {
    final visuals = MediaVisuals.of(record.mediaType, context.colors);
    // The ring is the glance: how far, in the media's hue, and a check when
    // it is done. It sits on the artwork's corner so the row reads at the
    // length of a look down the list.
    final showRing = record.status != DownloadStatus.queued;

    return SizedBox(
      width: _width,
      height: _width / (16 / 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            key: posterKey,
            width: _width,
            height: _width / (16 / 10),
            child: MediaThumbnail(
              mediaType: record.mediaType,
              imageUrl: record.thumbnailUrl,
              width: _width,
            ),
          ),
          PositionedDirectional(
            top: 4,
            start: 4,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: visuals.gradient,
              ),
              child: Icon(
                visuals.icon,
                size: 10,
                color: context.colors.onAccent,
              ),
            ),
          ),
          PositionedDirectional(
            bottom: -6,
            end: -6,
            child: AnimatedScale(
              scale: showRing ? 1 : 0,
              duration: context.motion(Motion.base),
              curve: showRing ? Motion.springy : Motion.exit,
              child: ProgressRing(
                status: record.status,
                progress: record.progress,
                color: visuals.tint,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.record});

  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final paused = record.status == DownloadStatus.paused;
    final visuals = MediaVisuals.of(record.mediaType, palette);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DownloadProgressBar(
          progress: record.status == DownloadStatus.queued
              ? 0
              : record.progress,
          // Paused is a state worth calling out in its own colour; otherwise
          // the bar runs in the hue of the thing it is fetching.
          color: paused ? palette.warning : visuals.tint,
          speedBytesPerSecond: record.status == DownloadStatus.downloading
              ? record.speedBytesPerSecond
              : null,
        ),
        const SizedBox(height: Gap.xs),
        Row(
          children: [
            AnimatedMetric(
              value: record.downloadedBytes.toDouble(),
              format: (bytes) =>
                  Formatters.transferred(bytes.round(), record.totalBytes),
              style: AppTypography.metric.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const Spacer(),
            if (record.status == DownloadStatus.downloading) ...[
              AnimatedMetric(
                value: record.speedBytesPerSecond,
                format: Formatters.speed,
                style: AppTypography.metric.copyWith(
                  color: speedColor(palette, record.speedBytesPerSecond),
                ),
              ),
              const SizedBox(width: Gap.xs),
            ],
            AnimatedMetric(
              value: record.progress == null ? null : record.progress! * 100,
              format: (percent) => '${percent.round()}%',
              style: AppTypography.metric.copyWith(
                color: paused ? palette.warning : visuals.tint,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.record,
    required this.allowedActions,
    required this.onAction,
  });

  final DownloadRecord record;
  final List<DownloadTileAction> allowedActions;
  final void Function(DownloadTileAction action) onAction;

  /// Whether the record remembers a web page it came from. A direct file link
  /// has nothing to go back to.
  bool get _hasSourceLink {
    final url = Uri.tryParse(record.sourceUrl);
    if (url == null || url.host.isEmpty) return false;
    final scheme = url.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  /// An action shows only when the caller supports it *and* the record's state
  /// makes it meaningful.
  bool _offers(DownloadTileAction action) {
    if (!allowedActions.contains(action)) return false;
    return switch (action) {
      DownloadTileAction.open ||
      DownloadTileAction.share ||
      DownloadTileAction.rename => record.status == DownloadStatus.completed,
      DownloadTileAction.openSource => _hasSourceLink,
      DownloadTileAction.retry => record.status.canRetry,
      DownloadTileAction.delete => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final items = <PopupMenuEntry<DownloadTileAction>>[
      if (_offers(DownloadTileAction.open))
        _item(
          DownloadTileAction.open,
          Icons.play_circle_outline_rounded,
          'Open',
        ),
      if (_offers(DownloadTileAction.openSource))
        _item(
          DownloadTileAction.openSource,
          Icons.open_in_new_rounded,
          record.source.trim().isEmpty
              ? 'Open original link'
              : 'Open in ${record.source.trim()}',
        ),
      if (_offers(DownloadTileAction.share))
        _item(DownloadTileAction.share, Icons.ios_share_rounded, 'Share'),
      if (_offers(DownloadTileAction.rename))
        _item(
          DownloadTileAction.rename,
          Icons.drive_file_rename_outline_rounded,
          'Rename',
        ),
      if (_offers(DownloadTileAction.retry))
        _item(DownloadTileAction.retry, Icons.refresh_rounded, 'Retry'),
      if (_offers(DownloadTileAction.delete))
        _item(
          DownloadTileAction.delete,
          Icons.delete_outline_rounded,
          'Delete',
          danger: true,
        ),
    ];

    if (items.isEmpty) return const SizedBox(width: Gap.xs);

    return PopupMenuButton<DownloadTileAction>(
      onSelected: onAction,
      tooltip: 'More actions',
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      padding: EdgeInsets.zero,
      itemBuilder: (context) => items,
    );
  }

  PopupMenuItem<DownloadTileAction> _item(
    DownloadTileAction action,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    return PopupMenuItem<DownloadTileAction>(
      value: action,
      height: Layout.minTouchTarget,
      child: Builder(
        builder: (context) {
          final palette = context.colors;
          final color = danger ? palette.danger : palette.textPrimary;
          return Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: Gap.sm),
              Text(label, style: AppTypography.body.copyWith(color: color)),
            ],
          );
        },
      ),
    );
  }
}
