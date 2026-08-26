import 'dart:async';
import 'dart:io';

import '../../../core/utils/app_log.dart';
import '../../../services/networking/http_client_provider.dart';
import '../domain/download_engine.dart';
import 'request_profiles.dart';
import 'request_race.dart';
import 'transfer_policy.dart';

/// Streams a download straight to disk over HTTP.
///
/// Bytes are written chunk by chunk and never buffered whole in memory, so a
/// multi-gigabyte video costs the same working set as a small one.
///
/// A host that only serves bounded byte ranges (see [TransferPolicy]) is read
/// as a series of range requests on the same connection, appended to one
/// file; every other host is read in a single request.
class HttpDownloadEngine implements DownloadEngine {
  const HttpDownloadEngine(this._client);

  final HttpClient _client;

  @override
  DownloadTask start(DownloadRequest request) =>
      _HttpDownloadTask(_client, request);
}

enum _StopMode { pause, cancel }

class _HttpDownloadTask implements DownloadTask {
  _HttpDownloadTask(this._client, this._request) {
    unawaited(_run());
  }

  final HttpClient _client;
  final DownloadRequest _request;

  final StreamController<DownloadProgress> _progress =
      StreamController<DownloadProgress>.broadcast();
  final Completer<DownloadOutcome> _outcome = Completer<DownloadOutcome>();

  StreamSubscription<List<int>>? _subscription;
  Completer<Object?>? _transfer;

  /// Set when a 416 forced a restart; user actions are forwarded to the run
  /// that is actually moving bytes.
  _HttpDownloadTask? _delegate;

  int _received = 0;
  int? _total;
  _StopMode? _stopMode;
  bool _restarted = false;

  // Progress pacing and speed smoothing.
  DateTime _lastEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSampleAt = DateTime.now();
  int _lastSampleBytes = 0;
  double? _speed;
  int _sinceFlush = 0;

  /// The UI cannot use samples faster than it paints; this also keeps the
  /// records list from rebuilding on every chunk.
  static const Duration _emitInterval = Duration(milliseconds: 300);

  /// Bytes buffered before the sink is flushed. Flushing also applies
  /// backpressure to the socket, which bounds memory on a fast connection.
  static const int _flushThreshold = 1024 * 1024;

  /// Weight of the newest sample in the smoothed speed.
  static const double _speedSmoothing = 0.35;

  static final Object _stopped = Object();

  @override
  Stream<DownloadProgress> get progress => _progress.stream;

  @override
  Future<DownloadOutcome> get outcome => _outcome.future;

  @override
  Future<void> pause() => _stop(_StopMode.pause);

  @override
  Future<void> cancel() => _stop(_StopMode.cancel);

  Future<void> _stop(_StopMode mode) async {
    if (_outcome.isCompleted || _stopMode != null) return;
    _stopMode = mode;

    final delegate = _delegate;
    if (delegate != null) {
      await (mode == _StopMode.cancel ? delegate.cancel() : delegate.pause());
      return;
    }

    await _subscription?.cancel();
    final transfer = _transfer;
    if (transfer != null && !transfer.isCompleted) transfer.complete(_stopped);
    // If the request has not reached the byte pump yet, _pump picks the stop
    // up as soon as it starts.
  }

  /// Ends the task for a stop that arrived before any bytes were pumped.
  Future<void> _completeStopped() async {
    if (_stopMode == _StopMode.cancel) {
      await _deletePartial();
      _complete(const DownloadCancelled());
    } else {
      _complete(DownloadPaused(receivedBytes: _received));
    }
  }

  Future<void> _run() async {
    _received = _request.startAt;
    _lastSampleBytes = _received;

    try {
      final resuming = _request.startAt > 0 && _request.supportsResume;
      final start = resuming ? _request.startAt : 0;

      // A host that refuses anything but a bounded range is asked for the
      // first slice of the file; every other host is asked for all of it, or
      // for the rest of it when resuming.
      final chunk = TransferPolicy.maxRequestBytes(_request.url);
      final firstEnd = chunk == null ? null : _chunkEnd(start, chunk);
      final String? range;
      if (firstEnd != null) {
        range = 'bytes=$start-$firstEnd';
      } else {
        range = resuming ? 'bytes=$start-' : null;
      }

      // One server, asked several ways at once. A CDN that turns away a bare
      // client usually serves the same file to a request shaped like the
      // browser it was published for, and trying those shapes one after
      // another spends a timeout on each. The first answer that really is the
      // file wins; the rest are dropped before a byte of them is read.
      final outcome = await RequestRace.open(
        _client,
        _request.url,
        profiles: RequestProfiles.forMedia(
          _request.url,
          source: _request.headers,
        ),
        range: range,
      );

      final HttpClientResponse response;
      final RequestProfile profile;
      switch (outcome) {
        case RaceWon(response: final served, profile: final accepted):
          response = served;
          profile = accepted;

        case RaceRefused(:final statusCode):
          // The partial on disk no longer matches the file on the server.
          // Start over once rather than appending onto bytes that do not
          // belong.
          if (statusCode == HttpStatus.requestedRangeNotSatisfiable &&
              !_restarted) {
            _restarted = true;
            _received = 0;
            await _runFromScratch();
            return;
          }
          AppLog.warn(
            'Media request refused',
            'HTTP $statusCode from ${_request.url.host}'
                '${range == null ? '' : ' for $range'}',
          );
          _complete(
            DownloadFailed(
              kind: DownloadErrorKind.forStatus(statusCode),
              receivedBytes: _received,
            ),
          );
          return;

        case RaceErrored(:final error):
          AppLog.warn('Media request failed', '${error.runtimeType}');
          _complete(
            DownloadFailed(kind: _errorKind(error), receivedBytes: _received),
          );
          return;
      }

      // A server may quietly ignore the range header and send the whole file.
      final partial = response.statusCode == HttpStatus.partialContent;
      final appending = resuming && partial;
      if (!appending) {
        _received = 0;
        _lastSampleBytes = 0;
      }
      _total = _resolveTotal(response, appending);

      // Only a host that honoured the bounded range is read a slice at a
      // time; one that sent the whole file is simply read to the end.
      final bounded = firstEnd != null && partial;
      await _pump(
        response,
        appending: appending,
        want: bounded ? firstEnd - start + 1 : null,
        next: bounded ? (chunk!, profile) : null,
      );
    } on TimeoutException {
      _complete(
        DownloadFailed(
          kind: DownloadErrorKind.timeout,
          receivedBytes: _received,
        ),
      );
    } on SocketException {
      _complete(
        DownloadFailed(
          kind: DownloadErrorKind.network,
          receivedBytes: _received,
        ),
      );
    } on HttpException {
      _complete(
        DownloadFailed(
          kind: DownloadErrorKind.network,
          receivedBytes: _received,
        ),
      );
    } on FileSystemException catch (error) {
      _complete(
        DownloadFailed(kind: _storageKind(error), receivedBytes: _received),
      );
    }
  }

  /// Last byte of a slice that starts at [start], inclusive. Never past the
  /// end of the file when its size is known.
  int _chunkEnd(int start, int chunk) {
    var end = start + chunk - 1;
    final total = _total ?? _request.expectedBytes;
    if (total != null && total > 0 && end > total - 1) end = total - 1;
    return end;
  }

  /// Re-runs the request without a range header after a 416.
  Future<void> _runFromScratch() async {
    final restart = _HttpDownloadTask(_client, _request.resumingFrom(0));
    restart._restarted = true;
    _delegate = restart;
    _subscription = null;
    _transfer = null;

    restart.progress.listen((sample) {
      if (!_progress.isClosed) _progress.add(sample);
    });

    // A stop that landed before the delegate existed still has to take effect.
    if (_stopMode == _StopMode.pause) await restart.pause();
    if (_stopMode == _StopMode.cancel) await restart.cancel();

    _complete(await restart.outcome);
  }

  /// Writes [response] to the target, then — for a host read a slice at a
  /// time — keeps asking for the next slice until the file is whole.
  ///
  /// [want] is how many bytes this first response should carry, or null when
  /// it carries the rest of the file. [next] is the slice size and the way of
  /// asking the host accepted, used for every slice after the first.
  Future<void> _pump(
    HttpClientResponse response, {
    required bool appending,
    required int? want,
    required (int, RequestProfile)? next,
  }) async {
    // A pause or cancel that arrived while the request was still in flight.
    if (_stopMode != null) {
      await response.drain<void>();
      await _completeStopped();
      return;
    }

    final sink = _request.target.openWrite(
      mode: appending ? FileMode.append : FileMode.write,
    );

    Object? result;
    try {
      result = await _pumpBody(response, sink, want: want);

      // The rest of the slices, one bounded request after another.
      if (result == null && next != null) {
        final (chunk, profile) = next;
        while (_stopMode == null) {
          final total = _total;
          if (total == null || _received >= total) break;

          final start = _received;
          final end = _chunkEnd(start, chunk);
          final slice = await _openSlice(profile, start, end);
          if (slice == null) {
            result = _SliceRefused();
            break;
          }
          result = await _pumpBody(slice, sink, want: end - start + 1);
          if (result != null) break;
        }
        if (_stopMode != null && result == null) result = _stopped;
      }
    } finally {
      await _subscription?.cancel();
      try {
        await sink.flush();
      } finally {
        await sink.close();
      }
    }

    if (identical(result, _stopped)) {
      if (_stopMode == _StopMode.cancel) {
        await _deletePartial();
        _complete(const DownloadCancelled());
      } else {
        _complete(DownloadPaused(receivedBytes: _received));
      }
      return;
    }

    if (result is _SliceRefused) {
      // The partial is kept: the address has most likely expired, and a fresh
      // one resumes from here.
      _complete(
        DownloadFailed(
          kind: DownloadErrorKind.server,
          receivedBytes: _received,
        ),
      );
      return;
    }

    if (result != null) {
      _complete(
        DownloadFailed(kind: _errorKind(result), receivedBytes: _received),
      );
      return;
    }

    final total = _total;
    if (total != null && _received < total) {
      // The connection closed early. The partial is kept so a retry can resume
      // rather than starting over.
      _complete(
        DownloadFailed(
          kind: DownloadErrorKind.corrupted,
          receivedBytes: _received,
        ),
      );
      return;
    }

    _complete(DownloadSucceeded(file: _request.target, totalBytes: _received));
  }

  /// Asks for one more slice the way the first one was accepted.
  ///
  /// Returns null when the host would not serve it, which the caller reports
  /// as a refusal; anything else that goes wrong is thrown and reported by
  /// its kind.
  Future<HttpClientResponse?> _openSlice(
    RequestProfile profile,
    int start,
    int end,
  ) async {
    final request = await _client.getUrl(_request.url);
    request.followRedirects = true;
    request.maxRedirects = 5;
    profile.headers.forEach(request.headers.set);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');

    final response = await request.close().timeout(NetworkTimeouts.connect);
    if (response.statusCode == HttpStatus.partialContent) return response;

    AppLog.warn(
      'Media range request refused',
      'HTTP ${response.statusCode} from ${_request.url.host} '
          'for bytes=$start-$end',
    );
    await RequestRace.discard(response);
    return null;
  }

  /// Copies one response body into [sink].
  ///
  /// Returns null when the body arrived whole, [_stopped] when the user
  /// stopped it, or the error that ended it. [want] is the byte count this
  /// response is expected to carry; a body that ends short of it is an error,
  /// a body that would overrun it is cut at it.
  Future<Object?> _pumpBody(
    HttpClientResponse response,
    IOSink sink, {
    required int? want,
  }) async {
    if (_stopMode != null) {
      await RequestRace.discard(response);
      return _stopped;
    }

    final transfer = Completer<Object?>();
    _transfer = transfer;
    var got = 0;

    // Stream.timeout fires when no chunk arrives for the stall window, which
    // catches a connection that goes quiet without closing.
    final subscription = response
        .timeout(NetworkTimeouts.transferStall)
        .listen(null);
    _subscription = subscription;

    subscription
      ..onData((chunk) {
        var bytes = chunk;
        if (want != null) {
          final room = want - got;
          if (room <= 0) return;
          if (bytes.length > room) bytes = bytes.sublist(0, room);
        }

        got += bytes.length;
        _received += bytes.length;
        _sinceFlush += bytes.length;
        sink.add(bytes);
        _emitProgress();

        if (want != null && got >= want) {
          if (!transfer.isCompleted) transfer.complete(null);
          return;
        }

        if (_sinceFlush >= _flushThreshold) {
          _sinceFlush = 0;
          subscription.pause(sink.flush());
        }
      })
      ..onError((Object error, StackTrace _) {
        if (!transfer.isCompleted) transfer.complete(error);
      })
      ..onDone(() {
        if (!transfer.isCompleted) transfer.complete(null);
      });

    final result = await transfer.future;
    await subscription.cancel();
    _subscription = null;
    _transfer = null;

    if (result != null) return result;
    if (want != null && got < want) {
      return const HttpException('The connection closed mid-slice.');
    }
    return null;
  }

  int? _resolveTotal(HttpClientResponse response, bool appending) {
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    if (range != null) {
      final slash = range.lastIndexOf('/');
      if (slash >= 0) {
        final total = int.tryParse(range.substring(slash + 1).trim());
        if (total != null && total > 0) return total;
      }
    }

    final length = response.contentLength;
    if (length > 0) return appending ? _request.startAt + length : length;
    return _request.expectedBytes;
  }

  void _emitProgress({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastEmitAt) < _emitInterval) return;
    _lastEmitAt = now;

    final elapsed = now.difference(_lastSampleAt).inMilliseconds;
    if (elapsed > 0) {
      final sample = (_received - _lastSampleBytes) * 1000 / elapsed;
      _speed = _speed == null
          ? sample
          : _speed! * (1 - _speedSmoothing) + sample * _speedSmoothing;
      _lastSampleAt = now;
      _lastSampleBytes = _received;
    }

    if (_progress.isClosed) return;
    _progress.add(
      DownloadProgress(
        receivedBytes: _received,
        totalBytes: _total,
        bytesPerSecond: _speed,
      ),
    );
  }

  Future<void> _deletePartial() async {
    try {
      if (_request.target.existsSync()) await _request.target.delete();
    } on FileSystemException {
      // A leftover partial in the cache directory is reclaimable by Android.
    }
  }

  DownloadErrorKind _errorKind(Object error) => switch (error) {
    TimeoutException() => DownloadErrorKind.timeout,
    SocketException() => DownloadErrorKind.network,
    HttpException() => DownloadErrorKind.network,
    FileSystemException() => _storageKind(error),
    _ => DownloadErrorKind.network,
  };

  static DownloadErrorKind _storageKind(FileSystemException error) {
    final message = '${error.osError?.message ?? ''} ${error.message}'
        .toLowerCase();
    return message.contains('no space') || message.contains('enospc')
        ? DownloadErrorKind.insufficientStorage
        : DownloadErrorKind.storage;
  }

  void _complete(DownloadOutcome result) {
    if (!_outcome.isCompleted) {
      _emitProgress(force: true);
      _outcome.complete(result);
    }
    if (!_progress.isClosed) unawaited(_progress.close());
  }
}

/// A slice after the first that the host would not serve.
class _SliceRefused {
  const _SliceRefused();
}
