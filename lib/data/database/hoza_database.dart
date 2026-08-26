import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'download_rows.dart';

/// The app's single SQLite database.
///
/// History and preferences share one file so there is one place to open, one
/// migration path, and one thing to back up. Migrations are additive: a new
/// version adds tables or columns, never drops user data.
abstract final class HozaDatabase {
  static const String fileName = 'hoza_download.db';

  /// v1 — download history.
  /// v2 — preferences table.
  /// v3 — per-download request headers and a paired audio track.
  /// v4 — group id, so the photos of one post are saved as one set.
  static const int schemaVersion = 4;

  static const String preferencesTable = 'preferences';
  static const String preferenceKey = 'key';
  static const String preferenceValue = 'value';

  static Future<Database> open() async {
    final directory = await getDatabasesPath();
    return openDatabase(
      p.join(directory, fileName),
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createDownloads(db);
        await _createPreferences(db);
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) await _createPreferences(db);
        if (from < 3) await _addMuxingColumns(db);
        if (from < 4) await _addGroupColumn(db);
      },
    );
  }

  static Future<void> _createDownloads(Database db) async {
    await db.execute('''
      CREATE TABLE ${DownloadRows.table} (
        ${DownloadRows.columnId} TEXT PRIMARY KEY,
        ${DownloadRows.columnSourceUrl} TEXT NOT NULL DEFAULT '',
        ${DownloadRows.columnDownloadUrl} TEXT NOT NULL DEFAULT '',
        ${DownloadRows.columnSupportsResume} INTEGER NOT NULL DEFAULT 0,
        ${DownloadRows.columnTitle} TEXT NOT NULL DEFAULT '',
        ${DownloadRows.columnFileName} TEXT NOT NULL,
        ${DownloadRows.columnFilePath} TEXT,
        ${DownloadRows.columnThumbnailUrl} TEXT,
        ${DownloadRows.columnSource} TEXT NOT NULL DEFAULT '',
        ${DownloadRows.columnMediaType} TEXT NOT NULL,
        ${DownloadRows.columnFormat} TEXT NOT NULL,
        ${DownloadRows.columnQuality} TEXT NOT NULL DEFAULT '',
        ${DownloadRows.columnTotalBytes} INTEGER,
        ${DownloadRows.columnDownloadedBytes} INTEGER NOT NULL DEFAULT 0,
        ${DownloadRows.columnStatus} TEXT NOT NULL,
        ${DownloadRows.columnCreatedAt} INTEGER NOT NULL,
        ${DownloadRows.columnCompletedAt} INTEGER,
        ${DownloadRows.columnErrorMessage} TEXT,
        ${DownloadRows.columnHeaders} TEXT,
        ${DownloadRows.columnAudioUrl} TEXT,
        ${DownloadRows.columnAudioBytes} INTEGER,
        ${DownloadRows.columnGroupId} TEXT
      )
    ''');

    // The list is always ordered by recency and filtered by status; duplicate
    // detection looks a file name up by name and type.
    await db.execute(
      'CREATE INDEX idx_downloads_created_at '
      'ON ${DownloadRows.table}(${DownloadRows.columnCreatedAt} DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_downloads_status '
      'ON ${DownloadRows.table}(${DownloadRows.columnStatus})',
    );
    await db.execute(
      'CREATE INDEX idx_downloads_file_name '
      'ON ${DownloadRows.table}'
      '(${DownloadRows.columnFileName}, ${DownloadRows.columnMediaType})',
    );
  }

  /// Additive, and tolerant of a database that already has the columns from a
  /// half-applied upgrade.
  static Future<void> _addMuxingColumns(Database db) async {
    const columns = <String, String>{
      DownloadRows.columnHeaders: 'TEXT',
      DownloadRows.columnAudioUrl: 'TEXT',
      DownloadRows.columnAudioBytes: 'INTEGER',
    };
    for (final entry in columns.entries) {
      try {
        await db.execute(
          'ALTER TABLE ${DownloadRows.table} '
          'ADD COLUMN ${entry.key} ${entry.value}',
        );
      } on DatabaseException {
        // Already present; nothing to migrate.
      }
    }
  }

  /// Additive and idempotent, like [_addMuxingColumns].
  static Future<void> _addGroupColumn(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE ${DownloadRows.table} '
        'ADD COLUMN ${DownloadRows.columnGroupId} TEXT',
      );
    } on DatabaseException {
      // Already present; nothing to migrate.
    }
  }

  static Future<void> _createPreferences(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $preferencesTable (
        $preferenceKey TEXT PRIMARY KEY,
        $preferenceValue TEXT NOT NULL
      )
    ''');
  }
}

/// Overridden in `main` with the database opened before the first frame, so no
/// screen has to wait on it.
final databaseProvider = Provider<Database>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);
