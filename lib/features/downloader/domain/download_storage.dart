import 'dart:io';

import '../../../data/models/media_option.dart';

/// Result of publishing a finished download.
class PublishedFile {
  const PublishedFile({required this.location, required this.fileName});

  /// What the app stores and later passes back to open or delete the file:
  /// a MediaStore content URI, or a file path on older Android.
  final String location;

  /// The name Android actually used. May differ from the requested name when
  /// the original was already taken.
  final String fileName;
}

/// Where partial and finished downloads live.
///
/// Splitting this out keeps the Android storage rules in one place: the engine
/// only ever writes to the file it is handed, and publishing to a user-visible
/// location is this service's problem.
abstract interface class DownloadStorage {
  /// Creates the partial file a transfer writes into.
  ///
  /// Returns an existing partial untouched so a paused download can resume.
  Future<File> reserve({
    required String downloadId,
    required String fileName,
    required MediaType mediaType,
  });

  /// Moves a finished partial into the user's shared Downloads folder.
  Future<PublishedFile> publish({
    required File partial,
    required String fileName,
    required String mimeType,
    required MediaType mediaType,
  });

  /// Removes the partial file for a download. Safe when there is none.
  ///
  /// Takes an id rather than a File so a download restored from the database,
  /// whose File this session never held, can still be cleaned up.
  Future<void> discardPartial(String downloadId);

  /// Deletes every partial chunk left behind by interrupted transfers, and
  /// returns how many were removed.
  ///
  /// Scoped to the app's own scratch directory. Published files live outside
  /// it and are never touched by this.
  Future<int> clearPartials();

  /// Deletes only the chunks that no longer belong to a known download, and
  /// returns how many were removed.
  ///
  /// A crash mid-transfer leaves bytes behind that no record will ever claim.
  /// Nothing else ever looks at them again, so without this sweep the cache
  /// only grows.
  Future<int> sweepPartials(Set<String> keepIds);

  /// True when a finished download already occupies [fileName].
  Future<bool> exists({required String fileName, required MediaType mediaType});

  /// Hands a published file to whichever app the user has for that type.
  /// Returns false when nothing on the device can open it.
  Future<bool> open({required String location, required String mimeType});

  /// Opens the page a download came from in the app that owns it — TikTok,
  /// Instagram, YouTube — or the browser when that app is not installed.
  /// Returns false when nothing on the device can open it.
  Future<bool> openLink(Uri url);

  /// Deletes a published file. Returns true when it is gone afterwards.
  Future<bool> deleteFile(String location);

  /// Where finished downloads are actually written, for display in Settings.
  ///
  /// Resolved from the platform rather than a constant, so the UI can never
  /// advertise a folder the app is not using.
  Future<String> describeLocation();

  /// Offers a published file to the Android share sheet.
  Future<bool> share({required String location, required String mimeType});

  /// Renames the saved file itself, returning the name it ended up with.
  ///
  /// Returns null when the file could not be renamed, so the caller can leave
  /// the record alone rather than showing a name that is not on disk.
  Future<String?> rename({required String location, required String fileName});

  /// How much room is left on the download volume.
  Future<StorageInfo> storageInfo();

  /// Asks for any permission this storage backend needs before a download
  /// starts. Returns false when the user declined.
  Future<bool> ensureWritable();
}

/// Free and total bytes on the volume downloads are written to.
class StorageInfo {
  const StorageInfo({required this.freeBytes, required this.totalBytes});

  static const StorageInfo unknown = StorageInfo(freeBytes: -1, totalBytes: -1);

  final int freeBytes;
  final int totalBytes;

  bool get isKnown => freeBytes >= 0 && totalBytes > 0;

  int get usedBytes => isKnown ? totalBytes - freeBytes : -1;
}
