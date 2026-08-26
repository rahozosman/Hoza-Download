import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/constants/app_info.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/download_record.dart';
import '../../../../data/models/download_status.dart';
import '../../../../shared/widgets/animated_metric.dart';
import '../../../../shared/widgets/download_progress_bar.dart';
import '../../../../shared/widgets/fade_slide_in.dart';
import '../../../../shared/widgets/hoza_button.dart';
import '../../../../shared/widgets/hoza_card.dart';
import 'media_header.dart';

/// The sheet once a download has started.
///
/// Every figure shown comes from the record the engine updates, so the sheet
/// cannot claim progress that is not happening.
class DownloadProgressView extends StatelessWidget {
  const DownloadProgressView({
    super.key,
    required this.record,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
    required this.onOpen,
    required this.onShare,
    required this.onClose,
    required this.onViewDownloads,
    this.holdReason,
    this.flyFrom,
  });

  final DownloadRecord record;

  /// Where the poster was on screen before this sheet opened — the row that
  /// was tapped — so it can fly into place instead of appearing.
  final Rect? flyFrom;

  /// Why the queue is not starting work right now, if anything is holding it.
  final String? holdReason;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  /// Once the file is on the device: play it, or hand it to another app.
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onClose;
  final VoidCallback onViewDownloads;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same lit identity card as the link sheet, so the two halves of the
        // flow read as one surface.
        HozaCard(
          glow: true,
          padding: const EdgeInsets.all(Gap.sm),
          child: MediaHeader(
            source: record.source,
            title: record.title,
            mediaType: record.mediaType,
            thumbnailUrl: record.thumbnailUrl,
            subtitle: '${record.quality}  •  ${record.format.label}',
            flyFrom: flyFrom,
          ),
        ),
        const SizedBox(height: Gap.lg),
        switch (record.status) {
          DownloadStatus.completed => _CompletedBlock(
            record: record,
            onOpen: onOpen,
            onShare: onShare,
            onClose: onClose,
            onViewDownloads: onViewDownloads,
          ),
          DownloadStatus.failed || DownloadStatus.cancelled => _StoppedBlock(
            record: record,
            onRetry: onRetry,
            onClose: onClose,
          ),
          _ => _RunningBlock(
            record: record,
            holdReason: holdReason,
            onPause: onPause,
            onResume: onResume,
            onCancel: onCancel,
          ),
        },
      ],
    );
  }
}

class _RunningBlock extends StatelessWidget {
  const _RunningBlock({
    required this.record,
    required this.holdReason,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final DownloadRecord record;
  final String? holdReason;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final paused = record.status == DownloadStatus.paused;
    final queued = record.status == DownloadStatus.queued;

    // A wait always states its cause: no connection, mobile data with Wi-Fi
    // only on, or simply a full queue.
    // A queued download may carry a note about what the queue is doing for it
    // — re-reading a link, moving to another server — which beats a generic
    // wait; the network hold still comes first, because it explains more.
    final label = switch (record.status) {
      DownloadStatus.queued =>
        holdReason ?? record.errorMessage ?? 'Waiting for a free slot…',
      DownloadStatus.paused => holdReason ?? 'Paused',
      _ => 'Downloading…',
    };
    final waiting =
        holdReason != null && record.status != DownloadStatus.downloading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    if (waiting) ...[
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 14,
                        color: palette.warning,
                      ),
                      const SizedBox(width: Gap.xxs),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          color: paused || waiting
                              ? palette.warning
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedMetric(
              value: record.progress == null ? null : record.progress! * 100,
              format: (percent) => '${percent.round()}%',
              style: AppTypography.display.copyWith(
                color: paused ? palette.warning : palette.accent,
                fontSize: 26,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        DownloadProgressBar(
          progress: queued ? 0 : record.progress,
          color: paused ? palette.warning : palette.accent,
          height: 8,
          speedBytesPerSecond: record.status == DownloadStatus.downloading
              ? record.speedBytesPerSecond
              : null,
        ),
        const SizedBox(height: Gap.sm),
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
              // The speed's colour says what the number says: lit when it
              // is fast, dim when it has all but stopped.
              AnimatedMetric(
                value: record.speedBytesPerSecond,
                format: Formatters.speed,
                style: AppTypography.metric.copyWith(
                  color: speedColor(palette, record.speedBytesPerSecond),
                ),
              ),
              if (record.etaSeconds != null) ...[
                const SizedBox(width: Gap.sm),
                AnimatedMetric(
                  value: record.etaSeconds!.toDouble(),
                  format: (seconds) =>
                      'ETA ${Formatters.duration(seconds.round())}',
                  style: AppTypography.metric.copyWith(
                    color: palette.textTertiary,
                  ),
                ),
              ],
            ],
          ],
        ),
        const SizedBox(height: Gap.lg),
        Row(
          children: [
            Expanded(
              child: HozaButton(
                label: paused ? 'Resume' : 'Pause',
                icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                variant: HozaButtonVariant.secondary,
                onPressed: queued ? null : (paused ? onResume : onPause),
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: HozaButton(
                label: 'Cancel',
                icon: Icons.close_rounded,
                variant: HozaButtonVariant.danger,
                onPressed: onCancel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CompletedBlock extends StatelessWidget {
  const _CompletedBlock({
    required this.record,
    required this.onOpen,
    required this.onShare,
    required this.onClose,
    required this.onViewDownloads,
  });

  final DownloadRecord record;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onClose;
  final VoidCallback onViewDownloads;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final size = Formatters.bytes(record.totalBytes ?? record.downloadedBytes);

    return FadeSlideIn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CompletionMark(),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Download complete',
                        style: AppTypography.title.copyWith(
                          color: palette.success,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${record.fileName}  •  $size',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          // Says where the file actually went, so the user can find it in any
          // file manager rather than having to hunt for it.
          Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 13,
                color: palette.textTertiary,
              ),
              const SizedBox(width: Gap.xxs),
              Expanded(
                child: Text(
                  '${AppInfo.downloadFolder}/${record.mediaType.folderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: palette.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          // The reward: the file, ready. Opening it is the primary action and
          // carries its size, so the button says exactly what it will hand
          // over; sharing sits beside it.
          Row(
            children: [
              Expanded(
                flex: 3,
                child: HozaButton(
                  label: 'Open  ·  $size',
                  icon: Icons.play_arrow_rounded,
                  onPressed: onOpen,
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                flex: 2,
                child: HozaButton(
                  label: 'Share',
                  icon: Icons.ios_share_rounded,
                  variant: HozaButtonVariant.secondary,
                  onPressed: onShare,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              Expanded(
                child: HozaButton(
                  label: 'Done',
                  variant: HozaButtonVariant.ghost,
                  onPressed: onClose,
                ),
              ),
              Expanded(
                child: HozaButton(
                  label: 'View downloads',
                  icon: Icons.download_rounded,
                  variant: HozaButtonVariant.ghost,
                  onPressed: onViewDownloads,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoppedBlock extends StatelessWidget {
  const _StoppedBlock({
    required this.record,
    required this.onRetry,
    required this.onClose,
  });

  final DownloadRecord record;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final cancelled = record.status == DownloadStatus.cancelled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              cancelled ? Icons.block_rounded : Icons.error_outline_rounded,
              color: cancelled ? palette.textTertiary : palette.danger,
              size: 20,
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  cancelled
                      ? 'Download cancelled'
                      : (record.errorMessage ?? 'Download failed'),
                  style: AppTypography.body.copyWith(
                    color: cancelled
                        ? palette.textSecondary
                        : palette.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        Row(
          children: [
            Expanded(
              child: HozaButton(
                label: 'Close',
                variant: HozaButtonVariant.secondary,
                onPressed: onClose,
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: HozaButton(
                label: 'Download again',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The moment a download finishes: a ring closes, a check draws itself
/// inside it, and a small burst of the brand colours leaves the mark.
///
/// One short sequence, played once — the success is the message, and the
/// motion only has to make it land. Under reduced motion the finished mark
/// is simply shown.
class _CompletionMark extends StatefulWidget {
  const _CompletionMark();

  /// The whole sequence: ring, check, and the burst fading out.
  static const Duration _length = Duration(milliseconds: 900);

  @override
  State<_CompletionMark> createState() => _CompletionMarkState();
}

class _CompletionMarkState extends State<_CompletionMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _CompletionMark._length,
  );

  static const double _size = 44;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.reduceMotion) {
        _controller.value = 1;
        return;
      }
      // A soft tap under the finger as the ring closes: felt, not just seen.
      HapticFeedback.lightImpact();
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return SizedBox(
      width: _size,
      height: _size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _CompletionPainter(
            progress: _controller.value,
            still: context.reduceMotion,
            ring: palette.success,
            fill: palette.successSoft,
            check: palette.success,
            sparks: [palette.accent, palette.success, palette.accentAlt],
          ),
        ),
      ),
    );
  }
}

class _CompletionPainter extends CustomPainter {
  const _CompletionPainter({
    required this.progress,
    required this.still,
    required this.ring,
    required this.fill,
    required this.check,
    required this.sparks,
  });

  final double progress;
  final bool still;
  final Color ring;
  final Color fill;
  final Color check;
  final List<Color> sparks;

  static const int _sparkCount = 12;
  static const double _stroke = 2.6;

  /// Where each stage sits on the timeline.
  static const Interval _fillStage = Interval(0.0, 0.35, curve: Curves.easeOut);
  static const Interval _ringStage = Interval(
    0.05,
    0.55,
    curve: Curves.easeInOutCubic,
  );
  static const Interval _checkStage = Interval(
    0.42,
    0.80,
    curve: Curves.easeOutCubic,
  );
  static const Interval _burstStage = Interval(
    0.30,
    1.0,
    curve: Curves.easeOut,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width / 2 - _stroke;

    final fillT = _fillStage.transform(progress);
    final ringT = _ringStage.transform(progress);
    final checkT = _checkStage.transform(progress);
    final burstT = _burstStage.transform(progress);

    // The burst first, so the mark sits on top of it: twelve sparks leaving
    // the ring, slowing as they go and fading as they slow.
    if (!still && burstT > 0 && burstT < 1) {
      for (var i = 0; i < _sparkCount; i++) {
        final angle = (i / _sparkCount) * 2 * math.pi - math.pi / 2;
        final reach = radius * (1.1 + 1.25 * burstT);
        final position =
            centre + Offset(math.cos(angle), math.sin(angle)) * reach;
        final alpha = (1 - burstT) * 0.9;
        final dot = 1.6 + 1.4 * (1 - burstT);
        canvas.drawCircle(
          position,
          dot,
          Paint()..color = sparks[i % sparks.length].withValues(alpha: alpha),
        );
      }
    }

    // The soft disc grows in under everything.
    if (fillT > 0) {
      canvas.drawCircle(centre, radius * fillT, Paint()..color = fill);
    }

    // The ring closes clockwise from the top: the download's own circle,
    // finishing.
    if (ringT > 0) {
      final rect = Rect.fromCircle(center: centre, radius: radius);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * ringT,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..color = ring,
      );
    }

    // Then the check draws itself, short stroke first, long stroke after.
    if (checkT > 0) {
      final w = size.width;
      final h = size.height;
      final path = Path()
        ..moveTo(w * 0.30, h * 0.52)
        ..lineTo(w * 0.44, h * 0.66)
        ..lineTo(w * 0.70, h * 0.36);
      final metric = path.computeMetrics().first;
      final drawn = metric.extractPath(0, metric.length * checkT);
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke + 0.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = check,
      );
    }
  }

  @override
  bool shouldRepaint(_CompletionPainter old) =>
      old.progress != progress ||
      old.still != still ||
      old.ring != ring ||
      old.fill != fill ||
      old.check != check;
}
