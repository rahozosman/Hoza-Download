import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../models/download_record.dart';
import '../models/download_status.dart';
import '../models/media_option.dart';
import 'download_rows.dart';
import 'hoza_database.dart';

/// Reads and writes download history.
///
/// Owns queries only; opening and migrating the database is [HozaDatabase]'s
/// job, so history and preferences share one connection.
class DownloadDao {
  const DownloadDao(this._db);

  final Database _db;

  /// Removes every history row, and returns how many there were.
  ///
  /// The table and its indexes are kept: a reset clears the user's data, it
  /// does not tear down the schema the app needs to keep working.
  Future<int> deleteAll() => _db.delete(DownloadRows.table);

  /// Newest first.
  Future<List<DownloadRecord>> all() async {
    final rows = await _db.query(
      DownloadRows.table,
      orderBy: '${DownloadRows.columnCreatedAt} DESC',
    );
    return rows
        .map(DownloadRows.fromRow)
        .whereType<DownloadRecord>()
        .toList(growable: false);
  }

  Future<void> save(DownloadRecord record) async {
    await _db.insert(
      DownloadRows.table,
      DownloadRows.toRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    await _db.delete(
      DownloadRows.table,
      where: '${DownloadRows.columnId} = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids) {
      batch.delete(
        DownloadRows.table,
        where: '${DownloadRows.columnId} = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// A finished download already holding this name, if there is one.
  Future<DownloadRecord?> findCompleted({
    required String fileName,
    required MediaType mediaType,
  }) async {
    final rows = await _db.query(
      DownloadRows.table,
      where:
          '${DownloadRows.columnFileName} = ? AND '
          '${DownloadRows.columnMediaType} = ? AND '
          '${DownloadRows.columnStatus} = ?',
      whereArgs: [
        fileName,
        mediaType.storageKey,
        DownloadStatus.completed.storageKey,
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DownloadRows.fromRow(rows.first);
  }

  /// Corrects rows left mid-flight when the process was killed.
  ///
  /// Nothing is transferring at startup, so a row that still says
  /// "downloading" would be a lie. Those become paused, keeping their partial
  /// file so the user can resume.
  Future<int> settleInterrupted() async {
    return _db.update(
      DownloadRows.table,
      {DownloadRows.columnStatus: DownloadStatus.paused.storageKey},
      where: '${DownloadRows.columnStatus} IN (?, ?)',
      whereArgs: [
        DownloadStatus.downloading.storageKey,
        DownloadStatus.queued.storageKey,
      ],
    );
  }

  /// Total size of everything Hoza has finished downloading, for the storage
  /// panel in Settings.
  Future<int> completedBytes() async {
    final rows = await _db.rawQuery(
      'SELECT SUM(${DownloadRows.columnTotalBytes}) AS total '
      'FROM ${DownloadRows.table} WHERE ${DownloadRows.columnStatus} = ?',
      [DownloadStatus.completed.storageKey],
    );
    final total = rows.isEmpty ? null : rows.first['total'];
    return total is num ? total.toInt() : 0;
  }
}

final downloadDaoProvider = Provider<DownloadDao>(
  (ref) => DownloadDao(ref.watch(databaseProvider)),
);
