import 'dart:convert';

import '../models/download_record.dart';
import '../models/download_status.dart';
import '../models/media_option.dart';

/// Translates between [DownloadRecord] and its database row.
///
/// Reading is deliberately forgiving: a row written by an older build may be
/// missing columns, and a corrupt value must degrade to a sane default rather
/// than throwing and taking the whole history with it.
abstract final class DownloadRows {
  static const String table = 'downloads';

  // Column names are referenced from queries, so they live here rather than as
  // string literals scattered across the DAO.
  static const String columnId = 'id';
  static const String columnSourceUrl = 'source_url';
  static const String columnDownloadUrl = 'download_url';
  static const String columnSupportsResume = 'supports_resume';
  static const String columnTitle = 'title';
  static const String columnFileName = 'file_name';
  static const String columnFilePath = 'file_path';
  static const String columnThumbnailUrl = 'thumbnail_url';
  static const String columnSource = 'source';
  static const String columnMediaType = 'media_type';
  static const String columnFormat = 'format';
  static const String columnQuality = 'quality';
  static const String columnTotalBytes = 'total_bytes';
  static const String columnDownloadedBytes = 'downloaded_bytes';
  static const String columnStatus = 'status';
  static const String columnCreatedAt = 'created_at';
  static const String columnCompletedAt = 'completed_at';
  static const String columnErrorMessage = 'error_message';
  static const String columnHeaders = 'headers';
  static const String columnAudioUrl = 'audio_url';
  static const String columnAudioBytes = 'audio_bytes';
  static const String columnGroupId = 'group_id';

  static Map<String, Object?> toRow(DownloadRecord record) {
    return {
      columnId: record.id,
      columnSourceUrl: record.sourceUrl,
      columnDownloadUrl: record.downloadUrl,
      columnSupportsResume: record.supportsResume ? 1 : 0,
      columnTitle: record.title,
      columnFileName: record.fileName,
      columnFilePath: record.filePath,
      columnThumbnailUrl: record.thumbnailUrl,
      columnSource: record.source,
      columnMediaType: record.mediaType.storageKey,
      columnFormat: record.format.storageKey,
      columnQuality: record.quality,
      columnTotalBytes: record.totalBytes,
      columnDownloadedBytes: record.downloadedBytes,
      columnStatus: record.status.storageKey,
      columnCreatedAt: record.createdAt.millisecondsSinceEpoch,
      columnCompletedAt: record.completedAt?.millisecondsSinceEpoch,
      columnErrorMessage: record.errorMessage,
      columnHeaders: record.headers.isEmpty ? null : jsonEncode(record.headers),
      columnAudioUrl: record.audioUrl,
      columnAudioBytes: record.audioBytes,
      columnGroupId: record.groupId,
      // Live speed is meaningless once the app closes and is not stored.
    };
  }

  /// Returns null when a row is too damaged to be shown, so one bad entry
  /// cannot break the whole list.
  static DownloadRecord? fromRow(Map<String, Object?> row) {
    final id = _string(row[columnId]);
    final fileName = _string(row[columnFileName]);
    if (id == null || fileName == null) return null;

    final createdAt = _dateTime(row[columnCreatedAt]);
    if (createdAt == null) return null;

    return DownloadRecord(
      id: id,
      sourceUrl: _string(row[columnSourceUrl]) ?? '',
      downloadUrl: _string(row[columnDownloadUrl]) ?? '',
      supportsResume: _int(row[columnSupportsResume]) == 1,
      title: _string(row[columnTitle]) ?? fileName,
      fileName: fileName,
      filePath: _string(row[columnFilePath]),
      thumbnailUrl: _string(row[columnThumbnailUrl]),
      source: _string(row[columnSource]) ?? '',
      mediaType: MediaType.fromStorageKey(_string(row[columnMediaType])),
      format: MediaFormat.fromStorageKey(_string(row[columnFormat])),
      quality: _string(row[columnQuality]) ?? '',
      totalBytes: _int(row[columnTotalBytes]),
      downloadedBytes: _int(row[columnDownloadedBytes]) ?? 0,
      status: DownloadStatus.fromStorageKey(_string(row[columnStatus])),
      createdAt: createdAt,
      completedAt: _dateTime(row[columnCompletedAt]),
      errorMessage: _string(row[columnErrorMessage]),
      headers: _headers(row[columnHeaders]),
      audioUrl: _string(row[columnAudioUrl]),
      audioBytes: _int(row[columnAudioBytes]),
      groupId: _string(row[columnGroupId]),
    );
  }

  /// Headers are stored as a small JSON object. A row written by an older
  /// build has none, and a damaged value degrades to none rather than throwing.
  static Map<String, String> _headers(Object? value) {
    final encoded = _string(value);
    if (encoded == null) return const <String, String>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const <String, String>{};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on FormatException {
      return const <String, String>{};
    }
  }

  static String? _string(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _dateTime(Object? value) {
    final millis = _int(value);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
