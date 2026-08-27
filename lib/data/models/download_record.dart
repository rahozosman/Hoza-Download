import 'download_status.dart';
import 'media_option.dart';

/// A single row of download history.
///
/// Immutable by design: the controller replaces records rather than mutating
/// them, which keeps the list a pure function of state and makes rebuilds
/// cheap to reason about.
class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.sourceUrl,
    required this.downloadUrl,
    required this.title,
    required this.fileName,
    required this.source,
    required this.mediaType,
    required this.format,
    required this.quality,
    required this.status,
    required this.createdAt,
    this.supportsResume = false,
    this.headers = const <String, String>{},
    this.audioUrl,
    this.audioBytes,
    this.reencodeKbps,
    this.filePath,
    this.thumbnailUrl,
    this.totalBytes,
    this.downloadedBytes = 0,
    this.speedBytesPerSecond,
    this.completedAt,
    this.errorMessage,
    this.groupId,
  });

  /// Ties the photos of one post together: every record of a "save all"
  /// shares the same id. Null for a download that stands alone.
  final String? groupId;

  final String id;

  /// The page or link the user shared. Kept for display and for retrying a
  /// lookup, never used to fetch bytes directly.
  final String sourceUrl;

  /// The media URL the chosen variant resolves to.
  ///
  /// Persisted so a download can still be resumed or retried after the app has
  /// been closed and reopened.
  final String downloadUrl;

  /// Whether the server advertised byte ranges for [downloadUrl]. Resuming is
  /// only offered when it did.
  final bool supportsResume;

  /// Headers the source requires on the byte request, persisted so a retry
  /// after a restart still reaches the CDN the same way.
  final Map<String, String> headers;

  /// Audio track merged into [downloadUrl] when the source publishes video and
  /// audio separately. Null for an ordinary single-file download.
  final String? audioUrl;

  /// Size of [audioUrl], so the video track's own size can be worked out from
  /// [totalBytes] when a paused paired download resumes.
  final int? audioBytes;

  /// Bitrate the sound is re-encoded to before the file is saved, in kbps.
  /// Null for a download saved exactly as it arrived. Persisted so a download
  /// resumed after a restart still produces the format the user chose.
  final int? reencodeKbps;

  bool get needsMuxing => audioUrl != null && audioUrl!.isNotEmpty;

  /// Human title from the source, falling back to the file name.
  final String title;

  /// Sanitised name on disk, including extension.
  final String fileName;

  /// Where the bytes live once complete: a file path or a MediaStore URI.
  /// Null until the download finishes.
  final String? filePath;

  final String? thumbnailUrl;

  /// Display name of the origin site.
  final String source;

  final MediaType mediaType;
  final MediaFormat format;

  /// Variant label shown in the UI: `1080p`, `MP3`, …
  final String quality;

  /// Total size in bytes, when the server reports one.
  final int? totalBytes;

  final int downloadedBytes;

  /// Live transfer rate. Runtime only — never persisted.
  final double? speedBytesPerSecond;

  final DownloadStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;

  /// User-facing failure reason, already translated out of technical jargon.
  final String? errorMessage;

  /// 0..1, or null when the total size is unknown and progress is
  /// indeterminate. Completed downloads always report 1.
  double? get progress {
    if (status == DownloadStatus.completed) return 1;
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (downloadedBytes / total).clamp(0.0, 1.0);
  }

  /// Remaining time in seconds, or null when it cannot be estimated honestly.
  int? get etaSeconds {
    final total = totalBytes;
    final speed = speedBytesPerSecond;
    if (status != DownloadStatus.downloading) return null;
    if (total == null || speed == null || speed <= 0) return null;
    final remaining = total - downloadedBytes;
    if (remaining <= 0) return 0;
    return (remaining / speed).ceil();
  }

  DownloadRecord copyWith({
    String? title,
    String? fileName,
    String? filePath,
    String? thumbnailUrl,
    int? totalBytes,
    int? downloadedBytes,
    double? speedBytesPerSecond,
    DownloadStatus? status,
    DateTime? completedAt,
    String? errorMessage,
    String? downloadUrl,
    Map<String, String>? headers,
    String? audioUrl,
    int? audioBytes,
    int? reencodeKbps,
    bool? supportsResume,
    bool clearSpeed = false,
    bool clearError = false,
    bool clearAudio = false,
    bool clearReencode = false,
  }) {
    return DownloadRecord(
      id: id,
      sourceUrl: sourceUrl,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      supportsResume: supportsResume ?? this.supportsResume,
      headers: headers ?? this.headers,
      audioUrl: clearAudio ? null : (audioUrl ?? this.audioUrl),
      audioBytes: clearAudio ? null : (audioBytes ?? this.audioBytes),
      reencodeKbps: clearReencode ? null : (reencodeKbps ?? this.reencodeKbps),
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      source: source,
      mediaType: mediaType,
      format: format,
      quality: quality,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      speedBytesPerSecond: clearSpeed
          ? null
          : (speedBytesPerSecond ?? this.speedBytesPerSecond),
      status: status ?? this.status,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      groupId: groupId,
    );
  }
}
