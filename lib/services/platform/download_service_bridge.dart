import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';

/// Buttons on the ongoing notification. Which ones show depends on what the
/// queue is doing; what they do is decided by the queue, not the platform.
enum DownloadNotificationAction {
  pauseAll('pause'),
  resumeAll('resume'),
  cancelAll('cancel');

  const DownloadNotificationAction(this.key);

  final String key;

  static DownloadNotificationAction? fromKey(String? key) {
    for (final action in values) {
      if (action.key == key) return action;
    }
    return null;
  }
}

/// Drives the Android foreground service that keeps transfers alive.
///
/// Transfers themselves run in the Flutter isolate; this only tells Android
/// that the work is happening and what to show while it does. It is a hint, not
/// a dependency — if the platform refuses, downloads carry on without the
/// notification.
class DownloadServiceBridge {
  DownloadServiceBridge({MethodChannel? channel, MethodChannel? actions})
    : _channel = channel ?? const MethodChannel(_channelName),
      _actions = actions ?? const MethodChannel(_actionsChannelName) {
    _actions.setMethodCallHandler(_onAction);
  }

  static const String _channelName = 'com.hoza.download/service';
  static const String _actionsChannelName =
      'com.hoza.download/download_actions';

  /// How often the ongoing notification is redrawn at most. Progress ticks
  /// arrive several times a second; Android throttles an app that posts that
  /// fast, and nobody reads a speed that flickers.
  static const Duration _minInterval = Duration(milliseconds: 600);

  final MethodChannel _channel;
  final MethodChannel _actions;

  final StreamController<DownloadNotificationAction> _tapped =
      StreamController<DownloadNotificationAction>.broadcast();

  /// A button on the notification was pressed.
  Stream<DownloadNotificationAction> get actions => _tapped.stream;

  bool _running = false;
  String? _lastSignature;
  DateTime? _lastSentAt;
  Timer? _trailing;
  Map<String, Object?>? _pendingArguments;

  Future<Object?> _onAction(MethodCall call) async {
    if (call.method != 'action') return null;
    final action = DownloadNotificationAction.fromKey(
      call.arguments as String?,
    );
    if (action != null) _tapped.add(action);
    return null;
  }

  /// Starts the service if needed and refreshes the ongoing notification.
  ///
  /// [text] is the one-line summary shown collapsed; [details] is the fuller
  /// text shown when the notification is expanded, and [subText] the small
  /// label beside the app name. [progress] is 0–100, or null when the total
  /// size is unknown, which shows an indeterminate bar rather than a made-up
  /// percentage. [buttons] are the actions to offer, in order.
  Future<void> update({
    required String title,
    required String text,
    String? details,
    String? subText,
    int? progress,
    List<DownloadNotificationAction> buttons = const [],
  }) async {
    final arguments = <String, Object?>{
      'title': title,
      'text': text,
      'details': details ?? text,
      'subText': subText,
      'progress': progress ?? -1,
      'actions': [for (final button in buttons) button.key],
    };

    // The notification only needs redrawing when something visible changed.
    final signature = arguments.values.join('|');
    if (_running && signature == _lastSignature) return;

    // Too soon after the last redraw: keep the newest state and send it once
    // the interval has passed, so the bar never freezes on a stale value.
    final sentAt = _lastSentAt;
    if (_running && sentAt != null) {
      final elapsed = DateTime.now().difference(sentAt);
      if (elapsed < _minInterval) {
        _pendingArguments = arguments;
        _trailing ??= Timer(_minInterval - elapsed, _flush);
        return;
      }
    }

    await _send(arguments, signature);
  }

  Future<void> _flush() async {
    _trailing = null;
    final arguments = _pendingArguments;
    _pendingArguments = null;
    if (arguments == null || !_running) return;
    await _send(arguments, arguments.values.join('|'));
  }

  Future<void> _send(Map<String, Object?> arguments, String signature) async {
    _lastSentAt = DateTime.now();
    final sent = await _call('update', arguments);
    if (sent) {
      _running = true;
      _lastSignature = signature;
    }
  }

  /// Forgets what was last shown, so the next [update] is posted even if
  /// nothing changed — needed once the user grants notification access after
  /// a download has already started, or the bar would stay hidden until the
  /// numbers moved.
  void invalidate() {
    _lastSignature = null;
  }

  /// Stops the service. Safe to call when it is not running.
  Future<void> stop() async {
    _trailing?.cancel();
    _trailing = null;
    _pendingArguments = null;
    if (!_running) return;
    _running = false;
    _lastSignature = null;
    _lastSentAt = null;
    await _call('stop', const {});
  }

  Future<bool> _call(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<bool>(method, arguments);
      return true;
    } on PlatformException catch (error) {
      AppLog.warn('Download service $method', error.code);
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final downloadServiceBridgeProvider = Provider<DownloadServiceBridge>((ref) {
  final bridge = DownloadServiceBridge();
  ref.onDispose(bridge.stop);
  return bridge;
});
