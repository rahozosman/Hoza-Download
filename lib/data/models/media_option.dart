/// Whether a download produces a video file, an audio-only file, or a photo.
enum MediaType {
  video,
  audio,
  image;

  String get storageKey => name;

  static MediaType fromStorageKey(String? key) {
    return MediaType.values.firstWhere(
      (type) => type.name == key,
      orElse: () => MediaType.video,
    );
  }

  String get label => switch (this) {
    MediaType.video => 'Video',
    MediaType.audio => 'Audio',
    MediaType.image => 'Image',
  };

  /// Sub-folder inside `Download/Hoza Download/`.
  String get folderName => switch (this) {
    MediaType.video => 'Videos',
    MediaType.audio => 'Audio',
    MediaType.image => 'Images',
  };
}

/// Container/codec a download is written as.
///
/// Only formats a source actually offers are ever surfaced to the user; this
/// enum simply names the ones Hoza can write.
enum MediaFormat {
  mp4('MP4', 'mp4', 'video/mp4', MediaType.video),
  webm('WEBM', 'webm', 'video/webm', MediaType.video),
  mp3('MP3', 'mp3', 'audio/mpeg', MediaType.audio),
  m4a('M4A', 'm4a', 'audio/mp4', MediaType.audio),
  jpg('JPG', 'jpg', 'image/jpeg', MediaType.image),
  png('PNG', 'png', 'image/png', MediaType.image),
  webp('WEBP', 'webp', 'image/webp', MediaType.image);

  const MediaFormat(this.label, this.extension, this.mimeType, this.mediaType);

  final String label;
  final String extension;

  /// Declared to MediaStore so Android files the download under the right
  /// collection and hands it to the right player.
  final String mimeType;

  final MediaType mediaType;

  String get storageKey => name;

  static MediaFormat fromStorageKey(String? key) {
    return MediaFormat.values.firstWhere(
      (format) => format.name == key,
      orElse: () => MediaFormat.mp4,
    );
  }
}

/// One selectable variant returned by a source provider.
///
/// A provider only emits variants it can genuinely deliver, so the quality list
/// in the download sheet is never padded with options that would fail.
class MediaVariant {
  const MediaVariant({
    required this.id,
    required this.label,
    required this.format,
    required this.url,
    this.heightPx,
    this.bitrateKbps,
    this.estimatedBytes,
    this.supportsResume = false,
    this.headers = const <String, String>{},
    this.audioUrl,
    this.audioBytes,
  });

  /// Provider-scoped identifier for this variant.
  final String id;

  /// What the user sees on the chip: `1080p`, `MP3 320 kbps`, …
  final String label;

  final MediaFormat format;

  /// Where the bytes are fetched from. Always a validated http(s) link.
  final Uri url;

  /// Whether the server advertised byte-range support, which is what makes
  /// pause and resume possible for this variant.
  final bool supportsResume;

  /// Vertical resolution for video variants; null for audio.
  final int? heightPx;

  /// Audio bitrate for audio variants; null for video.
  final int? bitrateKbps;

  /// Size hint from the source. Null when the source does not report one — the
  /// UI then omits the size row rather than inventing a number.
  final int? estimatedBytes;

  /// Headers the source requires on the byte request. Some CDNs answer only
  /// when the `Referer` matches the page the media was published on, so the
  /// provider that read the page also states how to fetch it.
  final Map<String, String> headers;

  /// A separate audio track to merge into [url] once both are on disk.
  ///
  /// Sites that publish adaptive streams keep video and audio in different
  /// files; only the pair together is a watchable download. Null whenever
  /// [url] already carries its own audio.
  final Uri? audioUrl;

  /// Size of [audioUrl], when the source reported one.
  final int? audioBytes;

  bool get needsMuxing => audioUrl != null;

  /// What the finished file will weigh: both tracks when they are merged.
  int? get totalEstimatedBytes {
    final video = estimatedBytes;
    if (video == null) return null;
    if (audioUrl == null) return video;
    final audio = audioBytes;
    return audio == null ? null : video + audio;
  }

  MediaType get mediaType => format.mediaType;
}
