import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';

import '../../core/utils/url_utils.dart';

/// Receives links shared to Hoza Download from other Android apps.
///
/// Backed by a small platform channel rather than a package: Android already
/// gives us everything needed through `ACTION_SEND`, and owning the ~90 lines
/// of Kotlin keeps cold-start and warm-start delivery under our control.
class ShareService {
  ShareService({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel =
          methodChannel ?? const MethodChannel('com.hoza.download/share'),
      _eventChannel =
          eventChannel ?? const EventChannel('com.hoza.download/share_events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  /// Links shared while the app is running.
  ///
  /// Raw platform text is parsed here so a malformed payload never reaches
  /// the UI as a link. It still surfaces, as null: a share that carried no
  /// usable link has opened a window that now has to be closed.
  Stream<Uri?> get sharedLinks =>
      _eventChannel.receiveBroadcastStream().map(_parse);

  /// The link that launched the app, if any.
  ///
  /// Claims it from the platform side, which then forgets it — calling twice
  /// cannot open the same share twice.
  Future<Uri?> consumeInitialLink() async {
    try {
      final raw = await _methodChannel.invokeMethod<String>(
        'consumeInitialLink',
      );
      return _parse(raw);
    } on PlatformException catch (error) {
      // A missing channel is expected on non-Android platforms; never fatal.
      AppLog.warn('Reading the launching share', error.code);
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Uri? _parse(Object? raw) {
    if (raw is! String) return null;
    final validation = UrlUtils.validate(raw);
    return validation.url;
  }
}

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());
