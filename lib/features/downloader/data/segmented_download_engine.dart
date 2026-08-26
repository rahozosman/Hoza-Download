import 'dart:async';
import 'dart:io';

import '../../../core/utils/app_log.dart';
import '../../../services/networking/http_client_provider.dart';
import '../domain/download_engine.dart';
import 'request_profiles.dart';
import 'request_race.dart';
import 'transfer_policy.dart';

/// Pulls one file down several connections at once.
///
/// A media host rarely gives a single connection everything the phone's link
/// can carry — the shaping is per-connection, not per-client — so one stream
/// leaves most of the available bandwidth unused. Asking for four slices of
/// the same file at the same time fills it, which is the difference between a
/// download that tracks the connection and one that crawls at a fixed rate no
/// matter how good the Wi-Fi is.
///
/// This is not a way around anything: every slice is an ordinary `Range`
/// request, the same one a video player makes when someone scrubs, and a
/// server that does not serve ranges is handed straight back to the
/// single-stream engine.
class SegmentedDownloadEngine implements DownloadEngine {
  const SegmentedDownloadEngine(this._client, this._inner);

  final HttpClient _client;

  /// The plain one-connection engine. Anything that cannot be split — and
  /// anything that turns out not to be splittable once the server answers —
  /// runs on it instead.
  final DownloadEngine _inner;

  /// Below this a second connection costs more in setup than it saves.
  static const int _minimumBytes = 8 * 1024 * 1024;

  /// Bytes each connection should have to itself, so a short file does not
  /// open four connections to move a few hundred kilobytes each.
  static const int _bytesPerConnection = 6 * 1024 * 1024;

  /// Most connections one file may use. Four saturates a phone's link without
  /// reading as hammering the host, and keeps the reassembly cheap.
  static const int _maxSegments = 4;

  @override
  DownloadTask start(DownloadRequest request) {
    final total = request.expectedBytes;
    if (!_canSegment(request, total)) return _inner.start(request);
    return _SegmentedTask(_client, _inner, request, _segmentCount(total!));
  }

  static bool _canSegment(DownloadRequest request, int? total) {
    // Ranges are what makes this possible at all, and a size is what makes it
    // plannable: without both, there is nothing to slice.
    if (!request.supportsResume) return false;
    if (total == null || total < _minimumBytes) return false;

    // A run that already wrote into the file itself keeps the single-stream
    // path — its bytes are in the target, not in slices, and appending slices
    // onto them would produce a file that does not play. A resumed segmented
    // run is not this case: its target is still the empty file that was
    // reserved for it, and its bytes are in the slices beside it.
    return request.startAt == 0 && !_hasBytes(request.target);
  }

  static int _segmentCount(int total) {
    final wanted = total ~/ _bytesPerConnection;
    if (wanted < 2) return 2;
    return wanted > _maxSegments ? _maxSegments : wanted;
  }

  /// The part file one segment of [target] is written to.
  static File segmentFile(File target, int index) =>
      File('${target.path}.s$index');

  /// Removes every slice belonging to [target].
  ///
  /// Callers that discard a partial download have to discard its slices too,
  /// or a cancelled transfer would leave them behind in the cache directory.
  static Future<void> discardSegments(File target) async {
    for (var index = 0; index < _maxSegments; index++) {
      final part = segmentFile(target, index);
      try {
        if (part.existsSync()) await part.delete();
      } on FileSystemException {
        // A leftover slice in the cache directory is reclaimable by Android.
      }
    }
  }

  static bool _hasBytes(File file) {
    try {
      return file.existsSync() && file.lengthSync() > 0;
    } on FileSystemException {
      return false;
    }
  }
}

enum _StopMode { pause, cancel }

class _SegmentedTask implements DownloadTask {
  _SegmentedTask(this._client, this._inner, this._request, this._count) {
    unawaited(_run());
  }

  final HttpClient _client;
  final DownloadEngine _inner;
  final DownloadRequest _request;

  /// How many slices this file is split into. Fixed for the whole run, and
  /// derived from the size, so a resumed run plans exactly the same slices.
  final int _count;

  final List<_Segment> _segments = <_Segment>[];

  final StreamController<DownloadProgress> _progress =
      StreamController<DownloadProgress>.broadcast();
  final Completer<DownloadOutcome> _outcome = Completer<DownloadOutcome>();

  /// Set when the run turned out not to be splittable and the single-stream
  /// engine took over; user actions are forwarded to whichever is moving bytes.
  DownloadTask? _delegate;

  int _received = 0;
  int? _total;
  _StopMode? _stopMode;

  // Progress pacing and speed smoothing, matched to the single-stream engine
  // so a download does not report differently depending on how it is fetched.
  DateTime _lastEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSampleAt = DateTime.now();
  int _lastSampleBytes = 0;
  double? _speed;

  static const Duration _emitInterval = Duration(milliseconds: 300);
  static const int _flushThreshold = 1024 * 1024;
  static const double _speedSmoothing = 0.35;

  /// Marks a transfer the user stopped, so a cancelled subscription is told
  /// apart from a connection that ended on its own.
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

    for (final segment in _segments) {
      await segment.subscription?.cancel();
      segment.subscription = null;

      final transfer = segment.transfer;
      if (transfer != null && !transfer.isCompleted) {
        transfer.complete(_stopped);
      }
    }
  }

  Future<void> _run() async {
    try {
      final total = _request.expectedBytes!;
      _total = total;
      _plan(total);
      _emitProgress(force: true);

      if (_stopMode != null) {
        await _completeStopped();
        return;
      }

      final lead = _firstUnfinished();
      if (lead == null) {
        // Every slice was already whole from an earlier run.
        await _assemble();
        return;
      }

      // A host that only serves bounded ranges gets each slice a piece at a
      // time; any other host gets each slice in one request.
      final chunk = TransferPolicy.maxRequestBytes(_request.url);
      final leadWant = lead.nextRequestBytes(chunk);

      // The first slice is asked for several ways at once, exactly as a
      // single-stream download is: whichever shape the host accepts is then
      // the shape the other slices use, so the race is paid for once.
      final outcome = await RequestRace.open(
        _client,
        _request.url,
        profiles: RequestProfiles.forMedia(
          _request.url,
          source: _request.headers,
        ),
        range: lead.rangeFor(leadWant),
      );

      switch (outcome) {
        case RaceWon(:final response, :final profile):
          if (response.statusCode != HttpStatus.partialContent ||
              _totalOf(response) != total) {
            // The host answered with the whole file, or with a different file
            // than the one that was measured. Slicing is off the table.
            await RequestRace.discard(response);
            await SegmentedDownloadEngine.discardSegments(_request.target);
            await _delegateToInner();
            return;
          }
          await _transfer(lead, response, leadWant, profile, total, chunk);

        case RaceRefused(:final statusCode):
          if (statusCode == HttpStatus.requestedRangeNotSatisfiable) {
            // The slices on disk no longer match the file on the host. Start
            // over on the plain path rather than stitching stale bytes.
            await SegmentedDownloadEngine.discardSegments(_request.target);
            await _delegateToInner();
            return;
          }
          AppLog.warn(
            'Media request refused',
            'HTTP $statusCode from ${_request.url.host} for '
                '${lead.rangeFor(leadWant)}',
          );
          _complete(
            DownloadFailed(
              kind: DownloadErrorKind.forStatus(statusCode),
              receivedBytes: _received,
            ),
          );

        case RaceErrored(:final error):
          _complete(
            DownloadFailed(kind: _errorKind(error), receivedBytes: _received),
          );
      }
    } on FileSystemException catch (error) {
      _complete(
        DownloadFailed(kind: _storageKind(error), receivedBytes: _received),
      );
    }
  }

  /// Lays out the slices and reads back what an earlier run already wrote.
  void _plan(int total) {
    final base = total ~/ _count;
    _segments
      ..clear()
      ..addAll([
        for (var index = 0; index < _count; index++)
          _Segment(
            start: base * index,
            // The last slice carries the remainder, so the plan always covers
            // the file exactly.
            end: index == _count - 1 ? total - 1 : base * (index + 1) - 1,
            part: SegmentedDownloadEngine.segmentFile(_request.target, index),
          ),
      ]);

    // A slice longer than the plan allows belongs to a different plan — a
    // different size, from a different resolve. Stitching those together would
    // produce a file that does not play, so the whole set goes.
    var stale = false;
    for (final segment in _segments) {
      final onDisk = _lengthOf(segment.part);
      if (onDisk > segment.length) {
        stale = true;
        break;
      }
      segment.received = onDisk;
    }

    if (stale) {
      for (final segment in _segments) {
        _deleteSync(segment.part);
        segment.received = 0;
      }
    }

    _received = _segments.fold(0, (sum, segment) => sum + segment.received);
    _lastSampleBytes = _received;
  }

  _Segment? _firstUnfinished() {
    for (final segment in _segments) {
      if (segment.remaining > 0) return segment;
    }
    return null;
  }

  /// Runs every slice at once and decides how the whole transfer ended.
  Future<void> _transfer(
    _Segment lead,
    HttpClientResponse leadResponse,
    int leadWant,
    RequestProfile profile,
    int total,
    int? chunk,
  ) async {
    final runs = <Future<Object?>>[
      _drive(lead, leadResponse, leadWant, profile, chunk),
      for (final segment in _segments)
        if (!identical(segment, lead) && segment.remaining > 0)
          _fetch(segment, profile, chunk),
    ];

    final failures = await Future.wait(runs);

    if (_stopMode != null) {
      await _completeStopped();
      return;
    }

    for (final failure in failures) {
      if (failure != null) {
        _complete(
          DownloadFailed(kind: _errorKind(failure), receivedBytes: _received),
        );
        return;
      }
    }

    if (_received < total) {
      // The slices are kept so a retry resumes rather than starting over.
      _complete(
        DownloadFailed(
          kind: DownloadErrorKind.corrupted,
          receivedBytes: _received,
        ),
      );
      return;
    }

    await _assemble();
  }

  /// Finishes the lead slice: the response the race won first, then whatever
  /// the slice still needs, asked for the way that response was.
  Future<Object?> _drive(
    _Segment lead,
    HttpClientResponse leadResponse,
    int leadWant,
    RequestProfile profile,
    int? chunk,
  ) async {
    final failure = await _pump(lead, leadResponse, want: leadWant);
    if (failure != null) return failure;
    return _fetch(lead, profile, chunk);
  }

  /// Pulls one slice down the way the lead slice was accepted, a request at a
  /// time until it is whole. Never throws: the error is returned so the other
  /// slices can finish first.
  Future<Object?> _fetch(
    _Segment segment,
    RequestProfile profile,
    int? chunk,
  ) async {
    try {
      while (_stopMode == null && segment.remaining > 0) {
        final want = segment.nextRequestBytes(chunk);
        final range = segment.rangeFor(want);

        final request = await _client.getUrl(_request.url);
        request.followRedirects = true;
        request.maxRedirects = 5;
        profile.headers.forEach(request.headers.set);
        request.headers.set(HttpHeaders.rangeHeader, range);

        final response = await request.close().timeout(NetworkTimeouts.connect);
        if (response.statusCode != HttpStatus.partialContent) {
          AppLog.warn(
            'Media range request refused',
            'HTTP ${response.statusCode} from ${_request.url.host} for $range',
          );
          await RequestRace.discard(response);
          return const HttpException('The server stopped serving byte ranges.');
        }

        final failure = await _pump(segment, response, want: want);
        if (failure != null) return failure;
      }
      return null;
    } catch (error) {
      return error;
    }
  }

  /// Writes one response into a slice's part file. [want] is how many bytes
  /// the response should carry. Returns the error that ended it, or null when
  /// the bytes arrived or the user stopped the download.
  Future<Object?> _pump(
    _Segment segment,
    HttpClientResponse response, {
    required int want,
  }) async {
    if (_stopMode != null) {
      await RequestRace.discard(response);
      return null;
    }

    final sink = segment.part.openWrite(mode: FileMode.append);
    final transfer = Completer<Object?>();
    segment.transfer = transfer;
    var sinceFlush = 0;
    var got = 0;

    // Stream.timeout fires when no chunk arrives for the stall window, which
    // catches a connection that goes quiet without closing.
    final subscription = response
        .timeout(NetworkTimeouts.transferStall)
        .listen(null);
    segment.subscription = subscription;

    subscription
      ..onData((chunk) {
        // A host that overruns the range it was given must not overrun the
        // slice: the extra bytes belong to the next request, or to the next
        // slice's part file.
        final room = want - got;
        if (room <= 0) return;
        final bytes = chunk.length <= room ? chunk : chunk.sublist(0, room);

        got += bytes.length;
        segment.received += bytes.length;
        _received += bytes.length;
        sinceFlush += bytes.length;
        sink.add(bytes);
        _emitProgress();

        if (got >= want) {
          if (!transfer.isCompleted) transfer.complete(null);
          return;
        }

        if (sinceFlush >= _flushThreshold) {
          sinceFlush = 0;
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
    segment.subscription = null;
    segment.transfer = null;
    try {
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (identical(result, _stopped) || _stopMode != null) return null;
    if (result != null) return result;
    if (got < want) {
      return const HttpException('The connection closed mid-file.');
    }
    return null;
  }

  /// Joins the slices into the file the caller asked for, in order.
  Future<void> _assemble() async {
    final sink = _request.target.openWrite(mode: FileMode.write);
    try {
      for (final segment in _segments) {
        await sink.addStream(segment.part.openRead());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    await SegmentedDownloadEngine.discardSegments(_request.target);
    _complete(
      DownloadSucceeded(
        file: _request.target,
        totalBytes: _lengthOf(_request.target),
      ),
    );
  }

  /// Hands the download to the single-stream engine and forwards everything
  /// the rest of the app is listening to, so the switch is invisible.
  Future<void> _delegateToInner() async {
    final task = _inner.start(_request.resumingFrom(0));
    _delegate = task;

    task.progress.listen((sample) {
      if (!_progress.isClosed) _progress.add(sample);
    });

    // A stop that landed before the delegate existed still has to take effect.
    if (_stopMode == _StopMode.pause) await task.pause();
    if (_stopMode == _StopMode.cancel) await task.cancel();

    _complete(await task.outcome);
  }

  Future<void> _completeStopped() async {
    if (_stopMode == _StopMode.cancel) {
      await SegmentedDownloadEngine.discardSegments(_request.target);
      _deleteSync(_request.target);
      _complete(const DownloadCancelled());
      return;
    }
    // The slices stay on disk: they are what a resumed run picks up from.
    _complete(DownloadPaused(receivedBytes: _received));
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

  void _complete(DownloadOutcome result) {
    if (!_outcome.isCompleted) {
      // The delegate has already reported its own final sample; repeating a
      // segment total over the top of it would make the bar jump backwards.
      if (_delegate == null) _emitProgress(force: true);
      _outcome.complete(result);
    }
    if (!_progress.isClosed) unawaited(_progress.close());
  }

  /// The size a `Content-Range` names for the whole file, or null.
  static int? _totalOf(HttpClientResponse response) {
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    if (range == null) return null;
    final slash = range.lastIndexOf('/');
    if (slash < 0) return null;
    return int.tryParse(range.substring(slash + 1).trim());
  }

  static int _lengthOf(File file) {
    try {
      return file.existsSync() ? file.lengthSync() : 0;
    } on FileSystemException {
      return 0;
    }
  }

  static void _deleteSync(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // A leftover partial in the cache directory is reclaimable by Android.
    }
  }

  static DownloadErrorKind _errorKind(Object error) => switch (error) {
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
}

/// One slice of the file, and the part it is written to.
class _Segment {
  _Segment({required this.start, required this.end, required this.part});

  /// Absolute offset of this slice's first byte.
  final int start;

  /// Absolute offset of its last byte, inclusive — the form `Range` uses.
  final int end;

  final File part;

  /// Bytes of this slice already on disk.
  int received = 0;

  StreamSubscription<List<int>>? subscription;

  /// Completes when this slice stops, however it stops.
  Completer<Object?>? transfer;

  int get length => end - start + 1;

  int get remaining => length - received;

  /// How much the next request for this slice asks for: the rest of it, or
  /// at most [chunk] of it on a host that only serves bounded ranges.
  int nextRequestBytes(int? chunk) =>
      chunk == null || chunk >= remaining ? remaining : chunk;

  /// The next [bytes] of this slice, which after a pause start where the
  /// last request stopped.
  String rangeFor(int bytes) {
    final from = start + received;
    return 'bytes=$from-${from + bytes - 1}';
  }
}
