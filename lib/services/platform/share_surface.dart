import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';

/// Which window the engine is being drawn into.
enum ShareHost {
  /// The full app.
  app,

  /// The floating share sheet over another app.
  share,
}

/// Controls the translucent window a shared link opens in.
///
/// That window starts out invisible and is revealed only once the sheet is
/// ready to animate in, so the user never sees a frame of the app itself — the
/// point of the share sheet is that it appears over whatever they were
/// watching.
class ShareSurface {
  ShareSurface({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.hoza.download/surface') {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  final MethodChannel _channel;

  final StreamController<void> _dismissals = StreamController<void>.broadcast();
  final StreamController<ShareHost> _hosts =
      StreamController<ShareHost>.broadcast();

  /// Fires when the share window goes away without Dart closing it — a back
  /// gesture, a swipe, or the system reclaiming it.
  Stream<void> get dismissals => _dismissals.stream;

  /// Fires whenever a window takes the engine, saying which kind it is.
  Stream<ShareHost> get hosts => _hosts.stream;

  /// Fade the window in. Safe to call more than once.
  Future<void> ready() => _invoke('ready');

  /// Close the window and return the user to the app they shared from.
  Future<void> close() => _invoke('close');

  /// Bring the full app forward, e.g. when the user asks for their downloads.
  Future<void> openApp() => _invoke('openApp');

  /// Which window holds the engine right now, or null when none does — or
  /// when there is no platform side to ask, as off Android.
  ///
  /// Asked directly rather than remembered from [hosts]: the first host
  /// change is sent while Dart is still booting, before anything listens.
  Future<ShareHost?> currentHost() async {
    try {
      final host = await _channel.invokeMethod<String>('host');
      return switch (host) {
        'share' => ShareHost.share,
        'app' => ShareHost.app,
        _ => null,
      };
    } on PlatformException catch (error) {
      AppLog.warn('Share window host', error.code);
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      AppLog.warn('Share window $method', error.code);
    } on MissingPluginException {
      // Expected off Android, where there is no floating window to drive.
    }
  }

  Future<void> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'overlayDismissed':
        _dismissals.add(null);
      case 'hostChanged':
        _hosts.add(call.arguments == 'share' ? ShareHost.share : ShareHost.app);
    }
  }
}

final shareSurfaceProvider = Provider<ShareSurface>((ref) => ShareSurface());
