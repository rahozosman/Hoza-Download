import 'dart:io';

import '../../../../data/models/media_option.dart';
import '../../domain/source_provider.dart';
import '../request_profiles.dart';
import '../request_race.dart';

/// What a server said about a media URL, reduced to the few facts the app
/// needs.
///
/// Shared by every source provider so a link is inspected the same way no
/// matter which provider claimed it.
class MediaProbe {
  const MediaProbe({
    required this.statusCode,
    required this.contentType,
    required this.totalBytes,
    required this.supportsResume,
    this.headers = const <String, String>{},
  });

  factory MediaProbe.fromResponse(
    HttpClientResponse response, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final responseHeaders = response.headers;
    return MediaProbe(
      statusCode: response.statusCode,
      contentType: responseHeaders.value(HttpHeaders.contentTypeHeader),
      totalBytes: _totalBytes(response),
      supportsResume:
          (responseHeaders.value(HttpHeaders.acceptRangesHeader) ?? '')
              .toLowerCase()
              .contains('bytes') ||
          response.statusCode == HttpStatus.partialContent,
      headers: headers,
    );
  }

  final int statusCode;
  final String? contentType;
  final int? totalBytes;

  /// The request headers the server actually answered, so the download that
  /// follows can ask the same way instead of rediscovering it.
  final Map<String, String> headers;

  /// Whether the server advertised byte ranges, which is what makes pause and
  /// resume possible for this URL.
  final bool supportsResume;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// The one refusal this status justifies, or null when the response is
  /// usable. Shared so every provider refuses for the same reasons.
  UnsupportedSource? get refusal {
    switch (statusCode) {
      case HttpStatus.unauthorized:
      case HttpStatus.forbidden:
      case HttpStatus.paymentRequired:
        return const UnsupportedSource(UnsupportedReason.restricted);
      case HttpStatus.notFound:
      case HttpStatus.gone:
        return const UnsupportedSource(
          UnsupportedReason.noDownloadableVariant,
          detail: 'The file is no longer available at this address.',
        );
    }

    if (statusCode >= 500) {
      return const UnsupportedSource(UnsupportedReason.lookupFailed);
    }
    if (statusCode >= 400) {
      return const UnsupportedSource(UnsupportedReason.noDownloadableVariant);
    }
    return null;
  }

  /// Asks the server about a file without downloading it.
  ///
  /// A single byte is requested rather than a HEAD: every server answers a
  /// ranged GET, many reject HEAD outright, and the answer says in one round
  /// trip what the file is, how big it is and whether ranges — and so pause
  /// and resume — are available at all.
  ///
  /// The question is put several ways at once (see [RequestRace]) because a
  /// host that refuses one kind of client often serves another, and the way
  /// that worked is carried back in [headers] for the download to reuse.
  ///
  /// [expectMedia] tells the race that an HTML answer is a refusal rather than
  /// the file; leave it off when the address may legitimately be a page.
  static Future<MediaProbe> of(
    HttpClient client,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    bool expectMedia = false,
  }) async {
    final outcome = await RequestRace.open(
      client,
      url,
      profiles: RequestProfiles.forMedia(url, source: headers),
      range: 'bytes=0-0',
      expectMedia: expectMedia,
    );

    switch (outcome) {
      case RaceWon(:final response, :final profile):
        final probe = MediaProbe.fromResponse(
          response,
          headers: profile.headers,
        );
        await RequestRace.discard(response);
        return probe;

      case RaceRefused(:final statusCode):
        return MediaProbe(
          statusCode: statusCode,
          contentType: null,
          totalBytes: null,
          supportsResume: false,
        );

      // Never an answer, so never a verdict about the file: the caller's own
      // network handling decides what to tell the user.
      case RaceErrored(:final error):
        throw error;
    }
  }

  /// Reads the real size, preferring `Content-Range` because a ranged probe's
  /// `Content-Length` describes the single byte we asked for, not the file.
  static int? _totalBytes(HttpClientResponse response) {
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    if (range != null) {
      final slash = range.lastIndexOf('/');
      if (slash >= 0) {
        final total = int.tryParse(range.substring(slash + 1).trim());
        if (total != null && total > 0) return total;
      }
    }
    final length = response.contentLength;
    return length > 0 ? length : null;
  }
}

/// Translates what a URL or a server says into the containers Hoza can write.
abstract final class MediaFormats {
  /// File extensions Hoza can write, mapped to the container it writes.
  static const Map<String, MediaFormat> _byExtension = {
    'mp4': MediaFormat.mp4,
    'm4v': MediaFormat.mp4,
    'webm': MediaFormat.webm,
    'mp3': MediaFormat.mp3,
    'm4a': MediaFormat.m4a,
    'aac': MediaFormat.m4a,
    'jpg': MediaFormat.jpg,
    'jpeg': MediaFormat.jpg,
    'png': MediaFormat.png,
    'webp': MediaFormat.webp,
  };

  /// Content types that name a container directly. `application/octet-stream`
  /// is deliberately absent: it says nothing, so the URL has to name the file.
  static const Map<String, MediaFormat> _byMimeType = {
    'video/mp4': MediaFormat.mp4,
    'video/x-m4v': MediaFormat.mp4,
    'video/webm': MediaFormat.webm,
    'audio/mpeg': MediaFormat.mp3,
    'audio/mp3': MediaFormat.mp3,
    'audio/mp4': MediaFormat.m4a,
    'audio/x-m4a': MediaFormat.m4a,
    'audio/aac': MediaFormat.m4a,
    'audio/webm': MediaFormat.webm,
    'image/jpeg': MediaFormat.jpg,
    'image/jpg': MediaFormat.jpg,
    'image/pjpeg': MediaFormat.jpg,
    'image/png': MediaFormat.png,
    'image/webp': MediaFormat.webp,
  };

  /// Segmented streaming manifests. They play fine in a browser but are not a
  /// single saveable file, so Hoza says so rather than downloading a playlist.
  static const Set<String> _manifestExtensions = {'m3u8', 'mpd', 'f4m', 'ism'};

  /// Lower-case extension of the last path segment, or null when there is none.
  static String? extensionOf(Uri url) {
    final segments = url.pathSegments;
    if (segments.isEmpty) return null;
    final last = segments.last;
    final dot = last.lastIndexOf('.');
    if (dot <= 0 || dot == last.length - 1) return null;
    return last.substring(dot + 1).toLowerCase();
  }

  static MediaFormat? fromUrl(Uri url) => _byExtension[extensionOf(url)];

  static MediaFormat? fromContentType(String? contentType) {
    final type = _bareType(contentType);
    return type == null ? null : _byMimeType[type];
  }

  static bool isManifest(Uri url) =>
      _manifestExtensions.contains(extensionOf(url));

  /// Content types that may legitimately carry a media file. Some CDNs serve
  /// media as a generic binary stream, which is accepted only when the URL has
  /// already named a media extension.
  static bool isMediaContentType(String? contentType) {
    final type = _bareType(contentType);
    if (type == null) return true;
    return type.startsWith('video/') ||
        type.startsWith('audio/') ||
        type.startsWith('image/') ||
        type == 'application/octet-stream' ||
        type == 'binary/octet-stream';
  }

  static bool isHtmlContentType(String? contentType) {
    final type = _bareType(contentType);
    return type == null ||
        type == 'text/html' ||
        type == 'application/xhtml+xml' ||
        type == 'text/plain';
  }

  /// `video/mp4; charset=utf-8` -> `video/mp4`. Null when nothing was declared.
  static String? _bareType(String? contentType) {
    if (contentType == null || contentType.isEmpty) return null;
    final type = contentType.split(';').first.trim().toLowerCase();
    return type.isEmpty ? null : type;
  }
}
