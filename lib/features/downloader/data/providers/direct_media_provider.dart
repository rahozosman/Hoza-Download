import 'dart:async';
import 'dart:io';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/media_option.dart';
import '../../domain/source_provider.dart';
import 'media_probe.dart';

/// Handles links that point straight at a media file the server publishes.
///
/// This is the compliant baseline provider: it asks the server what it is
/// serving and downloads exactly that. It performs no extraction, defeats no
/// protection, and claims a link only when the URL itself names a media file.
class DirectMediaProvider implements SourceProvider {
  const DirectMediaProvider(this._client);

  final HttpClient _client;

  @override
  String get name => 'Direct link';

  @override
  bool canHandle(Uri url) => MediaFormats.fromUrl(url) != null;

  @override
  Future<SourceResolution> resolve(Uri url, {required Duration timeout}) async {
    final format = MediaFormats.fromUrl(url);
    if (format == null) {
      return const UnsupportedSource(UnsupportedReason.noProvider);
    }

    try {
      final probe = await MediaProbe.of(
        _client,
        url,
        expectMedia: true,
      ).timeout(timeout);
      return _fold(probe, url, format);
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

  SourceResolution _fold(MediaProbe probe, Uri url, MediaFormat format) {
    final refusal = probe.refusal;
    if (refusal != null) return refusal;

    if (!MediaFormats.isMediaContentType(probe.contentType)) {
      return const UnsupportedSource(
        UnsupportedReason.noDownloadableVariant,
        detail: 'This address returns a web page, not a media file.',
      );
    }

    // pathSegments are already percent-decoded; decoding again would corrupt a
    // name that legitimately contains '%'.
    final fileName = url.pathSegments.last;
    return ResolvedMedia(
      MediaMetadata(
        sourceUrl: url,
        source: Formatters.hostOf(url.toString()) ?? url.host,
        title: fileName,
        variants: [
          MediaVariant(
            id: 'direct',
            // The server publishes one rendition and does not describe its
            // resolution, so no quality is invented for the chip.
            label: 'Original',
            format: format,
            url: url,
            estimatedBytes: probe.totalBytes,
            supportsResume: probe.supportsResume,
            // The way of asking that this server answered, so the download
            // starts from a request it has already accepted.
            headers: probe.headers,
          ),
        ],
      ),
    );
  }
}
