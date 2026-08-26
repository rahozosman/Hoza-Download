/// Lifecycle of a single download.
///
/// The set is closed on purpose: the download engine added in a later section
/// drives every transition through this enum so the UI can never show a
/// contradictory state such as "completed" while bytes are still arriving.
enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled;

  /// Stable key for database rows and preferences. Never localise this.
  String get storageKey => name;

  static DownloadStatus fromStorageKey(String? key) {
    return DownloadStatus.values.firstWhere(
      (status) => status.name == key,
      orElse: () => DownloadStatus.failed,
    );
  }

  /// Bytes may still be moving (or about to).
  bool get isActive =>
      this == DownloadStatus.queued || this == DownloadStatus.downloading;

  /// No further work will happen without user action.
  bool get isTerminal =>
      this == DownloadStatus.completed ||
      this == DownloadStatus.failed ||
      this == DownloadStatus.cancelled;

  bool get canPause => this == DownloadStatus.downloading;
  bool get canResume => this == DownloadStatus.paused;
  bool get canCancel => !isTerminal;
  bool get canRetry =>
      this == DownloadStatus.failed || this == DownloadStatus.cancelled;
}
