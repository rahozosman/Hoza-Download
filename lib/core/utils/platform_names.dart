/// The short name Hoza uses for a platform — in the remote config, in
/// telemetry, and in the extractor catalog. Never the URL itself.
abstract final class PlatformNames {
  static const String tiktok = 'tiktok';
  static const String instagram = 'instagram';
  static const String facebook = 'facebook';
  static const String youtube = 'youtube';
  static const String other = 'other';

  static const Map<String, String> _byDomain = {
    'tiktok.com': tiktok,
    'instagram.com': instagram,
    'instagr.am': instagram,
    'facebook.com': facebook,
    'fb.watch': facebook,
    'fb.com': facebook,
    'youtube.com': youtube,
    'youtu.be': youtube,
  };

  /// The platform [url] belongs to, or [other].
  static String of(Uri url) {
    final parts = url.host.toLowerCase().split('.');
    for (var index = 0; index < parts.length - 1; index++) {
      final domain = parts.sublist(index).join('.');
      final name = _byDomain[domain];
      if (name != null) return name;
    }
    return other;
  }
}
