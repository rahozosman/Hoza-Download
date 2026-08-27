import 'dart:io';

import '../../../data/models/media_option.dart';

/// Everything the engine needs to move one file.
class DownloadRequest {
  const DownloadRequest({
    required this.id,
    required this.url,
    required this.target,
    required this.mediaType,
    required this.format,
    this.expectedBytes,
    this.supportsResume = false,
    this.startAt = 0,
    this.headers = const <String, String>{},
    this.audioUrl,
    this.audioBytes,
    this.reencodeKbps,
  });

  /// Matches the record id, so progress can be routed back without a lookup.
  final String id;

  final Uri url;

  /// Partial file the bytes are appended to.
  final File target;

  final MediaType mediaType;
  final MediaFormat format;

  /// Size the source reported, when it reported one.
  final int? expectedBytes;

  /// Whether the server advertised byte ranges.
  final bool supportsResume;

  /// Bytes already on disk. Non-zero only when resuming.
  final int startAt;

  /// Headers the source requires on the byte request.
  final Map<String, String> headers;

  /// Audio track to merge into the download once both tracks are on disk.
  /// Null for an ordinary single-file transfer.
  final Uri? audioUrl;

  /// Size of [audioUrl], when the source reported one.
  final int? audioBytes;

  /// Bitrate, in kbps, the downloaded sound is re-encoded to once it is on
  /// disk. Null for a transfer that is saved exactly as it arrived.
  final int? reencodeKbps;

  DownloadRequest resumingFrom(int bytes) => DownloadRequest(
    id: id,
    url: url,
    target: target,
    mediaType: mediaType,
    format: format,
    expectedBytes: expectedBytes,
    supportsResume: supportsResume,
    startAt: bytes,
    headers: headers,
    audioUrl: audioUrl,
    audioBytes: audioBytes,
    reencodeKbps: reencodeKbps,
  );
}

/// A progress sample. Emitted at a fixed cadence, not per chunk, so the UI is
/// never asked to rebuild faster than it can paint.
class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    this.totalBytes,
    this.bytesPerSecond,
  });

  final int receivedBytes;
  final int? totalBytes;
  final double? bytesPerSecond;
}

/// Categories of download failure, each with a message a user can act on.
enum DownloadErrorKind {
  network,
  timeout,

  /// The host refused the address — usually an expired signature. Re-reading
  /// the source page is what fixes it.
  server,

  /// The host is up but asked for a pause (HTTP 429).
  rateLimited,

  /// The host itself is failing (HTTP 5xx); the address is still good.
  unavailable,

  /// The host says the file no longer exists (HTTP 404 / 410).
  gone,
  storage,
  insufficientStorage,
  corrupted,
  invalidLink,
  merge,

  /// The sound came down whole but could not be re-encoded to the bitrate the
  /// chosen format asks for.
  encode;

  String get message => switch (this) {
    DownloadErrorKind.network =>
      'Download failed — check your connection and try again.',
    DownloadErrorKind.timeout =>
      'The download stalled and was stopped. Try again.',
    DownloadErrorKind.server =>
      'The server refused the download. It may no longer be available.',
    DownloadErrorKind.rateLimited =>
      'The server asked for a pause. Hoza will retry shortly.',
    DownloadErrorKind.unavailable =>
      'The server is having trouble right now. Hoza will retry.',
    DownloadErrorKind.gone =>
      'The file was removed from its source and can no longer be downloaded.',
    DownloadErrorKind.storage => 'The file could not be saved to your device.',
    DownloadErrorKind.insufficientStorage =>
      'Not enough free space to finish this download.',
    DownloadErrorKind.corrupted =>
      'The download ended early and the file is incomplete.',
    DownloadErrorKind.invalidLink =>
      'This download link is no longer valid. Open the source again.',
    DownloadErrorKind.merge =>
      'The video and audio tracks could not be combined on this device.',
    DownloadErrorKind.encode =>
      'This device could not save the audio at that bitrate. Try a lower one.',
  };

  /// Whether trying the same download again could plausibly succeed.
  bool get isRetryable =>
      this == DownloadErrorKind.network ||
      this == DownloadErrorKind.timeout ||
      this == DownloadErrorKind.corrupted ||
      this == DownloadErrorKind.rateLimited ||
      this == DownloadErrorKind.unavailable;

  /// How long to wait before automatic retry number [attempt] (0-based), or
  /// null once this kind has had every retry it deserves.
  ///
  /// A rate limit is honoured with a real pause; a failing host gets a few
  /// spaced-out tries; a flaky connection gets two quick ones.
  Duration? retryDelay(int attempt) => switch (this) {
    DownloadErrorKind.rateLimited => switch (attempt) {
      0 => const Duration(seconds: 30),
      1 => const Duration(seconds: 90),
      _ => null,
    },
    DownloadErrorKind.unavailable => switch (attempt) {
      0 => const Duration(seconds: 5),
      1 => const Duration(seconds: 15),
      2 => const Duration(seconds: 45),
      _ => null,
    },
    DownloadErrorKind.network ||
    DownloadErrorKind.timeout ||
    DownloadErrorKind.corrupted => switch (attempt) {
      0 => const Duration(seconds: 3),
      1 => const Duration(seconds: 8),
      _ => null,
    },
    _ => null,
  };

  /// The error kind an HTTP status justifies for a media request.
  static DownloadErrorKind forStatus(int statusCode) => switch (statusCode) {
    429 => DownloadErrorKind.rateLimited,
    404 || 410 => DownloadErrorKind.gone,
    >= 500 => DownloadErrorKind.unavailable,
    _ => DownloadErrorKind.server,
  };
}

/// How a task ended. Exactly one of these is produced per run.
sealed class DownloadOutcome {
  const DownloadOutcome();
}

class DownloadSucceeded extends DownloadOutcome {
  const DownloadSucceeded({required this.file, required this.totalBytes});

  final File file;
  final int totalBytes;
}

/// Stopped by the user with the partial file kept for a later resume.
class DownloadPaused extends DownloadOutcome {
  const DownloadPaused({required this.receivedBytes});

  final int receivedBytes;
}

/// Stopped by the user with the partial file discarded.
class DownloadCancelled extends DownloadOutcome {
  const DownloadCancelled();
}

class DownloadFailed extends DownloadOutcome {
  const DownloadFailed({required this.kind, required this.receivedBytes});

  final DownloadErrorKind kind;
  final int receivedBytes;
}

/// A transfer in flight.
abstract interface class DownloadTask {
  /// Progress samples until the task ends. Closes when [outcome] completes.
  Stream<DownloadProgress> get progress;

  /// Completes once, with how the transfer ended. Never throws.
  Future<DownloadOutcome> get outcome;

  /// Stops and keeps the partial file.
  Future<void> pause();

  /// Stops and deletes the partial file.
  Future<void> cancel();
}

/// Starts transfers. The queue owns scheduling; the engine only moves bytes.
abstract interface class DownloadEngine {
  DownloadTask start(DownloadRequest request);
}
