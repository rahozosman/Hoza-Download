import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_typography.dart';
import '../../../data/models/download_filter.dart';
import '../../../data/models/download_record.dart';
import '../../../data/models/download_status.dart';
import '../../../data/providers/downloads_provider.dart';
import '../../../shared/widgets/connection_banner.dart';
import '../../../shared/widgets/download_list_skeleton.dart';
import '../../../shared/widgets/download_tile.dart';
import '../../../shared/widgets/flight_overlay.dart';
import '../../../shared/widgets/hoza_button.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../../shared/widgets/scroll_reveal.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/state_art.dart';
import '../../../shared/widgets/state_views.dart';
import '../../downloader/presentation/download_sheet.dart';
import '../../shell/presentation/app_shell.dart';
import '../../shell/presentation/shell_controller.dart';
import 'widgets/download_dialogs.dart';
import 'widgets/downloads_toolbar.dart';

/// Full download history, grouped by what each transfer is actually doing.
///
/// Four groups in one scroll rather than four tabs: at any moment most of them
/// are empty, and a tab that is usually empty still costs a tap to find out.
/// The order puts everything that still wants something from you above the
/// archive, which is why failures sit above completed downloads.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;

  /// Carries the "and delete the file" answer from the confirmation to the
  /// dismissal, which happen either side of the swipe-out animation.
  final Map<String, bool> _pendingDeleteFile = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (!_searching) {
      _searchController.clear();
      ref.read(downloadSearchProvider.notifier).clear();
    }
  }

  Future<void> _handleAction(
    DownloadRecord record,
    DownloadTileAction action,
  ) async {
    switch (action) {
      case DownloadTileAction.rename:
        final name = await promptRename(
          context,
          currentFileName: record.fileName,
        );
        if (name == null || !mounted) return;
        final applied = await ref
            .read(downloadsProvider.notifier)
            .rename(record.id, name);
        if (!mounted) return;
        _notify(
          applied == null
              ? 'That file could not be renamed.'
              : 'Renamed to $applied',
        );

      case DownloadTileAction.retry:
        await ref.read(downloadsProvider.notifier).retry(record.id);
        if (!mounted) return;
        _notify('Retrying download');

      case DownloadTileAction.delete:
        final unfinished = !record.status.isTerminal;
        final choice = await promptDelete(
          context,
          fileName: record.fileName,
          unfinished: unfinished,
          hasFile: (record.filePath ?? '').isNotEmpty,
        );
        if (!choice.confirmed || !mounted) return;
        HapticFeedback.mediumImpact();
        await ref
            .read(downloadsProvider.notifier)
            .remove(record.id, deleteFile: choice.deleteFile);
        if (!mounted) return;
        _notify(
          unfinished
              ? 'Download stopped'
              : choice.deleteFile
              ? 'Download and file deleted'
              : 'Removed from history',
        );

      case DownloadTileAction.open:
        final opened = await ref
            .read(downloadsProvider.notifier)
            .openFile(record.id);
        if (!mounted || opened) return;
        _notify('No app on this device can open that file.');

      case DownloadTileAction.share:
        final shared = await ref
            .read(downloadsProvider.notifier)
            .shareFile(record.id);
        if (!mounted || shared) return;
        _notify('That file could not be shared.');

      case DownloadTileAction.openSource:
        final opened = await ref
            .read(downloadsProvider.notifier)
            .openSource(record.id);
        if (!mounted || opened) return;
        _notify('That link could not be opened.');
    }
  }

  /// Swipe asks the same question the menu does, so the shortcut can never
  /// remove more than the long way round would.
  Future<bool> _confirmSwipe(DownloadRecord record) async {
    final choice = await promptDelete(
      context,
      fileName: record.fileName,
      unfinished: !record.status.isTerminal,
      hasFile: (record.filePath ?? '').isNotEmpty,
    );
    if (!choice.confirmed) return false;

    _pendingDeleteFile[record.id] = choice.deleteFile;
    HapticFeedback.mediumImpact();
    return true;
  }

  Future<void> _completeSwipe(DownloadRecord record) async {
    final deleteFile = _pendingDeleteFile.remove(record.id) ?? false;
    await ref
        .read(downloadsProvider.notifier)
        .remove(record.id, deleteFile: deleteFile);
    if (!mounted) return;
    _notify(deleteFile ? 'Download and file deleted' : 'Removed from history');
  }

  Future<void> _retryAll() async {
    final sent = await ref.read(downloadsProvider.notifier).retryAllFailed();
    if (!mounted) return;
    _notify(sent == 1 ? 'Retrying 1 download' : 'Retrying $sent downloads');
  }

  /// Tapping a row does the obvious thing for its state: play a finished file,
  /// and open the progress sheet for everything else — which is where a
  /// stopped download is offered again.
  /// One key per row's artwork, so the sheet a row opens can lift the
  /// picture out of the row. Keys are kept, not recreated, or the flight
  /// would measure a widget that no longer exists.
  final Map<String, GlobalKey> _posterKeys = {};

  GlobalKey _posterKeyFor(String id) =>
      _posterKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'poster-$id'));

  void _openRecord(DownloadRecord record) {
    if (record.status == DownloadStatus.completed) {
      unawaited(_handleAction(record, DownloadTileAction.open));
      return;
    }
    showDownloadSheet(
      context,
      record.id,
      flyFrom: Flight.rectOf(_posterKeys[record.id]),
    );
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(sortedDownloadsProvider);
    final records = ref.watch(visibleDownloadsProvider);
    final filter = ref.watch(downloadFilterProvider);
    final query = ref.watch(downloadSearchProvider);
    final hydrated = ref.watch(downloadsHydratedProvider);
    final canRetry = ref.watch(retryableDownloadsProvider).isNotEmpty;

    final counts = <DownloadFilter, int>{
      for (final value in DownloadFilter.values)
        value: all.where(value.matches).length,
    };

    final rows = _rowsFor(records, canRetry: canRetry);

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.maxContentWidth),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Layout.pagePadding,
                  Gap.xs,
                  Layout.pagePadding,
                  Gap.sm,
                ),
                child: DownloadsToolbar(
                  searching: _searching,
                  onToggleSearch: _toggleSearch,
                  searchController: _searchController,
                  onSearchChanged: (value) =>
                      ref.read(downloadSearchProvider.notifier).update(value),
                  filter: filter,
                  onFilterSelected: (value) =>
                      ref.read(downloadFilterProvider.notifier).select(value),
                  counts: counts,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Layout.pagePadding),
                child: ConnectionBanner(),
              ),
              Expanded(
                child: Stack(
                  children: [
                    !hydrated
                        ? const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: Layout.pagePadding,
                              vertical: Gap.xs,
                            ),
                            child: DownloadListSkeleton(count: 4),
                          )
                        : rows.isEmpty
                        ? _EmptyView(
                            hasHistory: all.isNotEmpty,
                            query: query,
                            filter: filter,
                            onClearSearch: _toggleSearch,
                            onGoHome: () => ref
                                .read(shellTabProvider.notifier)
                                .select(ShellTab.home),
                          )
                        : _AnimatedRows(
                            rows: rows,
                            padding: EdgeInsets.fromLTRB(
                              Layout.pagePadding,
                              Gap.xs,
                              Layout.pagePadding,
                              // Room for the retry pill above the nav bar.
                              shellContentInset(context) +
                                  (canRetry ? Gap.xxl + Gap.md : 0),
                            ),
                            buildRow: _buildRow,
                            onRefresh: () =>
                                ref.read(downloadsProvider.notifier).refresh(),
                          ),
                    // The whole recovery after a bad connection, where the
                    // thumb already is: a pill just above the bar, in only
                    // while there is something to retry.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: shellContentInset(context) + Gap.xs,
                      child: Center(
                        child: _RetryPill(
                          visible: hydrated && canRetry,
                          count: ref.watch(retryableDownloadsProvider).length,
                          onPressed: _retryAll,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Flattened so the list stays lazily built: a long history should not have
  /// to construct every group before the first one can be painted.
  List<_Row> _rowsFor(List<DownloadRecord> records, {required bool canRetry}) {
    final groups = <_Group>[
      _Group(
        'Active',
        records
            .where(
              (record) =>
                  record.status == DownloadStatus.downloading ||
                  record.status == DownloadStatus.paused,
            )
            .toList(),
      ),
      _Group(
        'Queued',
        records
            .where((record) => record.status == DownloadStatus.queued)
            .toList(),
      ),
      _Group(
        'Failed',
        records
            .where(
              (record) =>
                  record.status == DownloadStatus.failed ||
                  record.status == DownloadStatus.cancelled,
            )
            .toList(),
        // The whole recovery lives in the pill at the foot of the screen,
        // within a thumb's reach, not up here where the group header is.
      ),
      _Group(
        'Completed',
        records
            .where((record) => record.status == DownloadStatus.completed)
            .toList(),
      ),
    ];

    return [
      for (final group in groups)
        if (group.records.isNotEmpty) ...[
          _HeaderRow(group),
          for (final record in group.records) _TileRow(record),
        ],
    ];
  }

  Widget _buildRow(_Row row, int index) {
    return switch (row) {
      _HeaderRow(group: final group) => Padding(
        // Groups after the first need air above them; the first sits straight
        // under the filter rail.
        padding: EdgeInsets.only(top: index == 0 ? 0 : Gap.lg),
        child: ScrollReveal(
          index: index,
          child: SectionHeader(title: group.title, count: group.records.length),
        ),
      ),
      _TileRow(record: final record) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: ScrollReveal(
          key: ValueKey<String>('reveal-${record.id}'),
          index: index,
          child: _SwipeToRemove(
            record: record,
            onConfirm: () => _confirmSwipe(record),
            onDismissed: () => unawaited(_completeSwipe(record)),
            child: DownloadTile(
              record: record,
              allowedActions: DownloadTileAction.values,
              posterKey: _posterKeyFor(record.id),
              onTap: () => _openRecord(record),
              onAction: (action) => _handleAction(record, action),
            ),
          ),
        ),
      ),
    };
  }
}

/// One status group, with the records that landed in it.
@immutable
class _Group {
  const _Group(this.title, this.records);

  final String title;
  final List<DownloadRecord> records;
}

sealed class _Row {
  const _Row();

  /// Stable identity across rebuilds, so the animated list can tell a row
  /// that moved from one that merely changed.
  String get key;
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.group);

  final _Group group;

  @override
  String get key => 'h:${group.title}';
}

class _TileRow extends _Row {
  const _TileRow(this.record);

  final DownloadRecord record;

  @override
  String get key => 't:${record.id}';
}

/// Swipe from the trailing edge to remove a row.
///
/// A shortcut for the menu, not a second way in: it asks the same question,
/// and only the answer travels with the gesture.
class _SwipeToRemove extends StatelessWidget {
  const _SwipeToRemove({
    required this.record,
    required this.onConfirm,
    required this.onDismissed,
    required this.child,
  });

  final DownloadRecord record;
  final Future<bool> Function() onConfirm;
  final VoidCallback onDismissed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Dismissible(
      key: ValueKey<String>('swipe-${record.id}'),
      direction: DismissDirection.endToStart,
      // Far enough that a stray horizontal flick while scrolling cannot arm a
      // deletion by accident.
      dismissThresholds: const {DismissDirection.endToStart: 0.4},
      confirmDismiss: (_) => onConfirm(),
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: Gap.lg),
        decoration: BoxDecoration(
          // Flattened against the card surface so the panel stays opaque over
          // the page wash instead of showing it through.
          color: Color.alphaBlend(palette.dangerSoft, palette.surfaceElevated),
          borderRadius: Radii.cardRadius,
          border: Border.all(color: palette.danger.withValues(alpha: 0.35)),
        ),
        // The icon alone leaves the gesture ambiguous right up to the moment
        // it fires; the word says what letting go will do.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: palette.danger, size: 20),
            const SizedBox(width: Gap.xs),
            Text(
              'Remove',
              style: AppTypography.caption.copyWith(color: palette.danger),
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Empty states differ by cause: nothing downloaded, nothing matching the
/// filter, or nothing matching the search.
class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.hasHistory,
    required this.query,
    required this.filter,
    required this.onClearSearch,
    required this.onGoHome,
  });

  final bool hasHistory;
  final String query;
  final DownloadFilter filter;
  final VoidCallback onClearSearch;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isNotEmpty) {
      return _centered(
        StateView(
          icon: Icons.search_off_rounded,
          art: StateArt.search,
          title: 'No matches',
          message: 'Nothing here matches "${query.trim()}".',
          actionLabel: 'Clear search',
          onAction: onClearSearch,
        ),
      );
    }

    if (hasHistory) {
      return _centered(
        StateView(
          icon: Icons.filter_alt_off_rounded,
          art: StateArt.filter,
          title: 'Nothing in ${filter.label}',
          message: 'You have downloads, just none of this kind yet.',
        ),
      );
    }

    return _centered(
      StateView(
        icon: Icons.download_rounded,
        art: StateArt.emptyTray,
        title: 'No downloads yet',
        message:
            'Share a supported link to Hoza Download, or paste one on the '
            'Home tab to get started.',
        actionLabel: 'Go to Home',
        onAction: onGoHome,
        tone: StateTone.accent,
      ),
    );
  }

  Widget _centered(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: Gap.xxl),
      child: Center(child: child),
    );
  }
}

/// "Retry N failed", floating above the nav bar while there is anything to
/// retry. Slides up into reach and drops away when the last failure is gone.
class _RetryPill extends StatelessWidget {
  const _RetryPill({
    required this.visible,
    required this.count,
    required this.onPressed,
  });

  final bool visible;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.2),
        duration: context.motion(Motion.slow),
        curve: visible ? Motion.emphasized : Motion.exit,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: context.motion(Motion.base),
          child: HozaButton(
            label: count == 1 ? 'Retry 1 failed' : 'Retry $count failed',
            icon: Icons.refresh_rounded,
            expand: false,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

/// The list, with rows that leave and arrive instead of being redrawn.
///
/// When a download finishes it moves from *Active* to *Completed*. Rebuilt
/// plainly, it would simply be somewhere else on the next frame. Here the
/// row folds shut where it was, the headers close the gap, and it unfolds
/// where it now belongs — wearing a green edge for a second, so the eye that
/// followed it down knows it has settled. Pull down to re-read the history;
/// the Hoza ring at the top sweeps while it does.
class _AnimatedRows extends StatefulWidget {
  const _AnimatedRows({
    required this.rows,
    required this.padding,
    required this.buildRow,
    required this.onRefresh,
  });

  final List<_Row> rows;
  final EdgeInsets padding;
  final Widget Function(_Row row, int index) buildRow;
  final Future<void> Function() onRefresh;

  @override
  State<_AnimatedRows> createState() => _AnimatedRowsState();
}

class _AnimatedRowsState extends State<_AnimatedRows> {
  final GlobalKey<AnimatedListState> _list = GlobalKey<AnimatedListState>();

  /// What the list is showing, kept in step with [widget.rows] through
  /// insert and remove calls rather than replaced wholesale.
  late List<_Row> _shown = List<_Row>.of(widget.rows);

  /// Rows that just arrived in Completed, still wearing their glow.
  final Set<String> _settling = {};

  RefreshIndicatorStatus? _refresh;

  static const Duration _foldFor = Duration(milliseconds: 240);
  static const Duration _settleFor = Duration(milliseconds: 1100);

  @override
  void didUpdateWidget(covariant _AnimatedRows old) {
    super.didUpdateWidget(old);
    _reconcile(widget.rows);
  }

  /// Removals first, back to front, then insertions front to back — a row
  /// that moved is removed from where it was and inserted where it is, which
  /// is exactly the fold-and-unfold the eye should see.
  void _reconcile(List<_Row> next) {
    final list = _list.currentState;
    final nextKeys = {for (final row in next) row.key};

    if (list == null) {
      _shown = List<_Row>.of(next);
      return;
    }

    for (var i = _shown.length - 1; i >= 0; i--) {
      if (nextKeys.contains(_shown[i].key)) continue;
      final gone = _shown.removeAt(i);
      list.removeItem(
        i,
        (context, animation) => _fold(animation, widget.buildRow(gone, i)),
        duration: context.motion(_foldFor),
      );
    }

    final shownKeys = {for (final row in _shown) row.key};
    for (var i = 0; i < next.length; i++) {
      final row = next[i];
      if (shownKeys.contains(row.key)) {
        // Same row, possibly new figures: keep the list's copy current.
        final at = _shown.indexWhere((r) => r.key == row.key);
        if (at >= 0) _shown[at] = row;
        continue;
      }
      _shown.insert(i, row);
      list.insertItem(i, duration: context.motion(_foldFor));
      if (row is _TileRow && row.record.status == DownloadStatus.completed) {
        _settling.add(row.key);
        Future<void>.delayed(_settleFor + _foldFor, () {
          if (mounted) setState(() => _settling.remove(row.key));
        });
      }
    }
  }

  Widget _fold(Animation<double> animation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Motion.standard);
    return SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: curved, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: widget.onRefresh,
          onStatusChange: (status) => setState(() => _refresh = status),
          child: AnimatedList(
            key: _list,
            padding: widget.padding,
            initialItemCount: _shown.length,
            physics: const AlwaysScrollableScrollPhysics(),
            itemBuilder: (context, index, animation) {
              if (index >= _shown.length) return const SizedBox.shrink();
              final row = _shown[index];
              final child = widget.buildRow(row, index);
              return _fold(
                animation,
                _settling.contains(row.key)
                    ? _SettleGlow(duration: _settleFor, child: child)
                    : child,
              );
            },
          ),
        ),
        Positioned(
          top: Gap.sm,
          left: 0,
          right: 0,
          child: Center(child: _RefreshMark(status: _refresh)),
        ),
      ],
    );
  }
}

/// A green edge that lights and fades once, on a row that has just landed
/// in Completed.
class _SettleGlow extends StatelessWidget {
  const _SettleGlow({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: context.motion(duration),
      curve: Curves.easeOutCubic,
      builder: (context, glow, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: Radii.cardRadius,
          boxShadow: glow <= 0
              ? null
              : [
                  BoxShadow(
                    color: palette.success.withValues(alpha: 0.45 * glow),
                    blurRadius: 18 * glow,
                    spreadRadius: 1.5 * glow,
                  ),
                ],
        ),
        child: child,
      ),
      child: child,
    );
  }
}

/// The Hoza ring at the top of the list while it is being pulled: empty as
/// the pull arms, sweeping while the history is re-read, closed with a check
/// when it is done.
class _RefreshMark extends StatelessWidget {
  const _RefreshMark({required this.status});

  final RefreshIndicatorStatus? status;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final visible = switch (status) {
      RefreshIndicatorStatus.armed ||
      RefreshIndicatorStatus.snap ||
      RefreshIndicatorStatus.refresh ||
      RefreshIndicatorStatus.done => true,
      _ => false,
    };
    final ringStatus = switch (status) {
      RefreshIndicatorStatus.refresh => DownloadStatus.downloading,
      RefreshIndicatorStatus.done => DownloadStatus.completed,
      _ => DownloadStatus.queued,
    };

    return IgnorePointer(
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: context.motion(Motion.base),
        curve: visible ? Motion.springy : Motion.exit,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ProgressRing(
            status: ringStatus,
            progress: ringStatus == DownloadStatus.downloading ? null : 0,
            size: 30,
          ),
        ),
      ),
    );
  }
}
