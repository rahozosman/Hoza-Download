import 'dart:io';

import '../../../core/constants/app_info.dart';
import 'providers/page_fetcher.dart';

/// One way of asking a server for a file.
///
/// Servers disagree about what a legitimate client looks like: a CDN with
/// hotlink protection wants the page the media was published on, another
/// refuses a request that claims an origin it did not expect, and a plain file
/// host is happiest with no browser dressing at all. A profile is one of those
/// opinions, written down.
class RequestProfile {
  const RequestProfile({required this.label, required this.headers});

  /// Short name used in logs; never shown to the user.
  final String label;

  final Map<String, String> headers;

  /// Two profiles that would send exactly the same request are one profile.
  String get signature {
    final entries =
        headers.entries.map((e) => '${e.key.toLowerCase()}=${e.value}').toList()
          ..sort();
    return entries.join('|');
  }
}

/// The ways Hoza knows to ask for a media file.
abstract final class RequestProfiles {
  /// What a browser sends when a `<video>` element fetches a file.
  static const String _mediaAccept =
      'video/webm,video/ogg,video/*;q=0.9,application/ogg;q=0.7,'
      'audio/*;q=0.6,*/*;q=0.5';

  static const String _language = 'en-US,en;q=0.9';

  static String get _appAgent =>
      '${AppInfo.name.replaceAll(' ', '')}/${AppInfo.version}';

  /// Every way to ask for [url], most likely to be accepted first.
  ///
  /// [source] is what the provider that found the link says is required — a
  /// `Referer` it read off the page, for instance. It leads, because a source
  /// that states its terms is usually right about them.
  ///
  /// Nothing here defeats a protection: these are the ordinary headers any
  /// browser or download manager sends. A server that wants a login still gets
  /// to say no, and Hoza reports that rather than trying to get around it.
  static List<RequestProfile> forMedia(
    Uri url, {
    Map<String, String> source = const <String, String>{},
  }) {
    final origin = url.hasAuthority ? '${url.scheme}://${url.host}' : null;

    return _deduped([
      if (source.isNotEmpty)
        RequestProfile(
          label: 'source',
          headers: {
            HttpHeaders.userAgentHeader: BrowserProfile.userAgent,
            HttpHeaders.acceptHeader: _mediaAccept,
            ...source,
          },
        ),
      if (origin != null)
        RequestProfile(
          label: 'mobile',
          headers: {
            HttpHeaders.userAgentHeader: BrowserProfile.userAgent,
            HttpHeaders.acceptHeader: _mediaAccept,
            HttpHeaders.acceptLanguageHeader: _language,
            HttpHeaders.refererHeader: '$origin/',
            'Origin': origin,
          },
        ),
      // No referer at all: some hosts refuse a referer they did not issue,
      // where they would have served an anonymous request.
      RequestProfile(
        label: 'desktop',
        headers: {
          HttpHeaders.userAgentHeader: BrowserProfile.desktopUserAgent,
          HttpHeaders.acceptHeader: _mediaAccept,
          HttpHeaders.acceptLanguageHeader: _language,
        },
      ),
      // The honest one. Plenty of file hosts prefer it, and it is what Hoza
      // sends when nothing else is needed.
      RequestProfile(
        label: 'plain',
        headers: {
          HttpHeaders.userAgentHeader: _appAgent,
          HttpHeaders.acceptHeader: '*/*',
        },
      ),
    ]);
  }

  static List<RequestProfile> _deduped(List<RequestProfile> profiles) {
    final seen = <String>{};
    return [
      for (final profile in profiles)
        if (seen.add(profile.signature)) profile,
    ];
  }
}
