import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/downloads_provider.dart';
import '../../../shared/widgets/hoza_bottom_sheet.dart';
import '../../../shared/widgets/state_views.dart';
import '../../shell/presentation/shell_controller.dart';
import 'widgets/download_progress_view.dart';

/// Follows one download: progress, pause/resume/cancel, and how it ended.
///
/// Used both inside the link sheet after the user confirms and on its own when
/// an in-flight download is tapped in a list.
class DownloadStage extends ConsumerWidget {
  const DownloadStage({
    super.key,
    required this.downloadId,
    required this.onClose,
    required this.onViewDownloads,
    this.flyFrom,
  });

  final String downloadId;

  /// Where the poster was on screen before the sheet opened, if a row was
  /// tapped to get here.
  final Rect? flyFrom;
  final VoidCallback onClose;
  final VoidCallback onViewDownloads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(downloadRecordProvider(downloadId));

    // The record can only vanish if it was removed from history elsewhere.
    if (record == null) {
      return StateView(
        icon: Icons.info_outline_rounded,
        title: 'Download removed',
        message: 'This download is no longer in your history.',
        actionLabel: 'Close',
        onAction: onClose,
        compact: true,
      );
    }

    final controller = ref.read(downloadsProvider.notifier);

    // Light taps confirm the control landed even before the state catches up.
    void tap(Future<void> Function(String id) action) {
      HapticFeedback.selectionClick();
      action(downloadId);
    }

    return DownloadProgressView(
      record: record,
      flyFrom: flyFrom,
      onPause: () => tap(controller.pause),
      onResume: () => tap(controller.resume),
      onCancel: () {
        HapticFeedback.mediumImpact();
        controller.cancel(downloadId);
      },
      onRetry: () => tap(controller.retry),
      onOpen: () {
        HapticFeedback.selectionClick();
        controller.openFile(downloadId);
      },
      onShare: () {
        HapticFeedback.selectionClick();
        controller.shareFile(downloadId);
      },
      holdReason: ref.watch(downloadHoldProvider),
      onClose: onClose,
      onViewDownloads: onViewDownloads,
    );
  }
}

/// Opens [DownloadStage] as a standalone sheet.
Future<void> showDownloadSheet(
  BuildContext context,
  String downloadId, {
  Rect? flyFrom,
}) {
  return showHozaSheet<void>(
    context: context,
    builder: (_) => _DownloadSheet(downloadId: downloadId, flyFrom: flyFrom),
  );
}

class _DownloadSheet extends ConsumerWidget {
  const _DownloadSheet({required this.downloadId, this.flyFrom});

  final String downloadId;
  final Rect? flyFrom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(downloadRecordProvider(downloadId));

    void close() => Navigator.of(context).maybePop();

    return HozaSheet(
      title: record?.source ?? 'Download',
      trailing: IconButton(
        onPressed: close,
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Close',
      ),
      child: DownloadStage(
        downloadId: downloadId,
        flyFrom: flyFrom,
        onClose: close,
        onViewDownloads: () {
          ref.read(shellTabProvider.notifier).select(ShellTab.downloads);
          close();
        },
      ),
    );
  }
}
