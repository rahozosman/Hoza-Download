import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/utils/app_log.dart';
import '../../data/database/hoza_database.dart';

/// Keeps the link of a share that has not been shown yet.
///
/// A share can arrive while the engine is still starting on a low-memory
/// phone, and Android may kill the process before the sheet is up. Without
/// this the link would simply be gone — the user tapped Share and nothing
/// happened. It is written the moment a link arrives and cleared the moment
/// its sheet is shown, so a link the user has already seen is never shown
/// twice. Anything older than [maxAge] is dropped unread: a link from last
/// week is not what they meant to open now.
class PendingShareStore {
  const PendingShareStore(this._db);

  final Database _db;

  static const String _keyUrl = 'pending_share.url';
  static const String _keyAt = 'pending_share.at';
  static const Duration maxAge = Duration(minutes: 30);

  Future<void> remember(Uri url) async {
    try {
      final batch = _db.batch()
        ..insert(
          HozaDatabase.preferencesTable,
          {
            HozaDatabase.preferenceKey: _keyUrl,
            HozaDatabase.preferenceValue: url.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        )
        ..insert(
          HozaDatabase.preferencesTable,
          {
            HozaDatabase.preferenceKey: _keyAt,
            HozaDatabase.preferenceValue:
                '${DateTime.now().millisecondsSinceEpoch}',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      await batch.commit(noResult: true);
    } catch (error) {
      AppLog.warn('Remembering a pending share', error);
    }
  }

  Future<void> clear() async {
    try {
      await _db.delete(
        HozaDatabase.preferencesTable,
        where: '${HozaDatabase.preferenceKey} IN (?, ?)',
        whereArgs: [_keyUrl, _keyAt],
      );
    } catch (error) {
      AppLog.warn('Clearing a pending share', error);
    }
  }

  /// The link waiting to be shown, if there is one and it is recent. Reading
  /// it clears it, so a link that then fails to show is not retried forever.
  Future<Uri?> take() async {
    try {
      final rows = await _db.query(
        HozaDatabase.preferencesTable,
        where: '${HozaDatabase.preferenceKey} IN (?, ?)',
        whereArgs: [_keyUrl, _keyAt],
      );
      if (rows.isEmpty) return null;
      await clear();

      final values = {
        for (final row in rows)
          row[HozaDatabase.preferenceKey] as String:
              row[HozaDatabase.preferenceValue] as String,
      };
      final at = int.tryParse(values[_keyAt] ?? '');
      if (at == null) return null;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(at),
      );
      if (age > maxAge) return null;

      final url = Uri.tryParse(values[_keyUrl] ?? '');
      return url != null && url.host.isNotEmpty ? url : null;
    } catch (error) {
      AppLog.warn('Reading a pending share', error);
      return null;
    }
  }
}

final pendingShareStoreProvider = Provider<PendingShareStore>(
  (ref) => PendingShareStore(ref.watch(databaseProvider)),
);
