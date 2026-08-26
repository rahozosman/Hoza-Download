import 'dart:async';
import 'dart:io';

import '../../../core/utils/app_log.dart';
import 'providers/page_fetcher.dart';

/// Turns the link the user shared into the one a provider can read.
///
/// Apps hand out short links (`vt.tiktok.com/ZS…`, `fb.watch/…`, `youtu.be/…`,
/// `instagram.com/share/…`) that only become a post address after a redirect.
/// Choosing a provider — and building Instagram's embed address — needs the
/// address the redirect lands on, so those are expanded first with a single
/// body-less request. Tracking parameters are dropped from the result so the
/// same post shared twice is the same key for the resolution cache.
abstract final class LinkCanonicalizer {
  /// Hosts that exist only to redirect somewhere else.
  static const Set<String> _shortHosts = {
    'vt.tiktok.com',
    'vm.tiktok.com',
    'fb.watch',
    'youtu.be',
    't.co',
    'bit.ly',
    'goo.gl',
    'l.instagram.com',
    'l.facebook.com',
    'lm.facebook.com',
  };

  /// Query parameters that identify the share, not the post.
  static final RegExp _tracking = RegExp(
    r'^(utm_\w+|igsh|igshid|fbclid|gclid|_r|_t|_d|sender_device|sender_web_id|'
    r'web_id|is_from_webapp|is_copy_url|checksum|sec_uid|share_app_id|'
    r'share_link_id|source|ref|rdid|mibextid|si|feature)$',
    caseSensitive: false,
  );

  static const Duration _timeout = Duration(seconds: 8);

  /// Whether [url] is one that has to be followed before it names a post.
  static bool needsExpanding(Uri url) {
    final host = url.host.toLowerCase();
    if (_shortHosts.contains(host)) return true;
    final path = url.path.toLowerCase();
    if (host.endsWith('tiktok.com') && path.startsWith('/t/')) return true;
    if (host.endsWith('instagram.com') && path.startsWith('/share/')) {
      return true;
    }
    return false;
  }

  /// [url] with its redirects followed and its tracking parameters removed.
  /// Never throws: a link that cannot be expanded is returned as it came,
  /// minus the tracking, and the providers make of it what they can.
  static Future<Uri> canonical(HttpClient client, Uri url) async {
    var resolved = _unwrapLinkShim(url) ?? url;
    if (needsExpanding(resolved)) {
      resolved = await _expand(client, resolved) ?? resolved;
    }
    return strip(resolved);
  }

  /// Meta's link shims carry the destination in a query parameter, so no
  /// request is needed to find out where they go.
  static Uri? _unwrapLinkShim(Uri url) {
    final host = url.host.toLowerCase();
    if (host != 'l.instagram.com' &&
        host != 'l.facebook.com' &&
        host != 'lm.facebook.com') {
      return null;
    }
    final target = Uri.tryParse(url.queryParameters['u'] ?? '');
    if (target == null || target.host.isEmpty) return null;
    final scheme = target.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https' ? target : null;
  }

  /// Follows the redirects with a ranged request whose body is never read.
  static Future<Uri?> _expand(HttpClient client, Uri url) async {
    try {
      final request = await client.getUrl(url).timeout(_timeout);
      request.followRedirects = true;
      request.maxRedirects = 8;
      request.headers
        ..set(HttpHeaders.userAgentHeader, BrowserProfile.userAgent)
        ..set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final response = await request.close().timeout(_timeout);

      var landed = url;
      for (final redirect in response.redirects) {
        landed = landed.resolveUri(redirect.location);
      }
      await response.listen(null, cancelOnError: true).cancel();

      // A short link that answered without redirecting is not one the
      // providers know how to read; say so by returning nothing.
      if (landed == url) return null;
      return landed.host.isEmpty ? null : landed;
    } on TimeoutException {
      AppLog.warn('Expanding a short link', 'timed out for ${url.host}');
      return null;
    } on IOException catch (error) {
      AppLog.warn('Expanding a short link', error.runtimeType);
      return null;
    }
  }

  /// [url] without the parameters that only say who shared it.
  static Uri strip(Uri url) {
    if (url.query.isEmpty) return url;
    final kept = <String, String>{};
    url.queryParameters.forEach((key, value) {
      if (!_tracking.hasMatch(key)) kept[key] = value;
    });
    if (kept.length == url.queryParameters.length) return url;
    if (kept.isNotEmpty) return url.replace(queryParameters: kept);
    // `replace` keeps an empty `?`; rebuild without the query instead.
    return Uri(
      scheme: url.scheme,
      userInfo: url.userInfo,
      host: url.host,
      port: url.hasPort ? url.port : null,
      path: url.path,
      fragment: url.hasFragment ? url.fragment : null,
    );
  }
}
