import 'dart:convert';
import 'dart:io';

import '../../../../data/models/media_option.dart';
import '../../domain/source_provider.dart';
import 'media_probe.dart';

/// Request headers that make a site answer with the page a browser would get.
///
/// Several platforms serve a stripped placeholder — or nothing at all — to a
/// client that does not identify itself, and the media metadata this app reads
/// is only present in the full page.
abstract final class BrowserProfile {
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// The agent link previews are generated with. Meta's sites answer a plain
  /// browser agent with an error or a login shell, but serve the real page —
  /// Open Graph tags included — to the crawler that builds their own previews.
  static const String crawlerUserAgent =
      'facebookexternalhit/1.1 '
      '(+http://www.facebook.com/externalhit_uatext.php)';

  /// Headers for fetching a media file from a CDN that checks where the
  /// request came from.
  static Map<String, String> mediaHeaders({
    required String referer,
    String? userAgent,
  }) => {
    HttpHeaders.userAgentHeader: userAgent ?? BrowserProfile.userAgent,
    HttpHeaders.refererHeader: referer,
  };
}

/// One page, read once, with everything a provider needs to decide what to do.
class FetchedPage {
  const FetchedPage({
    required this.url,
    required this.probe,
    this.html,
    this.directFormat,
    this.refusal,
    this.cookies = const <Cookie>[],
  });

  /// Where the redirects actually landed. Relative URLs in [html] resolve
  /// against this, not against what the user pasted.
  final Uri url;

  final MediaProbe probe;

  /// Cookies the page set. Some platforms' media servers only hand over a
  /// file to the same session that read the page, so these have to travel
  /// with the media request.
  final List<Cookie> cookies;

  /// The `Cookie` header value that presents [cookies] back, or null when the
  /// page set none.
  String? get cookieHeader => cookies.isEmpty
      ? null
      : cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');

  /// Body text, present only when the response really was a page.
  final String? html;

  /// Set when the address turned out to be a media file rather than a page,
  /// even though its URL never named one.
  final MediaFormat? directFormat;

  /// Set when the response itself is a refusal — gone, forbidden, server down.
  final UnsupportedSource? refusal;
}

/// Fetches a page body once, with a cap, and closes the connection early when
/// the body is not something worth reading.
abstract final class PageFetcher {
  /// Metadata lives in the head, so this is generous; the cap exists so a huge
  /// page cannot stall the sheet or exhaust memory.
  static const int maxPageBytes = 512 * 1024;

  static Future<FetchedPage> fetch(
    HttpClient client,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    int maxBytes = maxPageBytes,
  }) async {
    final request = await client.getUrl(url);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers
      ..set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,video/*,audio/*;q=0.9,*/*;q=0.8',
      )
      ..set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9')
      // The shared client keeps compression off so download sizes stay honest.
      // A page body has to be readable text, so identity is asked for here and
      // a server that compresses anyway is decoded below.
      ..set(HttpHeaders.acceptEncodingHeader, 'identity');
    headers.forEach(request.headers.set);

    final response = await request.close();
    final resolved = _finalUrl(url, response);
    final probe = MediaProbe.fromResponse(response);
    final cookies = _cookiesOf(response);

    final refusal = probe.refusal;
    if (refusal != null) {
      await _abort(response);
      return FetchedPage(
        url: resolved,
        probe: probe,
        refusal: refusal,
        cookies: cookies,
      );
    }

    // A link with no file extension can still be the file itself; the server
    // has just said what it is, so there is no page to read.
    final direct = MediaFormats.fromContentType(probe.contentType);
    if (direct != null) {
      await _abort(response);
      return FetchedPage(
        url: resolved,
        probe: probe,
        directFormat: direct,
        cookies: cookies,
      );
    }

    if (!MediaFormats.isHtmlContentType(probe.contentType)) {
      await _abort(response);
      return FetchedPage(url: resolved, probe: probe, cookies: cookies);
    }

    return FetchedPage(
      url: resolved,
      probe: probe,
      html: await _readBody(response, maxBytes),
      cookies: cookies,
    );
  }

  /// The cookies a response set, read leniently: one malformed `Set-Cookie`
  /// must not cost the page.
  static List<Cookie> _cookiesOf(HttpClientResponse response) {
    try {
      return response.cookies;
    } on FormatException {
      final parsed = <Cookie>[];
      for (final raw in response.headers[HttpHeaders.setCookieHeader] ?? []) {
        try {
          parsed.add(Cookie.fromSetCookieValue(raw));
        } on FormatException {
          // Skip the one that does not parse.
        }
      }
      return parsed;
    }
  }

  static Uri _finalUrl(Uri requested, HttpClientResponse response) {
    var resolved = requested;
    for (final redirect in response.redirects) {
      resolved = resolved.resolveUri(redirect.location);
    }
    return resolved;
  }

  /// Reads at most [maxPageBytes] of the body, decompressing it when the
  /// server ignored the identity request.
  static Future<String> _readBody(
    HttpClientResponse response,
    int maxBytes,
  ) async {
    final buffer = <int>[];
    await for (final chunk in response) {
      buffer.addAll(chunk);
      if (buffer.length >= maxBytes) break;
    }

    final encoding =
        (response.headers.value(HttpHeaders.contentEncodingHeader) ?? '')
            .toLowerCase();
    var bytes = buffer;
    if (encoding.contains('gzip')) {
      try {
        bytes = gzip.decode(buffer);
      } on FormatException {
        // A truncated tail is expected once the cap is hit; parse what decoded.
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Closes a response without downloading its body.
  static Future<void> _abort(HttpClientResponse response) async {
    final subscription = response.listen(null, cancelOnError: true);
    await subscription.cancel();
  }
}
