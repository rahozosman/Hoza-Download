import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';
import '../../features/downloader/data/shared_download_storage.dart';
import '../database/download_dao.dart';
import '../providers/downloads_provider.dart';
import '../providers/settings_provider.dart';

/// The stages a reset moves through, in order.
enum ResetStage {
  stopping('Stopping transfers'),
  history('Clearing history'),
  preferences('Restoring defaults'),
  cache('Removing cached data'),
  done('Done');

  const ResetStage(this.label);

  final String label;

  /// The stages worth showing progress for. [done] is the outcome, not a step.
  static List<ResetStage> get steps =>
      values.where((stage) => stage != ResetStage.done).toList(growable: false);
}

/// What a reset actually removed. Reported back so the confirmation can say
/// what happened instead of only claiming that something did.
@immutable
class ResetReport {
  const ResetReport({
    required this.records,
    required this.preferences,
    required this.partials,
  });

  const ResetReport.empty() : records = 0, preferences = 0, partials = 0;

  final int records;
  final int preferences;
  final int partials;
}

/// The one place the app erases the user's local data.
///
/// Centralised on purpose. User data lives in five separate stores — the
/// `downloads` table, the `preferences` table, the partials scratch directory,
/// the in-memory Riverpod state, and the notifications already posted — and a
/// reset that misses one of them leaves the app in a state no fresh install
/// could ever be in. Scattering that across the screens that happen to own
/// each store is how a reset ends up half-done.
///
/// What it never touches:
///
/// * media already saved to the device — resetting the app is not the same as
///   deleting somebody's videos, and other apps may already reference them;
/// * the database file, its tables or its indexes — the schema is the app's,
///   not the user's;
/// * anything the app needs in order to run.
///
/// Every step is guarded on its own, so an unavailable database still lets the
/// cache and the in-memory state be cleared. A reset that fails halfway is
/// worse than one that clears everything it can reach and says so.
class ResetService {
  const ResetService(this._ref);

  final Ref _ref;

  /// Runs the reset, reporting each stage as it is entered.
  ///
  /// [onStage] is awaited, so the caller controls pacing: the work itself is
  /// close to instantaneous and a progress display nobody can read is not
  /// progress.
  Future<ResetReport> run({
    Future<void> Function(ResetStage stage)? onStage,
  }) async {
    var records = 0;
    var preferences = 0;
    var partials = 0;

    // 1. Stop first. Clearing rows out from under a running transfer would
    //    leave the engine writing progress to a record that no longer exists.
    await onStage?.call(ResetStage.stopping);
    try {
      records = await _ref.read(downloadsProvider.notifier).standDown();
    } catch (error, stack) {
      AppLog.error('Stopping transfers during reset', error, stack);
    }

    // 2. History. Standing down already removed every row it knew about; this
    //    also catches anything on disk that never reached memory — a database
    //    that failed to read at launch, for one.
    await onStage?.call(ResetStage.history);
    try {
      records += await _ref.read(downloadDaoProvider).deleteAll();
    } catch (error, stack) {
      AppLog.error('Clearing history during reset', error, stack);
    }

    // 3. Preferences: emptied on disk, then defaults adopted in memory, so the
    //    UI cannot keep showing settings that no longer exist anywhere.
    await onStage?.call(ResetStage.preferences);
    try {
      preferences = await _ref.read(settingsStoreProvider).clear();
    } catch (error, stack) {
      AppLog.error('Clearing preferences during reset', error, stack);
    }
    _ref.read(settingsProvider.notifier).adoptDefaults();

    // 4. Scratch chunks, plus the view state that would otherwise survive as a
    //    filter or a search term with nothing left to match.
    await onStage?.call(ResetStage.cache);
    try {
      partials = await _ref.read(downloadStorageProvider).clearPartials();
    } catch (error, stack) {
      AppLog.error('Clearing cached data during reset', error, stack);
    }
    _ref.invalidate(downloadFilterProvider);
    _ref.invalidate(downloadSearchProvider);

    await onStage?.call(ResetStage.done);
    return ResetReport(
      records: records,
      preferences: preferences,
      partials: partials,
    );
  }
}

final resetServiceProvider = Provider<ResetService>(ResetService.new);
