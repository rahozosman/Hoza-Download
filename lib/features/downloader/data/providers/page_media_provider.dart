import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/media_option.dart';
import '../../domain/source_provider.dart';
import 'media_probe.dart';
import 'page_fetcher.dart';
import 'page_media_scraper.dart';

/// Handles ordinary web pages by downloading the media the page itself
/// publishes.
///
/// Sites that want their media to be shareable advertise it in public
/// metadata: Open Graph `og:video`, `twitter:player:stream`, schema.org
/// `contentUrl`, and plain `<video>`/`<source>` elements. This provider reads
/// exactly those and nothing else — no private endpoint, no signed URL, no
/// account. A page that publishes no downloadable file is reported as
/// unsupported instead of being worked around.
///
/// It claims every http(s) link, so it is registered last: whatever the
/// direct-file provider did not already recognise lands here.
class PageMediaProvider implements SourceProvider {
  const PageMediaProvider(this._client);

  final HttpClient _client;

  /// Upper bound on how many published URLs are checked. Pages occasionally
  /// list several renditions; anything beyond this is noise.
  static const int _maxCandidates = 4;

  @override
  String get name => 'Web page';

  @override
  bool canHandle(Uri url) {
    final scheme = url.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && url.host.isNotEmpty;
  }

  @override
  Future<SourceResolution> resolve(Uri url, {required Duration timeout}) async {
    // Refused by name, before the fetch: a platform that only ever serves its
    // media through its own player cannot be read by any compliant client, and
    // a vague "no downloadable version" would read like a bug in Hoza.
    final platform = playerOnlyPlatform(url);
    if (platform != null) {
      return UnsupportedSource(
        UnsupportedReason.restricted,
        detail:
            '$platform serves its videos through its own player and '
            'publishes no downloadable file. Hoza does not work around that.',
      );
    }

    try {
      return await _resolve(url).timeout(timeout);
    } on TimeoutException {
      return const UnsupportedSource(UnsupportedReason.lookupFailed);
    } on SocketException {
      return const UnsupportedSource(UnsupportedReason.lookupFailed);
    } on HandshakeException {
      return const UnsupportedSource(
        UnsupportedReason.lookupFailed,
        detail: 'The secure connection to this site could not be established.',
      );
    } on HttpException {
      return const UnsupportedSource(UnsupportedReason.lookupFailed);
    }
  }

  Future<SourceResolution> _resolve(Uri url) async {
    final page = await PageFetcher.fetch(
      _client,
      url,
      headers: {HttpHeaders.userAgentHeader: BrowserProfile.userAgent},
    );

    final refusal = page.refusal;
    if (refusal != null) return refusal;

    // A link with no file extension can still be the file itself.
    final direct = page.directFormat;
    if (direct != null) {
      return ResolvedMedia(_singleFile(page.url, direct, page.probe));
    }

    final html = page.html;
    if (html == null) {
      return const UnsupportedSource(
        UnsupportedReason.noDownloadableVariant,
        detail: 'This address does not return a video or audio file.',
      );
    }

    // Read on a worker isolate: a long page run through the scraper's
    // patterns must not hold the UI's frame.
    final pageUrl = page.url;
    final scraped = await Isolate.run(
      () =>
          PageMediaScraper.parse(html, pageUrl, maxCandidates: _maxCandidates),
    );
    return _fromPage(scraped, pageUrl);
  }

  Future<SourceResolution> _fromPage(ScrapedPage page, Uri pageUrl) async {
    final host = Formatters.hostOf(pageUrl.toString()) ?? pageUrl.host;

    if (page.candidates.isEmpty) {
      return UnsupportedSource(
        UnsupportedReason.noDownloadableVariant,
        detail: page.hasStreamingManifest
            ? '$host streams this in segments rather than publishing a single '
                  'file, so there is nothing to save.'
            : '$host publishes this for playback only and offers no '
                  'downloadable file.',
      );
    }

    final probes = await Future.wait(page.candidates.map(_probeQuietly));
    // A resolution is only attached when the page describes exactly one
    // rendition; with several, the page never says which height belongs to
    // which URL, so no quality is invented for the chip.
    final height = page.candidates.length == 1 ? page.heightPx : null;

    final variants = <MediaVariant>[];
    for (var index = 0; index < page.candidates.length; index++) {
      final probe = probes[index];
      if (probe == null || !probe.isSuccess) continue;

      final candidate = page.candidates[index];
      final format =
          MediaFormats.fromContentType(probe.contentType) ??
          MediaFormats.fromUrl(candidate);
      if (format == null) continue;

      final isVideo = format.mediaType == MediaType.video;
      variants.add(
        MediaVariant(
          id: 'page-$index',
          label: _labelFor(format, isVideo ? height : null, variants.length),
          format: format,
          url: candidate,
          heightPx: isVideo ? height : null,
          estimatedBytes: probe.totalBytes,
          supportsResume: probe.supportsResume,
        ),
      );
    }

    if (variants.isEmpty) {
      return UnsupportedSource(
        UnsupportedReason.noDownloadableVariant,
        detail:
            'The media $host links to could not be read as a downloadable '
            'file.',
      );
    }

    return ResolvedMedia(
      MediaMetadata(
        sourceUrl: pageUrl,
        source: host,
        title: page.title,
        thumbnailUrl: page.thumbnailUrl,
        durationSeconds: page.durationSeconds,
        variants: variants,
      ),
    );
  }

  MediaMetadata _singleFile(Uri url, MediaFormat format, MediaProbe probe) {
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty);
    return MediaMetadata(
      sourceUrl: url,
      source: Formatters.hostOf(url.toString()) ?? url.host,
      title: segments.isEmpty ? url.host : segments.last,
      variants: [
        MediaVariant(
          id: 'direct',
          label: 'Original',
          format: format,
          url: url,
          estimatedBytes: probe.totalBytes,
          supportsResume: probe.supportsResume,
        ),
      ],
    );
  }

  /// A candidate that cannot be checked is dropped rather than failing the
  /// whole lookup — the other candidates may still be downloadable.
  Future<MediaProbe?> _probeQuietly(Uri url) async {
    try {
      return await MediaProbe.of(_client, url);
    } on IOException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static String _labelFor(MediaFormat format, int? heightPx, int index) {
    if (heightPx != null) return '${heightPx}p';
    if (index == 0) return 'Original';
    return '${format.label} ${index + 1}';
  }
}

/// Subscription services whose media is protected end to end — the file only
/// ever reaches a viewer through the platform own player, under DRM.
///
/// Listing them is not a blocklist of sites Hoza dislikes: it is the set where
/// the only route to the file is defeating a protection, which Hoza does not
/// do. Naming the platform in the refusal is more honest than letting the
/// generic "nothing downloadable here" message imply the app is broken.
///
/// A platform that has its own provider never belongs here: that provider
/// claims the link first and gives the accurate answer for it.
const Map<String, String> _playerOnlyPlatforms = {
  'netflix.com': 'Netflix',
  'primevideo.com': 'Prime Video',
  'disneyplus.com': 'Disney+',
  'hulu.com': 'Hulu',
  'spotify.com': 'Spotify',
};

/// The platform name for [url], or null when no listed platform owns the host.
///
/// Walks the host from the left so every subdomain — `m.`, `music.`, `www.` —
/// resolves to the same platform.
String? playerOnlyPlatform(Uri url) {
  final parts = url.host.toLowerCase().split('.');
  for (var i = 0; i < parts.length - 1; i++) {
    final match = _playerOnlyPlatforms[parts.sublist(i).join('.')];
    if (match != null) return match;
  }
  return null;
}
