import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/app_log.dart';
import '../../data/models/media_option.dart';

/// What this device's muxer will assemble.
///
/// Everything Android has ever muxed writes an MP4 holding H.264 beside AAC,
/// so that pairing is not asked about. A WebM holding VP9 beside Opus is: it
/// is the only way to save YouTube's 1440p and 2160p renditions without
/// re-encoding the picture, and not every device's writer takes it. A quality
/// is only offered once the device has said it can finish the file.
@immutable
class MuxSupport {
  const MuxSupport({required this.webm});

  /// Nothing extra: what a device is assumed to do until it has answered.
  static const MuxSupport none = MuxSupport(webm: false);

  /// Whether VP9 and Opus can be written into a WebM here.
  final bool webm;

  /// Whether a video saved as [format] can be assembled on this device.
  bool writes(MediaFormat format) => format != MediaFormat.webm || webm;
}

/// Assembles downloaded tracks into the file the user asked for.
///
/// Backed by Android's own `MediaMuxer` and `MediaCodec`, so the app carries
/// no media library. Merging a video with a soundtrack the container takes
/// re-encodes nothing — the compressed samples are copied into a new container
/// as-is — while a soundtrack in a codec the container refuses, or an audio
/// download at a bitrate the source does not serve, is encoded on the device.
class MediaMuxerBridge {
  MediaMuxerBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.hoza.download/muxer';

  final MethodChannel _channel;

  /// What the device answered last time it was asked. The probe writes a file,
  /// so it is done once per run rather than once per link.
  Future<MuxSupport>? _support;

  /// What this device can assemble, asked once and remembered.
  ///
  /// Answered by writing a throwaway file, not by reading the Android version:
  /// which codecs a build's muxer accepts is not something the version says.
  Future<MuxSupport> support() => _support ??= _askSupport();

  Future<MuxSupport> _askSupport() async {
    try {
      final probeDir = await getTemporaryDirectory();
      final answer = await _channel.invokeMapMethod<String, dynamic>(
        'capabilities',
        {'probeDir': probeDir.path},
      );
      return MuxSupport(webm: answer?['webm'] == true);
    } on PlatformException catch (error) {
      AppLog.warn('Asking what the muxer writes', error.message ?? error.code);
      return MuxSupport.none;
    } on MissingPluginException {
      // Not an Android build; nothing can merge tracks here at all.
      return MuxSupport.none;
    }
  }

  /// Writes [video] + [audio] into [output] as [format].
  ///
  /// Returns false when the platform could not merge them — a codec the muxer
  /// will not accept, or no muxer at all — so the caller can fail the download
  /// with a real message instead of publishing a silent video.
  Future<bool> merge({
    required File video,
    required File audio,
    required File output,
    MediaFormat format = MediaFormat.mp4,
  }) async {
    try {
      final merged = await _channel.invokeMethod<bool>('mux', {
        'video': video.path,
        'audio': audio.path,
        'output': output.path,
        // The container decides what may be copied across untouched and what
        // has to be re-encoded first, so the platform is told which one this
        // download is rather than guessing from the tracks.
        'container': format.extension,
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
