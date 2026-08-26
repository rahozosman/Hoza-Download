import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';

/// Posts the one-off notifications for downloads that finished or failed.
///
/// Whether to post at all is the caller's decision, driven by the user's
/// notification preferences. A platform failure here is logged and ignored: a
/// missing notification must never affect the download itself.
class DownloadNotifications {
  DownloadNotifications({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.hoza.download/notifications');

  final MethodChannel _channel;

  Future<void> showCompleted({
    required String id,
    required String title,
    required String text,
    required String mimeType,
    String? location,
    String? mediaType,
  }) => _call('showCompleted', {
    'id': id,
    'mediaType': mediaType,
    'title': title,
    'text': text,
    'mimeType': mimeType,
    'location': location,
  });

  Future<void> showFailed({
    required String id,
    required String title,
    required String text,
  }) => _call('showFailed', {'id': id, 'title': title, 'text': text});

  /// A quiet note that opens the app: downloads that were interrupted, and
  /// the like. Neither a success nor a failure, so neither icon.
  Future<void> showInfo({
    required String id,
    required String title,
    required String text,
  }) => _call('showInfo', {'id': id, 'title': title, 'text': text});

  /// Clears a notification for a download the user has since removed.
  Future<void> cancel(String id) => _call('cancel', {'id': id});

  Future<void> _call(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<bool>(method, arguments);
    } on PlatformException catch (error) {
      AppLog.warn('Notification $method', error.code);
    } on MissingPluginException {
      // Not Android: nothing to post.
    }
  }
}

final downloadNotificationsProvider = Provider<DownloadNotifications>(
  (ref) => DownloadNotifications(),
);
