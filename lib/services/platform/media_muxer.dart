import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';

/// Assembles downloaded tracks into the file the user asked for.
///
/// Backed by Android's own `MediaMuxer` and `MediaCodec`, so the app carries
/// no media library. Merging a video with an AAC soundtrack re-encodes
/// nothing — the compressed samples are copied into a new container as-is —
/// while a soundtrack in another codec, or an audio download at a bitrate the
/// source does not serve, is encoded on the device.
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

  /// Writes [source] into [output] as AAC at [bitrateKbps].
  ///
  /// Used for an audio download at a bitrate the source does not publish. The
  /// sound is only ever as good as what came down — encoding a 128 kbps track
  /// at 320 kbps makes a bigger file of the same music — so this is called
  /// only when the chosen variant asks for it.
  ///
  /// Returns false when the device could not encode it, so the caller can fail
  /// the download with a real message instead of publishing a broken file.
  Future<bool> transcode({
    required File source,
    required File output,
    required int bitrateKbps,
  }) async {
    try {
      final done = await _channel.invokeMethod<bool>('transcode', {
        'input': source.path,
        'output': output.path,
        'bitrate': bitrateKbps * 1000,
      });
      return done ?? false;
    } on PlatformException catch (error) {
      AppLog.warn('Re-encoding audio', error.message ?? error.code);
      return false;
    } on MissingPluginException {
      // Not an Android build; nothing can encode here.
      return false;
    }
  }
}

final mediaMuxerProvider = Provider<MediaMuxerBridge>(
  (ref) => MediaMuxerBridge(),
);
