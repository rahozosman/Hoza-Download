import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';

/// Merges a downloaded video track and audio track into one playable file.
///
/// Backed by Android's own `MediaMuxer`, so nothing is re-encoded and the app
/// carries no media library: the compressed samples are copied into a new
/// container as-is.
class MediaMuxerBridge {
  MediaMuxerBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.hoza.download/muxer';

  final MethodChannel _channel;

  /// Writes [video] + [audio] into [output].
  ///
  /// Returns false when the platform could not merge them — a codec the muxer
  /// will not accept, or no muxer at all — so the caller can fail the download
  /// with a real message instead of publishing a silent video.
  Future<bool> merge({
    required File video,
    required File audio,
    required File output,
  }) async {
    try {
      final merged = await _channel.invokeMethod<bool>('mux', {
        'video': video.path,
        'audio': audio.path,
        'output': output.path,
      });
      return merged ?? false;
    } on PlatformException catch (error) {
      AppLog.warn('Merging video and audio', error.message ?? error.code);
      return false;
    } on MissingPluginException {
      // Not an Android build; nothing can merge the tracks here.
      return false;
    }
  }
}

final mediaMuxerProvider = Provider<MediaMuxerBridge>(
  (ref) => MediaMuxerBridge(),
);
