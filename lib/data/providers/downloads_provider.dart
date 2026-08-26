import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_info.dart';
import '../../core/utils/app_log.dart';

import '../../core/utils/file_names.dart';
import '../../core/utils/media_titles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/url_expiry.dart';
import '../../features/downloader/data/muxing_download_engine.dart';
import '../../features/downloader/data/source_registry.dart';
import '../../features/downloader/data/shared_download_storage.dart';
import '../../features/downloader/domain/download_engine.dart';
import '../../features/downloader/domain/download_storage.dart';
import '../../features/downloader/domain/source_provider.dart';
import '../../features/downloader/domain/variant_selection.dart';
import '../../services/platform/download_notifications.dart';
import '../../services/platform/download_service_bridge.dart';
import '../../services/platform/network_status.dart';
import '../../services/platform/platform_permissions.dart';
import '../../services/telemetry/failure_reporter.dart';
import '../database/download_dao.dart';
import '../models/download_filter.dart';
import '../models/download_record.dart';
import '../models/download_status.dart';
import '../models/media_option.dart';
import 'settings_provider.dart';

/// Download history plus whether it has been read back from disk yet.
///
/// The flag matters: an empty list before hydration means "still loading", and
/// showing the "no downloads yet" empty state then would be wrong.
@immutable
class DownloadsState {
  const DownloadsState({required this.records, required this.hydrated});

  const DownloadsState.loading() : records = const [], hydrated = false;

  final List<DownloadRecord> records;
  final bool hydrated;

  DownloadsState copyWith({List<DownloadRecord>? records, bool? hydrated}) =>
      DownloadsState(
        records: records ?? this.records,
        hydrated: hydrated ?? this.hydrated,
      );
}

/// What happened when a download was requested.
class EnqueueOutcome {
  const EnqueueOutcome.started(String this.id) : blockedReason = null;
  const EnqueueOutcome.blocked(String this.blockedReason) : id = null;

  /// Set when the download was accepted.
  final String? id;

  /// Set when it was not, with a message the user can act on.
  final String? blockedReason;

  bool get isStarted => id != null;
}

/// Owns every download record and schedules the transfers behind them.
///
/// This is the single source of truth: the UI reads records from here and asks
/// for state changes here, and every transition — queued, downloading, paused,
/// completed, failed, cancelled — is applied in one place so the list can never
/// disagree with what the engine is doing.
class DownloadsController extends Notifier<DownloadsState> {
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, StreamSubscription<DownloadProgress>> _progressSubs = {};

  /// Automatic retries already spent, per download.
  final Map<String, int> _attempts = {};
  final Map<String, Timer> _retryTimers = {};

  /// Downloads this controller paused because of the network, so only those
  /// are resumed when it recovers.
  final Set<String> _heldByNetwork = {};

  /// Downloads whose link is being re-read. They are queued, but must not be
  /// started yet: the address on the record is the one that just failed.
  final Set<String> _refreshing = {};

  DownloadDao? _dao;
  int _sequence = 0;
  bool _disposed = false;

  /// Downloads whose expired address has already been refreshed once this
  /// session, so a source that keeps handing out short-lived links cannot
  /// send a record round in circles.
  final Set<String> _expiryRefreshed = {};

  DownloadEngine get _engine => ref.read(downloadEngineProvider);
  DownloadStorage get _storage => ref.read(downloadStorageProvider);
  DownloadServiceBridge get _service => ref.read(downloadServiceBridgeProvider);
  DownloadNotifications get _notifications =>
      ref.read(downloadNotificationsProvider);

  @override
  DownloadsState build() {
    ref.onDispose(_disposeAll);

    // Raising the concurrency limit should release queued work immediately.
    ref.listen(
      settingsProvider.select((s) => s.maxConcurrentDownloads),
      (_, _) => _pump(),
    );

    // Losing Wi-Fi, or going offline, has to take effect on transfers that are
    // already running — not only on the next one to start.
    ref.listen(downloadHoldProvider, (_, hold) {
      if (hold != null) {
        unawaited(_holdRunning());
      } else {
        _releaseHeld();
      }
    });

    final actions = _service.actions.listen(
      (action) => unawaited(_onNotificationAction(action)),
    );
    ref.onDispose(actions.cancel);

    unawaited(_hydrate());
    return const DownloadsState.loading();
  }

  /// Pauses everything in flight because the network no longer allows it.
  ///
  /// Paused rather than failed: the partial files are kept and the queue picks
  /// them back up as soon as the connection is acceptable again.
  Future<void> _holdRunning() async {
    final running = state.records
        .where((record) => record.status == DownloadStatus.downloading)
        .toList(growable: false);
    for (final record in running) {
      _heldByNetwork.add(record.id);
      await _tasks[record.id]?.pause();
    }
  }

  /// Puts network-paused downloads back in the queue once the connection is
  /// acceptable again.
  ///
  /// Only downloads *this* stopped are resumed — one the user paused by hand
  /// stays paused, because that was their decision, not the network's.
  void _releaseHeld() {
    final held = _heldByNetwork.toList(growable: false);
    _heldByNetwork.clear();

    for (final id in held) {
      if (_find(id)?.status != DownloadStatus.paused) continue;
      _update(
        id,
        (r) => r.copyWith(status: DownloadStatus.queued),
        persist: true,
      );
    }
    _pump();
  }

  /// Reads history back from the database.
  ///
  /// Anything the database says was mid-transfer is corrected to paused first:
  /// nothing is moving at startup, and the list must not claim otherwise. The
  /// partial files are kept, so those downloads can be resumed.
  Future<void> _hydrate() async {
    try {
      final dao = ref.read(downloadDaoProvider);

      final interrupted = await dao.settleInterrupted();
      final stored = await dao.all();
      if (_disposed) return;

      _dao = dao;

      // Transfers the last run never finished: Android stopped the process
      // — low memory, a force-stop, a reboot. Say so where the user will see
      // it, since the progress bar they were watching simply vanished.
      if (interrupted > 0) {
        unawaited(
          _notifications.showInfo(
            id: 'interrupted',
            title: interrupted == 1
                ? 'Download paused'
                : '$interrupted downloads paused',
            text: 'Hoza was stopped before it finished. Tap to resume.',
          ),
        );
      }

      // A share can land before the read finishes. Those records are newer than
      // anything on disk, so they stay on top — and are written now that the
      // database is available.
      final live = state.records;
      final liveIds = live.map((record) => record.id).toSet();
      state = DownloadsState(
        records: [
          ...live,
          ...stored.where((record) => !liveIds.contains(record.id)),
        ],
        hydrated: true,
      );
      for (final record in live) {
        unawaited(_persist(record));
      }

      // Startup is the one moment that knows which downloads are still real,
      // so it is the only place that can tell an orphaned chunk from one a
      // paused transfer is still waiting on.
      unawaited(_sweepOrphanedPartials());
    } catch (error) {
      // A database that will not open must not take the app with it: history
      // is simply empty for this session.
      AppLog.error('Loading download history', error);
      if (!_disposed) state = state.copyWith(hydrated: true);
    }
  }

  /// Re-reads history from disk and nudges the queue — pull-to-refresh.
  ///
  /// Records with a transfer behind them keep their live figures; the rest
  /// are taken as the database has them. Held for a moment even when the
  /// read is instant, so the gesture is seen to do something.
  Future<void> refresh() async {
    final dao = _dao;
    if (dao == null) return;
    final started = DateTime.now();
    try {
      final stored = await dao.all();
      if (_disposed) return;

      final live = {
        for (final record in state.records)
          if (record.status.isActive || _tasks.containsKey(record.id))
            record.id: record,
      };
      final storedIds = stored.map((record) => record.id).toSet();
      state = state.copyWith(
        records: [
          ...state.records.where((record) => !storedIds.contains(record.id)),
          for (final record in stored) live[record.id] ?? record,
        ],
      );
    } catch (error) {
      AppLog.warn('Refreshing history', error);
    }
    _pump();

    const minimum = Duration(milliseconds: 700);
    final elapsed = DateTime.now().difference(started);
    if (elapsed < minimum) await Future<void>.delayed(minimum - elapsed);
  }

  /// Removes cached chunks left behind by a crash or a force-stop.
  ///
  /// Best-effort housekeeping: a failure here costs disk space, never data, so
  /// it must not disturb startup.
  Future<void> _sweepOrphanedPartials() async {
    try {
      final keep = state.records.map((record) => record.id).toSet();
      await _storage.sweepPartials(keep);
    } catch (error) {
      AppLog.warn('Sweeping orphaned partials', error);
    }
  }

  void _disposeAll() {
    _disposed = true;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _heldByNetwork.clear();
    _refreshing.clear();
    for (final subscription in _progressSubs.values) {
      unawaited(subscription.cancel());
    }
    _progressSubs.clear();
    for (final task in _tasks.values) {
      // Paused, not cancelled: partials are kept so work is not thrown away.
      unawaited(task.pause());
    }
    _tasks.clear();
  }

  // ---------------------------------------------------------------- commands

  /// The name a download would be saved under, before any collision handling.
  String fileNameFor(MediaMetadata metadata, MediaVariant variant) =>
      FileNames.sanitizeWithExtension(
        titleFor(metadata),
        variant.format.extension,
      );

  /// The name a download is shown and saved under.
  ///
  /// A site's own title ("TikTok - Make Your Day") is never used: it is the
  /// same on every post, so every video would end up with the same name.
  /// Without a real title, the site and the post's ID name it instead.
  static String titleFor(MediaMetadata metadata) => MediaTitles.resolve(
    title: metadata.title,
    source: metadata.source,
    url: metadata.sourceUrl,
  );

  /// A finished download that already holds this file name, or null.
  ///
  /// A history row alone is not enough — the file has to still be on the
  /// device, otherwise this is not really a duplicate.
  Future<DownloadRecord?> findDuplicate({
    required MediaMetadata metadata,
    required MediaVariant variant,
  }) async {
    final fileName = fileNameFor(metadata, variant);

    final existing =
        await _dao?.findCompleted(
          fileName: fileName,
          mediaType: variant.mediaType,
        ) ??
        _findCompletedNamed(fileName, variant.mediaType);
    if (existing == null) return null;

    final present = await _storage.exists(
      fileName: existing.fileName,
      mediaType: existing.mediaType,
    );
    return present ? existing : null;
  }

  /// Creates a record for [variant] and starts or queues it.
  /// Queues every one of [variants] as one set — a post's photos — and
  /// returns the outcome of the first, which is the one the sheet follows.
  ///
  /// Each photo is its own record with its own file, and the set is what
  /// ties them together in the list. A refusal on the first (no storage
  /// permission, say) applies to all of them, so nothing else is queued.
  Future<EnqueueOutcome> enqueueAll({
    required MediaMetadata metadata,
    required List<MediaVariant> variants,
  }) async {
    if (variants.isEmpty) {
      return const EnqueueOutcome.blocked('Nothing to download.');
    }
    final groupId = variants.length > 1 ? _newId() : null;
    EnqueueOutcome? first;
    for (final variant in variants) {
      final outcome = await enqueue(
        metadata: metadata,
        variant: variant,
        groupId: groupId,
      );
      first ??= outcome;
      if (!outcome.isStarted) break;
    }
    return first!;
  }

  Future<EnqueueOutcome> enqueue({
    required MediaMetadata metadata,
    required MediaVariant variant,
    String? groupId,
  }) async {
    // Ask for storage access before any bytes move, so a refusal costs the
    // user nothing. On Android 10+ this always succeeds without a prompt.
    final writable = await _storage.ensureWritable();
    if (!writable) {
      return const EnqueueOutcome.blocked(
        'Hoza Download needs permission to save files to your device.',
      );
    }
    if (_disposed) {
      return const EnqueueOutcome.blocked('Hoza Download is shutting down.');
    }

    // The progress notification is a nicety, not a requirement — never block
    // the download on it. Once the user answers the permission prompt the
    // bar is posted again, since the first attempt went out before they did.
    unawaited(
      ref.read(platformPermissionsProvider).ensureNotifications().then((
        granted,
      ) {
        if (!granted || _disposed) return;
        _service.invalidate();
        _syncService();
      }),
    );

    final id = _newId();
    final title = titleFor(metadata);

    final record = DownloadRecord(
      id: id,
      sourceUrl: metadata.sourceUrl.toString(),
      downloadUrl: variant.url.toString(),
      supportsResume: variant.supportsResume,
      headers: variant.headers,
      audioUrl: variant.audioUrl?.toString(),
      audioBytes: variant.audioBytes,
      title: title,
      fileName: fileNameFor(metadata, variant),
      source: metadata.source,
      mediaType: variant.mediaType,
      format: variant.format,
      quality: variant.label,
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
      thumbnailUrl: metadata.thumbnailUrl,
      groupId: groupId,
      totalBytes: variant.totalEstimatedBytes,
    );

    state = state.copyWith(records: [record, ...state.records]);
    unawaited(_persist(record));
    _syncService();

    _pump();
    return EnqueueOutcome.started(id);
  }

  Future<void> pause(String id) async {
    final record = _find(id);
    if (record == null || !record.status.canPause) return;
    await _tasks[id]?.pause();
  }

  Future<void> resume(String id) async {
    final record = _find(id);
    if (record == null || !record.status.canResume) return;
    _update(
      id,
      (r) => r.copyWith(status: DownloadStatus.queued),
      persist: true,
    );
    _pump();
  }

  Future<void> cancel(String id) async {
    final record = _find(id);
    if (record == null || !record.status.canCancel) return;

    _cancelRetryTimer(id);

    final task = _tasks[id];
    if (task is _PendingTask) {
      // Start is mid-flight: mark it cancelled so _start bails out when the
      // storage reservation returns, then finish the transition here.
      task.cancelled = true;
    } else if (task != null) {
      await task.cancel();
      return;
    }

    await _discardPartial(id);
    _update(
      id,
      (r) => r.copyWith(status: DownloadStatus.cancelled, clearSpeed: true),
      persist: true,
    );
    _pump();
  }

  /// Starts a stopped download over, re-reading the source link first.
  ///
  /// The stored media URL is not permanent: YouTube and the social CDNs sign
  /// theirs for a few hours, so the address that failed is often simply out of
  /// date. Re-reading the page is what makes "download again" actually
  /// download again instead of failing the same way twice.
  Future<void> retry(String id) async {
    final record = _find(id);
    if (record == null || !record.status.canRetry) return;

    // A deliberate retry starts the automatic budget over.
    _attempts.remove(id);
    _cancelRetryTimer(id);

    _update(
      id,
      (r) => r.copyWith(status: DownloadStatus.queued, clearError: true),
      persist: true,
    );

    // Queued, but held back until the address is known to be current.
    _refreshing.add(id);
    try {
      await _refreshLink(id);
    } finally {
      _refreshing.remove(id);
    }
    if (_disposed) return;

    _pump();
  }

  /// Points a record at a fresh media URL from its source page.
  ///
  /// Returns whether the address actually moved. Best effort: a lookup that
  /// fails leaves the record exactly as it was, so a retry with no connection
  /// still tries the address it already has.
  Future<bool> _refreshLink(String id) async {
    final record = _find(id);
    if (record == null || record.sourceUrl.isEmpty) return false;

    final source = Uri.tryParse(record.sourceUrl);
    if (source == null || !source.hasAuthority) return false;

    final SourceResolution resolution;
    try {
      // A cached answer is the very address that just failed; ask afresh.
      resolution = await ref
          .read(sourceRegistryProvider)
          .resolve(source, fresh: true);
    } on Object catch (error) {
      AppLog.warn('Re-reading a download link', '$error');
      return false;
    }
    if (resolution is! ResolvedMedia || _disposed) return false;

    final metadata = resolution.metadata;
    final variant = _matchVariant(metadata, record);
    if (variant == null) return false;

    // The source still points at the same file, so there is nothing to fix and
    // nothing to gain from starting over.
    if (variant.url.toString() == record.downloadUrl) return false;

    // Whatever is on disk was fetched from the old address, and appending the
    // new file onto it would produce something unplayable.
    await _discardPartial(id);
    if (_disposed) return false;

    _update(
      id,
      (r) => r.copyWith(
        downloadUrl: variant.url.toString(),
        headers: variant.headers,
        audioUrl: variant.audioUrl?.toString(),
        audioBytes: variant.audioBytes,
        clearAudio: variant.audioUrl == null,
        supportsResume: variant.supportsResume,
        totalBytes: variant.totalEstimatedBytes,
        downloadedBytes: 0,
        thumbnailUrl: metadata.thumbnailUrl,
      ),
      persist: true,
    );
    return true;
  }

  /// The variant on the freshly read page that matches what the user chose.
  ///
  /// Sources relabel and drop renditions over time, so an exact match is tried
  /// first, then the nearest resolution, and only then the best on offer.
  MediaVariant? _matchVariant(MediaMetadata metadata, DownloadRecord record) {
    final offered = metadata.variantsFor(record.mediaType);
    if (offered.isEmpty) return null;

    for (final variant in offered) {
      if (variant.label == record.quality) return variant;
    }

    final wanted = _heightOf(record.quality);
    if (wanted != null) {
      final withHeight = offered
          .where((variant) => variant.heightPx != null)
          .toList();
      if (withHeight.isNotEmpty) {
        withHeight.sort(
          (a, b) => (a.heightPx! - wanted).abs().compareTo(
            (b.heightPx! - wanted).abs(),
          ),
        );
        return withHeight.first;
      }
    }

    return VariantSelection.ranked(offered).first;
  }

  /// `1080p60` -> 1080. Null when the label names no resolution.
  static int? _heightOf(String quality) {
    final match = RegExp(r'^(\d{2,5})p').firstMatch(quality.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Removes a download from history, and optionally the saved file with it.
  ///
  /// The file is only ever touched when [deleteFile] is explicitly true, so a
  /// tidy-up of the list can never cost the user their media by accident.
  Future<void> remove(String id, {bool deleteFile = false}) async {
    _cancelRetryTimer(id);
    _attempts.remove(id);

    final record = _find(id);
    final task = _tasks[id];
    if (task != null) await task.cancel();
    await _discardPartial(id);

    final location = record?.filePath;
    if (deleteFile && location != null && location.isNotEmpty) {
      await _storage.deleteFile(location);
    }
    unawaited(_notifications.cancel(id));

    state = state.copyWith(
      records: state.records.where((record) => record.id != id).toList(),
    );
    await _dao?.delete(id);
    _syncService();
    _pump();
  }

  /// Renames the saved file and the history entry together.
  ///
  /// Returns the name the file actually ended up with, or null when the rename
  /// failed — in which case nothing changes, so the list never shows a name
  /// that is not on disk.
  Future<String?> rename(String id, String fileName) async {
    final record = _find(id);
    if (record == null) return null;

    final location = record.filePath;
    if (location == null || location.isEmpty) {
      // Nothing published yet: only the record has a name to change.
      _update(id, (r) => r.copyWith(fileName: fileName), persist: true);
      return fileName;
    }

    final applied = await _storage.rename(
      location: location,
      fileName: fileName,
    );
    if (applied == null) return null;

    _update(id, (r) => r.copyWith(fileName: applied), persist: true);
    return applied;
  }

  /// Offers a finished file to the Android share sheet.
  Future<bool> shareFile(String id) async {
    final record = _find(id);
    final location = record?.filePath;
    if (record == null || location == null || location.isEmpty) return false;
    return _storage.share(location: location, mimeType: record.format.mimeType);
  }

  /// Hands a finished file to whichever app the user has for that media type.
  Future<bool> openFile(String id) async {
    final record = _find(id);
    final location = record?.filePath;
    if (record == null || location == null || location.isEmpty) return false;
    return _storage.open(location: location, mimeType: record.format.mimeType);
  }

  /// Opens the page a download came from in the platform's own app.
  Future<bool> openSource(String id) async {
    final url = sourceLinkOf(_find(id));
    if (url == null) return false;
    return _storage.openLink(url);
  }

  /// The web link a record was downloaded from, when it has a usable one.
  static Uri? sourceLinkOf(DownloadRecord? record) {
    if (record == null) return null;
    final url = Uri.tryParse(record.sourceUrl);
    if (url == null || url.host.isEmpty) return null;
    final scheme = url.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return url;
  }

  /// Drops finished entries. Transfers still running are deliberately kept:
  /// clearing history must not silently abandon work the user started. Files
  /// already saved to the device are untouched.
  Future<void> clearHistory() async {
    final removed = state.records
        .where((r) => r.status.isTerminal)
        .map((r) => r.id)
        .toList();
    if (removed.isEmpty) return;

    for (final id in removed) {
      _cancelRetryTimer(id);
      _attempts.remove(id);
    }

    state = state.copyWith(
      records: state.records.where((r) => !r.status.isTerminal).toList(),
    );
    await _dao?.deleteMany(removed);
  }

  /// Stops every transfer and drops all history, in memory and on disk.
  ///
  /// For the reset flow only. Unlike [clearHistory] this takes running
  /// downloads with it, and files already saved to the device are left exactly
  /// where they are — resetting the app is not the same as deleting someone's
  /// media.
  ///
  /// Deliberately built out of [cancel] and [remove] rather than reaching into
  /// the scheduler's own state: cancelling first marks every record terminal,
  /// so the queue cannot start a fresh transfer as the records disappear
  /// underneath it.
  Future<int> standDown() async {
    final ids = state.records
        .map((record) => record.id)
        .toList(growable: false);
    if (ids.isEmpty) return 0;

    for (final id in ids) {
      await cancel(id);
    }
    for (final id in ids) {
      await remove(id);
    }
    return ids.length;
  }

  /// Puts every download that stopped with an error back in the queue, and
  /// returns how many were sent.
  ///
  /// After a bad connection this is the whole recovery: one action, instead of
  /// hunting each failure down the list. Records that cannot be retried — one
  /// the user cancelled on purpose, say — are left exactly where they are.
  Future<int> retryAllFailed() async {
    final ids = state.records
        .where((record) => record.status.canRetry)
        .map((record) => record.id)
        .toList(growable: false);

    for (final id in ids) {
      await retry(id);
    }
    return ids.length;
  }

  // --------------------------------------------------------------- scheduling

  /// Starts queued downloads while a slot is free.
  ///
  /// The cap comes from settings and is never bypassed, so a burst of shares
  /// cannot saturate the connection.
  void _pump() {
    if (_disposed) return;
    // Offline, or on mobile data with Wi-Fi-only on: queued work waits, and the
    // UI says why instead of silently doing nothing.
    if (ref.read(downloadHoldProvider) != null) return;

    final limit = ref.read(settingsProvider).maxConcurrentDownloads;
    var running = state.records
        .where((record) => record.status == DownloadStatus.downloading)
        .length;

    for (final record in state.records.reversed) {
      if (running >= limit) return;
      if (record.status != DownloadStatus.queued) continue;
      if (_tasks.containsKey(record.id)) continue;
      if (_refreshing.contains(record.id)) continue;
      running++;
      if (_hasExpiredAddress(record)) {
        unawaited(_refreshExpired(record.id));
        continue;
      }
      unawaited(_start(record.id));
    }
  }

  /// Whether the record's media address has run out, so far as its own query
  /// string says. Only worth acting on when the source page can be re-read.
  bool _hasExpiredAddress(DownloadRecord record) {
    if (record.sourceUrl.isEmpty) return false;
    if (_expiryRefreshed.contains(record.id)) return false;
    final url = Uri.tryParse(record.downloadUrl);
    return url != null && UrlExpiry.isExpired(url);
  }

  /// Asks the source for a current address before spending a request on one
  /// that has expired. Never fails the record: if the source cannot be
  /// re-read, the old address is tried anyway — some hosts are lenient — and
  /// the ordinary failure path takes it from there.
  Future<void> _refreshExpired(String id) async {
    _expiryRefreshed.add(id);
    _refreshing.add(id);
    _update(
      id,
      (r) => r.copyWith(errorMessage: _refreshingMessage, clearSpeed: true),
    );
    try {
      await _refreshLink(id);
    } finally {
      _refreshing.remove(id);
    }
    if (_disposed) return;
    if (_find(id)?.status == DownloadStatus.queued) {
      _update(id, (r) => r.copyWith(clearError: true));
    }
    _pump();
  }

  static const String _refreshingMessage =
      'The link had expired — getting a fresh one…';

  Future<void> _start(String id) async {
    final record = _find(id);
    if (record == null) return;

    final url = Uri.tryParse(record.downloadUrl);
    if (url == null || !url.hasAuthority) {
      _fail(id, DownloadErrorKind.invalidLink);
      return;
    }

    // Claim the slot before the first await so a second _pump cannot double
    // start the same record.
    final pending = _PendingTask();
    _tasks[id] = pending;

    try {
      final partial = await _storage.reserve(
        downloadId: id,
        fileName: record.fileName,
        mediaType: record.mediaType,
      );
      final resumeFrom = await partial.length();

      // The user may have cancelled, or the provider been disposed, while
      // storage was being prepared.
      if (_disposed ||
          pending.cancelled ||
          _find(id)?.status != DownloadStatus.queued) {
        _tasks.remove(id);
        _pump();
        return;
      }

      // A paired download writes its two tracks beside the target and only
      // fills the target when they are merged, so a part-sized target is never
      // mistaken for a finished file.
      final audioUrl = record.needsMuxing
          ? Uri.tryParse(record.audioUrl!)
          : null;

      // The bytes are already on disk — a previous run finished but could not
      // publish. Re-fetching them would be pure waste.
      final expected = record.totalBytes;
      if (audioUrl == null &&
          expected != null &&
          expected > 0 &&
          resumeFrom >= expected) {
        _tasks.remove(id);
        await _publish(id, partial, resumeFrom);
        _pump();
        return;
      }

      final request = DownloadRequest(
        id: id,
        url: url,
        target: partial,
        mediaType: record.mediaType,
        format: record.format,
        expectedBytes: record.totalBytes,
        supportsResume: record.supportsResume,
        startAt: record.supportsResume ? resumeFrom : 0,
        headers: record.headers,
        audioUrl: audioUrl,
        audioBytes: record.audioBytes,
      );

      final task = _engine.start(request);
      _tasks[id] = task;

      _update(
        id,
        (r) => r.copyWith(
          status: DownloadStatus.downloading,
          downloadedBytes: request.startAt,
          clearError: true,
        ),
        persist: true,
      );

      _progressSubs[id] = task.progress.listen((sample) {
        _update(
          id,
          (r) => r.copyWith(
            downloadedBytes: sample.receivedBytes,
            totalBytes: sample.totalBytes ?? r.totalBytes,
            speedBytesPerSecond: sample.bytesPerSecond,
          ),
        );
      });

      await _finish(id, await task.outcome);
    } on FileSystemException catch (error) {
      AppLog.warn('Reserving storage for a download', error.message);
      _tasks.remove(id);
      _fail(id, DownloadErrorKind.storage);
      _pump();
    }
  }

  Future<void> _finish(String id, DownloadOutcome outcome) async {
    await _progressSubs.remove(id)?.cancel();
    _tasks.remove(id);

    switch (outcome) {
      case DownloadSucceeded(:final file, :final totalBytes):
        await _publish(id, file, totalBytes);

      case DownloadPaused(:final receivedBytes):
        _update(
          id,
          (r) => r.copyWith(
            status: DownloadStatus.paused,
            downloadedBytes: receivedBytes,
            clearSpeed: true,
          ),
          persist: true,
        );

      case DownloadCancelled():
        _update(
          id,
          (r) => r.copyWith(status: DownloadStatus.cancelled, clearSpeed: true),
          persist: true,
        );

      case DownloadFailed(:final kind, :final receivedBytes):
        AppLog.warn(
          'Download failed',
          '${kind.name} after $receivedBytes bytes '
              '(${_find(id)?.source ?? 'unknown source'})',
        );
        _update(
          id,
          (r) => r.copyWith(
            status: DownloadStatus.failed,
            downloadedBytes: receivedBytes,
            errorMessage: kind.message,
            clearSpeed: true,
          ),
          persist: true,
        );
        _scheduleAutoRetry(id, kind);
        // Only notify once no retry is pending — a failure the app is about to
        // fix itself is not worth interrupting the user for.
        if (!_retryTimers.containsKey(id) && !_refreshing.contains(id)) {
          _notifyFailed(id);
          _report(
            id,
            (reporter, source) => reporter.downloadFailed(source, kind),
          );
        }
    }

    _pump();
  }

  /// Sends one anonymous count to the failure reporter, when there is one.
  /// The reporter only ever learns which platform, never which post.
  void _report(
    String id,
    void Function(FailureReporter reporter, Uri source) send,
  ) {
    final reporter = ref.read(failureReporterProvider);
    if (reporter == null) return;
    final url = Uri.tryParse(_find(id)?.sourceUrl ?? '');
    if (url == null || url.host.isEmpty) return;
    send(reporter, url);
  }

  void _notifyCompleted(String id) {
    if (!ref.read(settingsProvider).notifyOnComplete) return;
    final record = _find(id);
    if (record == null) return;

    unawaited(
      _notifications.showCompleted(
        id: id,
        mediaType: record.mediaType.name,
        title: 'Download complete',
        // Name, size and where it went: everything the user would open the
        // app to check, in the card they can tap to open the file instead.
        text:
            '${record.fileName}\n'
            '${Formatters.bytes(record.totalBytes ?? record.downloadedBytes)}'
            '  •  ${AppInfo.downloadFolder}/${record.mediaType.folderName}',
        mimeType: record.format.mimeType,
        location: record.filePath,
      ),
    );
  }

  void _notifyFailed(String id) {
    if (!ref.read(settingsProvider).notifyOnFailure) return;
    final record = _find(id);
    if (record == null) return;

    unawaited(
      _notifications.showFailed(
        id: id,
        title: 'Download failed',
        text: '${record.fileName} — ${record.errorMessage ?? 'Try again'}',
      ),
    );
  }

  /// Moves a finished transfer into the user's shared Downloads folder.
  Future<void> _publish(String id, File file, int totalBytes) async {
    final record = _find(id);
    if (record == null) return;

    try {
      final published = await _storage.publish(
        partial: file,
        fileName: record.fileName,
        mimeType: record.format.mimeType,
        mediaType: record.mediaType,
      );
      _attempts.remove(id);

      _update(
        id,
        (r) => r.copyWith(
          status: DownloadStatus.completed,
          filePath: published.location,
          // Android may have made the name unique on collision; show the one
          // the file actually has.
          fileName: published.fileName,
          downloadedBytes: totalBytes,
          totalBytes: totalBytes,
          completedAt: DateTime.now(),
          clearSpeed: true,
          clearError: true,
        ),
        persist: true,
      );
      _notifyCompleted(id);
      _report(id, (reporter, source) => reporter.downloadCompleted(source));
    } on FileSystemException catch (error) {
      AppLog.warn('Saving a finished download', error.message);
      _fail(id, DownloadErrorKind.storage);
    } on PlatformException catch (error) {
      AppLog.warn('Publishing a finished download', error.message);
      _fail(id, DownloadErrorKind.storage);
    }
  }

  /// Gives a transient failure a couple of quiet second chances.
  ///
  /// Permanent failures — a refused server, a full disk — are never retried
  /// automatically; the user is told instead.
  void _scheduleAutoRetry(String id, DownloadErrorKind kind) {
    // A refused or invalid address is usually an expired one rather than a
    // missing file, and re-reading the page is the only thing that can fix it.
    if (kind == DownloadErrorKind.server ||
        kind == DownloadErrorKind.invalidLink) {
      unawaited(_retryWithFreshLink(id));
      return;
    }

    if (!kind.isRetryable) return;

    // Each kind of failure has its own budget: a rate limit is honoured with
    // a real pause, a failing host gets a few spaced tries, a flaky
    // connection two quick ones.
    final spent = _attempts[id] ?? 0;
    final delay = kind.retryDelay(spent);
    if (delay == null) return;
    _attempts[id] = spent + 1;

    _cancelRetryTimer(id);
    _retryTimers[id] = Timer(delay, () {
      _retryTimers.remove(id);
      if (_disposed) return;
      // Only retry if the user has not touched it in the meantime.
      if (_find(id)?.status != DownloadStatus.failed) return;

      _update(
        id,
        (r) => r.copyWith(status: DownloadStatus.queued, clearError: true),
        persist: true,
      );
      _pump();
    });
  }

  /// Re-reads the source page once and starts over if it yields a new address.
  ///
  /// Deliberately capped at a single attempt: if the fresh address is refused
  /// too, the file really is gone, and looping would only burn data.
  ///
  /// While the page is being re-read the download shows as queued with a note
  /// saying so — the source's other servers are being asked — rather than as
  /// failed, because it has not failed yet.
  Future<void> _retryWithFreshLink(String id) async {
    final spent = _attempts[id] ?? 0;
    if (spent >= 1) return;
    _attempts[id] = spent + 1;

    if (_find(id)?.sourceUrl.isEmpty ?? true) return;

    _update(
      id,
      (r) => r.copyWith(
        status: DownloadStatus.queued,
        errorMessage: _switchingServerMessage,
        clearSpeed: true,
      ),
      persist: true,
    );

    _refreshing.add(id);
    final bool moved;
    try {
      moved = await _refreshLink(id);
    } finally {
      _refreshing.remove(id);
    }
    if (_disposed) return;

    // Only if the user has not touched it in the meantime.
    if (_find(id)?.status != DownloadStatus.queued) return;

    if (!moved) {
      _update(
        id,
        (r) => r.copyWith(
          status: DownloadStatus.failed,
          errorMessage: _exhaustedMessage,
        ),
        persist: true,
      );
      _notifyFailed(id);
      return;
    }

    _update(id, (r) => r.copyWith(clearError: true), persist: true);
    _pump();
  }

  /// Shown while a refused download is re-read from its source.
  static const String _switchingServerMessage =
      'Server temporarily unavailable. Trying another server…';

  /// Shown when every server the source has was tried.
  static const String _exhaustedMessage =
      'We couldn\'t process this download right now. Please try again later.';

  void _cancelRetryTimer(String id) {
    _retryTimers.remove(id)?.cancel();
  }

  void _fail(String id, DownloadErrorKind kind) {
    _update(
      id,
      (r) => r.copyWith(
        status: DownloadStatus.failed,
        errorMessage: kind.message,
        clearSpeed: true,
      ),
      persist: true,
    );
    _scheduleAutoRetry(id, kind);
  }

  Future<void> _discardPartial(String id) async {
    await _storage.discardPartial(id);
  }

  // ----------------------------------------------------- foreground service

  /// Keeps the Android service in step with what is actually running.
  void _syncService() {
    if (_disposed) return;

    final active = state.records
        .where((r) => r.status.isActive)
        .toList(growable: false);
    if (active.isEmpty) {
      unawaited(_service.stop());
      return;
    }
    final running = active
        .where((r) => r.status == DownloadStatus.downloading)
        .toList(growable: false);
    final primary = running.isNotEmpty ? running.first : active.first;
    final others = active.length - 1;

    // With several transfers running the bar is all of them together —
    // bytes done over bytes expected — so it moves steadily instead of
    // jumping as each one finishes. Only once every running total is known;
    // otherwise the one file whose size is known would misreport the rest.
    final int downloaded;
    final int? total;
    final double? speed;
    if (running.length > 1) {
      downloaded = running.fold<int>(0, (sum, r) => sum + r.downloadedBytes);
      total = running.every((r) => (r.totalBytes ?? 0) > 0)
          ? running.fold<int>(0, (sum, r) => sum + r.totalBytes!)
          : null;
      final rates = running.map((r) => r.speedBytesPerSecond).nonNulls;
      speed = rates.isEmpty ? null : rates.fold<double>(0, (sum, r) => sum + r);
    } else {
      downloaded = primary.downloadedBytes;
      total = primary.totalBytes;
      speed = primary.speedBytesPerSecond;
    }
    final fraction = total == null || total <= 0
        ? primary.progress
        : (downloaded / total).clamp(0.0, 1.0);

    // Says what is happening as well as how far along it is, because the
    // notification is often the only thing the user sees of a download
    // started from the share sheet. Collapsed it is one line — percent and
    // size; expanded it adds the speed and the time left on their own line.
    final String text;
    final String details;
    if (running.isEmpty) {
      text = ref.read(downloadHoldProvider) ?? 'Waiting to start';
      details = text;
    } else {
      final percent = fraction == null ? null : Formatters.percent(fraction);
      final size = Formatters.transferred(downloaded, total);
      final rate = Formatters.speed(speed, unknown: '');
      final remaining = total == null || speed == null || speed <= 0
          ? null
          : ((total - downloaded) / speed).ceil();
      final left = remaining == null
          ? ''
          : '${Formatters.duration(remaining)} left';

      text = [?percent, size, if (rate.isNotEmpty) rate].join('  •  ');
      details = [
        [?percent, size].join('  •  '),
        [if (rate.isNotEmpty) rate, if (left.isNotEmpty) left].join('  •  '),
      ].where((line) => line.isNotEmpty).join('\n');
    }

    unawaited(
      _service.update(
        title: running.length > 1
            ? '${running.length} downloads'
            : primary.title,
        text: text,
        details: details,
        subText: others == 0 || running.length > 1
            ? null
            : others == 1
            ? '1 more queued'
            : '$others more queued',
        progress: fraction == null ? null : (fraction * 100).round(),
        buttons: [
          if (running.isNotEmpty)
            DownloadNotificationAction.pauseAll
          else if (active.any((r) => r.status == DownloadStatus.paused))
            DownloadNotificationAction.resumeAll,
          DownloadNotificationAction.cancelAll,
        ],
      ),
    );
  }

  /// A button on the ongoing notification: the same commands the Downloads
  /// screen offers, applied to everything the notification stands for.
  Future<void> _onNotificationAction(DownloadNotificationAction action) async {
    if (_disposed) return;
    final ids = state.records
        .where((r) => r.status.isActive)
        .map((r) => r.id)
        .toList(growable: false);
    switch (action) {
      case DownloadNotificationAction.pauseAll:
        for (final id in ids) {
          await pause(id);
        }
      case DownloadNotificationAction.resumeAll:
        for (final id in ids) {
          await resume(id);
        }
      case DownloadNotificationAction.cancelAll:
        for (final id in ids) {
          await cancel(id);
        }
    }
  }

  // -------------------------------------------------------------- primitives

  DownloadRecord? _find(String id) {
    for (final record in state.records) {
      if (record.id == id) return record;
    }
    return null;
  }

  DownloadRecord? _findCompletedNamed(String fileName, MediaType mediaType) {
    for (final record in state.records) {
      if (record.status == DownloadStatus.completed &&
          record.fileName == fileName &&
          record.mediaType == mediaType) {
        return record;
      }
    }
    return null;
  }

  /// Applies a change to one record.
  ///
  /// [persist] is set for state transitions only. Byte counts during a transfer
  /// are not written on every tick — the partial file on disk is the real
  /// record of progress, and it is what a resume reads.
  void _update(
    String id,
    DownloadRecord Function(DownloadRecord) transform, {
    bool persist = false,
  }) {
    if (_disposed) return;

    DownloadRecord? changed;
    final next = <DownloadRecord>[];
    for (final record in state.records) {
      if (record.id == id) {
        changed = transform(record);
        next.add(changed);
      } else {
        next.add(record);
      }
    }
    if (changed == null) return;

    state = state.copyWith(records: next);
    if (persist) unawaited(_persist(changed));
    _syncService();
  }

  Future<void> _persist(DownloadRecord record) async {
    final dao = _dao;
    if (dao == null) return;
    try {
      await dao.save(record);
    } catch (error) {
      // History that fails to write is a degraded experience, not a crash.
      AppLog.warn('Writing a history row', error);
    }
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_sequence++}';
}

/// Reserves a concurrency slot between the decision to start and the engine
/// actually being handed the request.
///
/// Holding the slot with a real object keeps a second `_pump` from starting the
/// same record twice, and lets a cancel that lands during that window be seen.
class _PendingTask implements DownloadTask {
  bool cancelled = false;

  @override
  Stream<DownloadProgress> get progress => const Stream.empty();

  @override
  Future<DownloadOutcome> get outcome async => const DownloadCancelled();

  @override
  Future<void> pause() async {}

  @override
  Future<void> cancel() async {}
}

final downloadsProvider = NotifierProvider<DownloadsController, DownloadsState>(
  DownloadsController.new,
);

/// True once history has been read back from the database.
final downloadsHydratedProvider = Provider<bool>(
  (ref) => ref.watch(downloadsProvider.select((s) => s.hydrated)),
);

/// Why queued downloads are not starting, or null when nothing is holding them.
///
/// The queue honours this and the UI shows it, so waiting always has a stated
/// reason instead of looking like the app is stuck.
final downloadHoldProvider = Provider<String?>((ref) {
  final network = ref.watch(networkStatusProvider);
  final wifiOnly = ref.watch(settingsProvider.select((s) => s.wifiOnly));

  if (network.captivePortal) {
    return 'Sign in to this Wi-Fi network to continue';
  }
  if (network.isOffline) return 'Waiting for a connection';
  if (wifiOnly && network.metered) return 'Waiting for Wi-Fi';
  return null;
});

/// Total size of everything Hoza has finished downloading.
///
/// Kept separate so the figure only changes when a download completes — not on
/// every progress tick, which would re-query the device volume several times a
/// second.
final completedBytesProvider = Provider<int>((ref) {
  return ref
      .watch(downloadsProvider)
      .records
      .where((record) => record.status == DownloadStatus.completed)
      .fold<int>(0, (sum, record) => sum + (record.totalBytes ?? 0));
});

/// How much space Hoza's downloads take, and what is free on the device.
final storageUsageProvider = FutureProvider<StorageUsage>((ref) async {
  final used = ref.watch(completedBytesProvider);
  final info = await ref.watch(downloadStorageProvider).storageInfo();
  return StorageUsage(usedByApp: used, device: info);
});

@immutable
class StorageUsage {
  const StorageUsage({required this.usedByApp, required this.device});

  /// Bytes across everything Hoza has finished downloading.
  final int usedByApp;

  final StorageInfo device;
}

/// A single record, for screens that follow one download.
final downloadRecordProvider = Provider.family<DownloadRecord?, String>((
  ref,
  id,
) {
  for (final record in ref.watch(downloadsProvider).records) {
    if (record.id == id) return record;
  }
  return null;
});

/// History ordered newest first.
final sortedDownloadsProvider = Provider<List<DownloadRecord>>((ref) {
  final records = [...ref.watch(downloadsProvider).records];
  records.sort((a, b) {
    final aDate = a.completedAt ?? a.createdAt;
    final bDate = b.completedAt ?? b.createdAt;
    return bDate.compareTo(aDate);
  });
  return records;
});

/// Transfers that are queued, running or paused.
final activeDownloadsProvider = Provider<List<DownloadRecord>>((ref) {
  return ref
      .watch(sortedDownloadsProvider)
      .where(
        (record) =>
            record.status.isActive || record.status == DownloadStatus.paused,
      )
      .toList();
});

/// Finished transfers, for the Home preview.
final recentDownloadsProvider = Provider<List<DownloadRecord>>((ref) {
  return ref
      .watch(sortedDownloadsProvider)
      .where((record) => record.status.isTerminal)
      .toList();
});

/// Transfers that stopped with an error and can be sent again.
///
/// Drives the "Retry all" affordance, so what the action offers and what it
/// would actually do are read from the same place.
final retryableDownloadsProvider = Provider<List<DownloadRecord>>((ref) {
  return ref
      .watch(sortedDownloadsProvider)
      .where((record) => record.status.canRetry)
      .toList();
});

/// Current chip on the Downloads screen.
final downloadFilterProvider =
    NotifierProvider<DownloadFilterController, DownloadFilter>(
      DownloadFilterController.new,
    );

class DownloadFilterController extends Notifier<DownloadFilter> {
  @override
  DownloadFilter build() => DownloadFilter.all;

  void select(DownloadFilter filter) => state = filter;
}

/// Search text on the Downloads screen.
final downloadSearchProvider =
    NotifierProvider<DownloadSearchController, String>(
      DownloadSearchController.new,
    );

class DownloadSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

/// The list the Downloads screen renders: filtered, then searched.
final visibleDownloadsProvider = Provider<List<DownloadRecord>>((ref) {
  final filter = ref.watch(downloadFilterProvider);
  final query = ref.watch(downloadSearchProvider).trim().toLowerCase();
  final records = ref
      .watch(sortedDownloadsProvider)
      .where(filter.matches)
      .toList();

  if (query.isEmpty) return records;

  return records.where((record) {
    return record.title.toLowerCase().contains(query) ||
        record.fileName.toLowerCase().contains(query) ||
        record.source.toLowerCase().contains(query) ||
        record.format.label.toLowerCase().contains(query) ||
        record.quality.toLowerCase().contains(query);
  }).toList();
});
