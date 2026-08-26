import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/download_record.dart';
import '../../../../data/models/download_status.dart';
import '../../../../data/providers/downloads_provider.dart';
import '../../../../shared/widgets/download_progress_bar.dart';
import '../../../../shared/widgets/hoza_card.dart';
import '../../../shell/presentation/shell_controller.dart';

/// What Home says about downloads, and the way through to them.
///
/// Home lists nothing itself, so this card carries the whole account: three
/// figures read straight off the records, a line of progress whenever anything
/// is moving, and a way in to the full history. Pasting a link at the top is
/// answered here rather than nowhere.
///
/// Every number counts to its new value rather than snapping, which is what
/// makes a download finishing somewhere off screen still register on this
/// screen. Until there is something true to report, the card says so plainly
/// instead of showing three zeroes.
class HomeStats extends ConsumerWidget {
  const HomeStats({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(sortedDownloadsProvider);
    final running = ref.watch(activeDownloadsProvider);
    final bytes = ref.watch(completedBytesProvider);
    final hydrated = ref.watch(downloadsHydratedProvider);

    final active = running.length;
    final saved = records
        .where((record) => record.status == DownloadStatus.completed)
        .length;

    // Nothing is claimed before the history is actually on hand, so a slow
    // first read never flashes zeroes that are about to be replaced.
    final hasHistory = hydrated && records.isNotEmpty;

    return HozaCard(
      // Lit the whole time it is on screen, like the paste card above it: the
      // two of them are all Home has, so both stay alive rather than waiting
      // to be touched.
      glow: true,
      onTap: () =>
          ref.read(shellTabProvider.notifier).select(ShellTab.downloads),
      semanticLabel: hasHistory
          ? '$saved saved, $active active, '
                '${Formatters.bytes(bytes)} stored. Opens Downloads.'
          : 'No downloads yet. Opens Downloads.',
      padding: const EdgeInsets.symmetric(vertical: Gap.md, horizontal: Gap.xs),
      // The card swaps between having something to report and not, and it does
      // so in place: the surface stays, only what it says changes.
      child: AnimatedSize(
        duration: context.motion(Motion.base),
        curve: Motion.standard,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: context.motion(Motion.base),
          switchInCurve: Motion.standard,
          switchOutCurve: Motion.exit,
          child: hasHistory
              ? _Figures(
                  key: const ValueKey<String>('figures'),
                  saved: saved,
                  active: active,
                  bytes: bytes,
                  running: running,
                )
              : _Waiting(key: const ValueKey<String>('waiting')),
        ),
      ),
    );
  }
}

/// The three figures, the live progress line, and the way in.
class _Figures extends StatelessWidget {
  const _Figures({
    super.key,
    required this.saved,
    required this.active,
    required this.bytes,
    required this.running,
  });

  final int saved;
  final int active;
  final int bytes;
  final List<DownloadRecord> running;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                value: saved.toDouble(),
                label: 'Saved',
                format: (value) => '${value.round()}',
              ),
            ),
            _Divider(color: palette.border),
            Expanded(
              child: _Stat(
                value: active.toDouble(),
                label: 'Active',
                // The one figure that means "something is happening right
                // now", so it is the one allowed to carry the accent.
                highlight: active > 0,
                format: (value) => '${value.round()}',
              ),
            ),
            _Divider(color: palette.border),
            Expanded(
              child: _Stat(
                value: bytes.toDouble(),
                label: 'Stored',
                format: (value) => Formatters.bytes(value.round()),
              ),
            ),
          ],
        ),

        // While something is moving, the card carries how far along it is —
        // one line, across all of it. It is not here at any other time, so its
        // presence is itself the signal that work is running.
        AnimatedSize(
          duration: context.motion(Motion.base),
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: running.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.md, Gap.sm, 0),
                  child: DownloadProgressBar(
                    progress: _combinedProgress(running),
                    height: 4,
                  ),
                ),
        ),

        Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: Divider(height: 1, color: palette.border),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.xs, 0),
          child: Row(
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 15,
                color: palette.textTertiary,
              ),
              const SizedBox(width: Gap.xs),
              Text(
                'All downloads',
                style: AppTypography.caption.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: palette.textTertiary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// How far the running transfers are, taken together.
  ///
  /// Null as soon as one of them has no known size: a bar drawn from a total
  /// that is partly guessed would be a guess itself, and the indeterminate
  /// sweep says "working" without claiming a figure.
  static double? _combinedProgress(List<DownloadRecord> running) {
    var received = 0;
    var total = 0;
    for (final record in running) {
      final size = record.totalBytes;
      if (size == null || size <= 0) return null;
      received += record.downloadedBytes;
      total += size;
    }
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }
}

/// What the card says before anything has been downloaded.
class _Waiting extends StatelessWidget {
  const _Waiting({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
      child: Row(
        children: [
          HozaIconTile(icon: Icons.download_rounded, size: 34),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No downloads yet',
                  style: AppTypography.body.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Paste a link above, or share one from any app.',
                  style: AppTypography.caption.copyWith(
                    color: palette.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: palette.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: color);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.format,
    this.highlight = false,
  });

  final double value;
  final String label;
  final String Function(double value) format;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: context.motion(Motion.slow),
      curve: Motion.standard,
      builder: (context, animated, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            format(animated),
            maxLines: 1,
            textAlign: TextAlign.center,
            // Tabular figures on a number that counts: without them the digits
            // change width as they roll and the whole row twitches.
            style: AppTypography.title.copyWith(
              color: highlight ? palette.accent : palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            style: AppTypography.label.copyWith(color: palette.textTertiary),
          ),
        ],
      ),
    );
  }
}
