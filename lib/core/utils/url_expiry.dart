/// Reads the expiry a media host signed into its URL.
///
/// TikTok, Meta, YouTube and S3-style CDNs all hand out addresses that stop
/// working after a few hours, and they all say when in the query string. A
/// download that knows this can ask for a fresh address *before* the old one
/// is refused, instead of failing first and recovering second.
abstract final class UrlExpiry {
  /// When [url] stops being served, or null when the URL does not say.
  static DateTime? of(Uri url) {
    final params = url.queryParameters;
    if (params.isEmpty) return null;

    for (final entry in params.entries) {
      final key = entry.key.toLowerCase();
      final value = entry.value;
      final DateTime? parsed = switch (key) {
        // TikTok, YouTube, S3 presigned, generic: seconds since the epoch.
        'x-expires' || 'expire' || 'expires' || 'exp' => _seconds(value),
        // Meta's CDNs: the same, written in hex.
        'oe' => _hexSeconds(value),
        _ => null,
      };
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Whether [url] has expired, or will within [margin]. A URL with no expiry
  /// is never treated as expired.
  static bool isExpired(
    Uri url, {
    Duration margin = const Duration(minutes: 1),
  }) {
    final expiry = of(url);
    if (expiry == null) return false;
    return expiry.isBefore(DateTime.now().add(margin));
  }

  static DateTime? _seconds(String value) {
    final seconds = int.tryParse(value);
    if (seconds == null) return null;
    return _plausible(seconds);
  }

  static DateTime? _hexSeconds(String value) {
    if (value.length < 6 || value.length > 10) return null;
    final seconds = int.tryParse(value, radix: 16);
    if (seconds == null) return null;
    return _plausible(seconds);
  }

  /// Only epoch seconds between 2015 and 2100 count; anything else is a
  /// parameter that happens to share the name.
  static DateTime? _plausible(int seconds) {
    if (seconds < 1420070400 || seconds > 4102444800) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
}
