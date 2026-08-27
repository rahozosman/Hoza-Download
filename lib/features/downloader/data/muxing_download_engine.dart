import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/networking/http_client_provider.dart';
import '../../../services/platform/media_muxer.dart';
import '../domain/download_engine.dart';
import 'http_download_engine.dart';
import 'segmented_download_engine.dart';

/// Adds paired video+audio downloads, and re-encoded audio downloads, on top
/// of a plain byte engine.
///
/// Sites that publish adaptive streams keep the picture and the sound in
/// separate files. This engine fetches both — one after the other, so the
/// bandwidth still goes to one transfer at a time — and merges them into the
/// file the caller asked for. An audio download at a bitrate the source does
/// not publish takes the same shape with the video stage left out: the track
/// comes down once and is written back out at the chosen bitrate. A request
/// that needs neither is handed straight to [_inner], so ordinary downloads
/// take exactly the path they always did.
class MuxingDownloadEngine implements DownloadEngine {
  const MuxingDownloadEngine(this._inner, this._muxer);

  final DownloadEngine _inner;
  final MediaMuxerBridge _muxer;

  @override
  DownloadTask start(DownloadRequest request) {
    if (request.audioUrl == null && request.reencodeKbps == null) {
      return _inner.start(request);
    }
    return _AssembledDownloadTask(_inner, _muxer, request);
  }
}

/// Runs the transfers and the assembling step as one task, so the rest of the
/// app still sees a single download with a single outcome.
class _AssembledDownloadTask implements DownloadTask {
  _AssembledDownloadTask(this._inner, this._muxer, this._request) {
    unawaited(_run());
  }

  final DownloadEngine _inner;
  final MediaMuxerBridge _muxer;
  final DownloadRequest _request;

  final StreamController<DownloadProgress> _progress =
      StreamController<DownloadProgress>.broadcast();
  final Completer<DownloadOutcome> _outcome = Completer<DownloadOutcome>();

  StreamSubscription<DownloadProgress>? _sub;
  DownloadTask? _stage;

  /// Set as soon as the user asks to stop, even before a stage exists.
  bool _pauseRequested = false;
  bool _cancelRequested = false;

  /// Bytes of the tracks that already finished, so the combined progress the
  /// UI sees only ever moves forward.
  int _completedBytes = 0;

  File get _videoPart => File('${_request.target.path}.v');
  File get _audioPart => File('${_request.target.path}.a');

  /// Whether there is a picture to fetch and merge. False for an audio-only
  /// download that is here purely to be re-encoded.
  bool get _hasVideo => _request.audioUrl != null;

  /// Where the sound comes from: its own track for a paired download, the
  /// request's own address for an audio-only one.
  Uri get _audioUrl => _request.audioUrl ?? _request.url;

  /// Size of the sound as the source serves it.
  int? get _audioBytes =>
      _hasVideo ? _request.audioBytes : _request.expectedBytes;

  /// Size of the video track alone. Known only when the source reported both
  /// the combined size and the audio size.
  int? get _videoBytes {
    final total = _request.expectedBytes;
    final audio = _request.audioBytes;
    if (total == null || audio == null) return null;
    final video = total - audio;
    return video > 0 ? video : null;
  }

  @override
  Stream<DownloadProgress> get progress => _progress.stream;

  @override
  Future<DownloadOutcome> get outcome => _outcome.future;

  @override
  Future<void> pause() async {
    _pauseRequested = true;
    await _stage?.pause();
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    await _stage?.cancel();
    // A stop that lands between the two stages still has to take effect.
    if (_stage == null) await _finishCancelled();
  }

  Future<void> _run() async {
    try {
      if (_hasVideo) {
        final video = await _fetch(
          url: _request.url,
          target: _videoPart,
          expected: _videoBytes,
        );
        if (video != null) return _complete(video);

        _completedBytes = await _lengthOf(_videoPart);
      }

      final audio = await _fetch(
        url: _audioUrl,
        target: _audioPart,
        expected: _audioBytes,
      );
      if (audio != null) return _complete(audio);

      _completedBytes += await _lengthOf(_audioPart);
      await _assemble();
    } on FileSystemException {
      await _discardParts();
      _complete(
        DownloadFailed(
          kind: DownloadErrorKind.storage,
          receivedBytes: _completedBytes,
        ),
      );
    }
  }

  /// Runs one stage. Returns the outcome to report when the stage did not
  /// finish, or null when it succeeded and the run should continue.
  Future<DownloadOutcome?> _fetch({
    required Uri url,
    required File target,
    required int? expected,
  }) async {
    if (_cancelRequested) return await _cancelledOutcome();
    if (_pauseRequested) return DownloadPaused(receivedBytes: _completedBytes);

    // A track that is already whole on disk — from a paused run — is not
    // fetched again.
    final onDisk = await _lengthOf(target);
    if (expected != null && expected > 0 && onDisk >= expected) return null;

    final stage = _inner.start(
      DownloadRequest(
        id: _request.id,
        url: url,
        target: target,
        mediaType: _request.mediaType,
        format: _request.format,
        expectedBytes: expected,
        supportsResume: _request.supportsResume,
        startAt: _request.supportsResume ? onDisk : 0,
        headers: _request.headers,
      ),
    );
    _stage = stage;

    _sub = stage.progress.listen((sample) {
      if (_progress.isClosed) return;
      _progress.add(
        DownloadProgress(
          receivedBytes: _completedBytes + sample.receivedBytes,
          totalBytes: _request.expectedBytes,
          bytesPerSecond: sample.bytesPerSecond,
        ),
      );
    });

    // The stop may have arrived while the stage was starting.
    if (_cancelRequested) {
      await stage.cancel();
    } else if (_pauseRequested) {
      await stage.pause();
    }

    final result = await stage.outcome;
    await _sub?.cancel();
    _sub = null;
    _stage = null;

    switch (result) {
      case DownloadSucceeded():
        return null;
      // The stage reports what it actually holds, which is not always what the
      // track file weighs: a transfer split across several connections keeps
      // its bytes in slices until they are joined.
      case DownloadPaused(:final receivedBytes):
        return DownloadPaused(receivedBytes: _completedBytes + receivedBytes);
      case DownloadCancelled():
        return await _cancelledOutcome();
      case DownloadFailed(:final kind, :final receivedBytes):
        return DownloadFailed(
          kind: kind,
          receivedBytes: _completedBytes + receivedBytes,
        );
    }
  }

  /// Turns the fetched track — or pair of tracks — into the file the user
  /// asked for.
  Future<void> _assemble() async {
    final done = _hasVideo
        ? await _muxer.merge(
            video: _videoPart,
            audio: _audioPart,
            output: _request.target,
          )
        : await _muxer.transcode(
            source: _audioPart,
            output: _request.target,
            bitrateKbps: _request.reencodeKbps!,
          );

    if (!done) {
      // Never publish a silent video or a half-written track: the download
      // failed, and says why.
      await _discardParts();
      await _delete(_request.target);
      _complete(
        DownloadFailed(
          kind: _hasVideo ? DownloadErrorKind.merge : DownloadErrorKind.encode,
          receivedBytes: _completedBytes,
        ),
      );
      return;
    }

    await _discardParts();
    final size = await _lengthOf(_request.target);
    _complete(DownloadSucceeded(file: _request.target, totalBytes: size));
  }

  Future<DownloadOutcome> _cancelledOutcome() async {
    await _discardParts();
    await _delete(_request.target);
    return const DownloadCancelled();
  }

  Future<void> _finishCancelled() async {
    if (_outcome.isCompleted) return;
    _complete(await _cancelledOutcome());
  }

  void _complete(DownloadOutcome outcome) {
    if (_outcome.isCompleted) return;
    unawaited(_sub?.cancel());
    _sub = null;
    _outcome.complete(outcome);
    unawaited(_progress.close());
  }

  Future<void> _discardParts() async {
    // A track that was fetched in slices leaves those slices next to its part
    // file; dropping the part without them would strand them on disk.
    await SegmentedDownloadEngine.discardSegments(_videoPart);
    await SegmentedDownloadEngine.discardSegments(_audioPart);
    await _delete(_videoPart);
    await _delete(_audioPart);
  }

  static Future<void> _delete(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // A leftover part in the cache directory is reclaimable by Android.
    }
  }

  static Future<int> _lengthOf(File file) async {
    try {
      return file.existsSync() ? await file.length() : 0;
    } on FileSystemException {
      return 0;
    }
  }
}

/// The engine the app downloads with, assembled from the inside out: bytes are
/// moved a slice at a time where the host allows it, one stream where it does
/// not, and paired tracks are merged on top of whichever of those ran.
final downloadEngineProvider = Provider<DownloadEngine>((ref) {
  final client = ref.watch(httpClientProvider);
  return MuxingDownloadEngine(
    SegmentedDownloadEngine(client, HttpDownloadEngine(client)),
    ref.watch(mediaMuxerProvider),
  );
});
