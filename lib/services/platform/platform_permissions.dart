import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';

/// Runtime permissions Hoza asks for, and only when it needs them.
///
/// Each answer is cached for the session: Android shows its dialog once, and a
/// refusal must not turn into a prompt on every download.
class PlatformPermissions {
  PlatformPermissions({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.hoza.download/permissions';

  final MethodChannel _channel;

  bool? _notifications;
  bool? _legacyStorage;

  /// Needed on Android 13+ before the download progress notification can be
  /// shown. Declining is not fatal — transfers still run.
  Future<bool> ensureNotifications() async {
    return _notifications ??= await _request('ensureNotifications');
  }

  /// Needed only on Android 9 and older, where files are written to the public
  /// Downloads folder directly. Android 10+ always answers true.
  Future<bool> ensureLegacyStorage() async {
    return _legacyStorage ??= await _request('ensureLegacyStorage');
  }

  Future<bool> _request(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException catch (error) {
      AppLog.warn('Permission $method', error.code);
      return false;
    } on MissingPluginException {
      // Not Android: nothing to ask for.
      return true;
    }
  }
}

final platformPermissionsProvider = Provider<PlatformPermissions>(
  (ref) => PlatformPermissions(),
);
