import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/app_log.dart';

import '../../../core/constants/app_info.dart';
import '../../../data/models/media_option.dart';
import '../../../services/platform/platform_permissions.dart';
import '../domain/download_storage.dart';

/// Storage backed by Android's shared Downloads collection.
///
/// Partial files live in the app cache, which Android may reclaim under
/// pressure — exactly the right place for resumable scratch data. Finished
/// files are handed to the platform, which writes them into
/// `Download/Hoza Download/{Videos,Audio}` through MediaStore so normal file
/// managers and media apps can see them.
class SharedDownloadStorage implements DownloadStorage {
  SharedDownloadStorage(this._permissions, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.hoza.download/storage';
  static const String _partialExtension = '.hozapart';

  final MethodChannel _channel;
  final PlatformPermissions _permissions;

  Directory? _partialsRoot;

  Future<Directory> _partials() async {
    final cached = _partialsRoot;
    if (cached != null) return cached;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/partials');
    await dir.create(recursive: true);
    return _partialsRoot = dir;
  }

  @override
  Future<File> reserve({
    required String downloadId,
    required String fileName,
    required MediaType mediaType,
  }) async {
    final dir = await _partials();
    // Keyed by download id, not by name: two downloads with the same title must
    // never write into the same partial.
    final file = File('${dir.path}/$downloadId$_partialExtension');
    if (!file.existsSync()) await file.create(recursive: true);
    return file;
  }

  @override
  Future<PublishedFile> publish({
    required File partial,
    required String fileName,
    required String mimeType,
    required MediaType mediaType,
  }) async {
    Map<String, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<String, Object?>('publish', {
        'sourcePath': partial.path,
        'fileName': fileName,
        'mimeType': mimeType,
        'subFolder': mediaType.folderName,
      });
    } on PlatformException catch (error) {
      // The platform already phrased the problem; surface it as a storage
      // failure so the caller has one exception type to handle.
      throw FileSystemException(
        error.message ?? 'The download could not be saved',
      );
    } on MissingPluginException {
      throw const FileSystemException('Saving files is not available here');
    }

    if (result == null) {
      throw const FileSystemException('The download could not be saved');
    }

    final location = result['location'] as String?;
    if (location == null || location.isEmpty) {
      throw const FileSystemException('The download could not be saved');
    }

    return PublishedFile(
      location: location,
      fileName: result['fileName'] as String? ?? fileName,
    );
  }

  @override
  Future<void> discardPartial(String downloadId) async {
    // A download in progress owns more than one file: a paired video keeps a
    // track apiece, and a transfer split across several connections keeps a
    // slice apiece. They all hang off the same partial name, so everything
    // that starts with it goes together — otherwise a cancelled download
    // leaves bytes behind that nothing will ever claim.
    final prefix = '$downloadId$_partialExtension';
    try {
      final dir = await _partials();
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (name == prefix || name.startsWith('$prefix.')) {
          await entry.delete();
        }
      }
    } on FileSystemException {
      // A leftover partial in the cache directory is reclaimable by Android.
    }
  }

  @override
  Future<int> clearPartials() async {
    try {
      final dir = await _partials();
      if (!dir.existsSync()) return 0;

      var removed = 0;
      for (final entity in dir.listSync()) {
        // One bad entry must not abandon the rest of the sweep.
        try {
          entity.deleteSync(recursive: true);
          removed++;
        } catch (error) {
          AppLog.warn('Removing a partial download', error);
        }
      }
      return removed;
    } catch (error) {
      AppLog.warn('Clearing partial downloads', error);
      return 0;
    }
  }

  @override
  Future<int> sweepPartials(Set<String> keepIds) async {
    try {
      final dir = await _partials();
      if (!dir.existsSync()) return 0;

      var removed = 0;
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;

        // Chunks are named `{id}.hozapart`, with paired tracks and split
        // slices hanging off the same stem. Anything that is not ours, or has
        // no id in front of the marker, is left alone.
        final name = entity.uri.pathSegments.last;
        final marker = name.indexOf(_partialExtension);
        if (marker <= 0) continue;
        if (keepIds.contains(name.substring(0, marker))) continue;

        try {
          entity.deleteSync();
          removed++;
        } catch (error) {
          AppLog.warn('Removing an orphaned partial', error);
        }
      }
      return removed;
    } catch (error) {
      AppLog.warn('Sweeping orphaned partials', error);
      return 0;
    }
  }

  @override
  Future<bool> exists({
    required String fileName,
    required MediaType mediaType,
  }) async {
    return await _call<bool>('exists', {
          'fileName': fileName,
          'subFolder': mediaType.folderName,
        }) ??
        false;
  }

  @override
  Future<bool> open({
    required String location,
    required String mimeType,
  }) async {
    return await _call<bool>('open', {
          'location': location,
          'mimeType': mimeType,
        }) ??
        false;
  }

  @override
  Future<bool> openLink(Uri url) async {
    return await _call<bool>('openLink', {'url': url.toString()}) ?? false;
  }

  @override
  Future<bool> share({
    required String location,
    required String mimeType,
  }) async {
    return await _call<bool>('share', {
          'location': location,
          'mimeType': mimeType,
        }) ??
        false;
  }

  @override
  Future<String?> rename({required String location, required String fileName}) {
    return _call<String>('rename', {
      'location': location,
      'fileName': fileName,
    });
  }

  @override
  Future<StorageInfo> storageInfo() async {
    final raw = await _call<Map<Object?, Object?>>('storageInfo', const {});
    if (raw == null) return StorageInfo.unknown;

    final free = raw['free'];
    final total = raw['total'];
    if (free is! int || total is! int) return StorageInfo.unknown;
    return StorageInfo(freeBytes: free, totalBytes: total);
  }

  @override
  Future<bool> deleteFile(String location) async {
    return await _call<bool>('delete', {'location': location}) ?? false;
  }

  @override
  Future<String> describeLocation() async {
    return await _call<String>('describeLocation', const {}) ??
        // Matches what the platform reports; kept in one place.
        AppInfo.downloadFolder;
  }

  @override
  Future<bool> ensureWritable() => _permissions.ensureLegacyStorage();

  /// Platform failures are logged and turned into a null result; callers decide
  /// what a missing answer means rather than being handed an exception from the
  /// other side of the channel.
  Future<T?> _call<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      AppLog.warn('Storage.$method', error.code);
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

final downloadStorageProvider = Provider<DownloadStorage>((ref) {
  return SharedDownloadStorage(ref.watch(platformPermissionsProvider));
});

/// The folder shown on the Settings screen. Read from the storage service so
/// it always reflects where files are really being written.
final downloadLocationProvider = FutureProvider<String>(
  (ref) => ref.watch(downloadStorageProvider).describeLocation(),
);
