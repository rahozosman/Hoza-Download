import 'media_probe.dart';

/// What a page published about itself, reduced to what the download sheet
/// needs.
class ScrapedPage {
  const ScrapedPage({
    required this.candidates,
    required this.hasStreamingManifest,
    this.title,
    this.thumbnailUrl,
    this.heightPx,
    this.durationSeconds,
  });

  /// Absolute http(s) media URLs the page advertised, in the order they were
  /// published. Never a manifest and never the page itself.
  final List<Uri> candidates;

  /// Whether the only media the page named was a segmented stream. The sheet
  /// says so instead of showing a generic refusal.
  final bool hasStreamingManifest;

  final String? title;
  final String? thumbnailUrl;

  /// Vertical resolution the page declared for its video, when it declared one.
  final int? heightPx;

  final int? durationSeconds;
}

/// Reads the public metadata a page publishes about its own media.
///
/// Deliberately regex-based rather than a full HTML parse: the app only needs
/// a handful of well-known tags, and every value is treated as untrusted text
/// that still has to survive URL validation and a server probe before it is
/// used.
abstract final class PageMediaScraper {
  static ScrapedPage parse(
    String html,
    Uri pageUrl, {
    required int maxCandidates,
  }) {
    final meta = _metaTags(html);

    final published = <String>[
      ...?meta['og:video:secure_url'],
      ...?meta['og:video:url'],
      ...?meta['og:video'],
      ...?meta['twitter:player:stream'],
      ...?meta['og:audio:secure_url'],
      ...?meta['og:audio:url'],
      ...?meta['og:audio'],
      ..._elementSources(html),
      ..._linkedDataUrls(html),
    ];

    final candidates = <Uri>[];
    var hasStreamingManifest = false;

    for (final value in published) {
      final url = _absolute(value, pageUrl);
      if (url == null) continue;
      if (MediaFormats.isManifest(url)) {
        hasStreamingManifest = true;
        continue;
      }
      if (_isPageLike(url)) continue;
      if (candidates.contains(url)) continue;

      candidates.add(url);
      if (candidates.length >= maxCandidates) break;
    }

    return ScrapedPage(
      candidates: candidates,
      hasStreamingManifest: hasStreamingManifest,
      title: _title(html, meta),
      thumbnailUrl: _thumbnail(meta, pageUrl),
      heightPx: _positiveInt(_first(meta, const ['og:video:height'])),
      durationSeconds: _duration(html, meta),
    );
  }

  // ---- tag readers ---------------------------------------------------------

  static final RegExp _metaTag = RegExp(r'<meta\b[^>]*>', caseSensitive: false);

  static final RegExp _mediaElement = RegExp(
    r'<(?:video|audio|source)\b[^>]*>',
    caseSensitive: false,
  );

  static final RegExp _contentUrl = RegExp(
    r'"contentUrl"\s*:\s*"([^"]+)"',
    caseSensitive: false,
  );

  static final RegExp _titleElement = RegExp(
    r'<title\b[^>]*>([\s\S]{0,300}?)</title>',
    caseSensitive: false,
  );

  static final RegExp _isoDuration = RegExp(
    r'"duration"\s*:\s*"(P[^"]{1,40})"',
    caseSensitive: false,
  );

  static final RegExp _isoDurationParts = RegExp(
    r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
    caseSensitive: false,
  );

  /// Attribute patterns are built once per attribute name; the scraper only
  /// ever asks for a handful.
  static final Map<String, RegExp> _attributePatterns = {};

  /// Every `<meta>` keyed by its `property` or `name`, lower-cased. A key can
  /// legitimately repeat, so values are kept in publication order.
  static Map<String, List<String>> _metaTags(String html) {
    final tags = <String, List<String>>{};
    for (final match in _metaTag.allMatches(html)) {
      final tag = match.group(0)!;
      final key = (_attribute(tag, 'property') ?? _attribute(tag, 'name'))
          ?.trim()
          .toLowerCase();
      final content = _attribute(tag, 'content');
      if (key == null || key.isEmpty) continue;
      if (content == null || content.isEmpty) continue;
      tags.putIfAbsent(key, () => <String>[]).add(_unescape(content));
    }
    return tags;
  }

  static List<String> _elementSources(String html) {
    final sources = <String>[];
    for (final match in _mediaElement.allMatches(html)) {
      final tag = match.group(0)!;
      final src = _attribute(tag, 'src') ?? _attribute(tag, 'data-src');
      if (src != null && src.isNotEmpty) sources.add(_unescape(src));
    }
    return sources;
  }

  /// schema.org `VideoObject.contentUrl`, which sites embed as JSON-LD. The
  /// value is JSON, so escaped slashes are unescaped before it is parsed.
  static List<String> _linkedDataUrls(String html) {
    return _contentUrl
        .allMatches(html)
        .map((match) => _unescape(match.group(1)!.replaceAll(r'\/', '/')))
        .toList();
  }

  static String? _attribute(String tag, String name) {
    final pattern = _attributePatterns.putIfAbsent(
      name,
      () => RegExp(
        '(?<![-\\w:])$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s"\'>]+))',
        caseSensitive: false,
      ),
    );
    final match = pattern.firstMatch(tag);
    if (match == null) return null;
    return match.group(1) ?? match.group(2) ?? match.group(3);
  }

  static final RegExp _entity = RegExp(
    r'&(#x[0-9a-fA-F]{1,6}|#\d{1,7}|amp|lt|gt|quot|apos|nbsp);',
    caseSensitive: false,
  );

  /// Attribute values arrive HTML-escaped; a URL full of `&amp;` would 404.
  static String _unescape(String value) {
    if (!value.contains('&')) return value;
    return value.replaceAllMapped(_entity, (match) {
      final token = match.group(1)!;
      switch (token.toLowerCase()) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        case 'nbsp':
          return ' ';
      }
      final isHex = token.startsWith('#x') || token.startsWith('#X');
      final code = int.tryParse(
        token.substring(isHex ? 2 : 1),
        radix: isHex ? 16 : 10,
      );
      if (code == null || code <= 0 || code > 0x10FFFF) return match.group(0)!;
      return String.fromCharCode(code);
    });
  }

  // ---- value readers -------------------------------------------------------

  static String? _title(String html, Map<String, List<String>> meta) {
    final published = _first(meta, const [
      'og:title',
      'twitter:title',
      'title',
    ]);
    if (published != null && published.isNotEmpty) return published;

    final match = _titleElement.firstMatch(html);
    if (match == null) return null;
    final text = _unescape(match.group(1)!).trim();
    return text.isEmpty ? null : text;
  }

  static String? _thumbnail(Map<String, List<String>> meta, Uri pageUrl) {
    final published = _first(meta, const [
      'og:image:secure_url',
      'og:image',
      'twitter:image',
      'thumbnailurl',
    ]);
    if (published == null) return null;
    return _absolute(published, pageUrl)?.toString();
  }

  static int? _duration(String html, Map<String, List<String>> meta) {
    final seconds = _positiveInt(
      _first(meta, const ['og:video:duration', 'video:duration']),
    );
    if (seconds != null) return seconds;

    final match = _isoDuration.firstMatch(html);
    return match == null ? null : _isoSeconds(match.group(1)!);
  }

  /// `PT1H2M30S` -> 3750. Returns null for anything that is not a plain
  /// day/hour/minute/second duration.
  static int? _isoSeconds(String value) {
    final parts = _isoDurationParts.firstMatch(value.trim());
    if (parts == null) return null;
    final days = int.tryParse(parts.group(1) ?? '') ?? 0;
    final hours = int.tryParse(parts.group(2) ?? '') ?? 0;
    final minutes = int.tryParse(parts.group(3) ?? '') ?? 0;
    final seconds = double.tryParse(parts.group(4) ?? '') ?? 0;
    final total = days * 86400 + hours * 3600 + minutes * 60 + seconds.round();
    return total > 0 ? total : null;
  }

  static String? _first(Map<String, List<String>> meta, List<String> keys) {
    for (final key in keys) {
      final values = meta[key];
      if (values != null && values.isNotEmpty) return values.first;
    }
    return null;
  }

  static int? _positiveInt(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  // ---- URL handling --------------------------------------------------------

  /// Extensions that mark a link as another page rather than a file.
  static const Set<String> _pageExtensions = {
    'html',
    'htm',
    'php',
    'asp',
    'aspx',
    'jsp',
  };

  /// Resolves a published value against the page and keeps only http(s).
  /// Anything else — `blob:`, `data:`, a malformed value — is dropped.
  static Uri? _absolute(String value, Uri pageUrl) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 2048) return null;

    final parsed = Uri.tryParse(
      trimmed.startsWith('//') ? '${pageUrl.scheme}:$trimmed' : trimmed,
    );
    if (parsed == null) return null;

    final Uri resolved;
    try {
      resolved = parsed.hasScheme ? parsed : pageUrl.resolveUri(parsed);
    } on FormatException {
      return null;
    }

    final scheme = resolved.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (resolved.host.isEmpty) return null;
    return resolved;
  }

  /// An embed or player page is a page, not a file. Sites list one under
  /// `og:video` constantly, and probing it would only cost a round trip.
  static bool _isPageLike(Uri url) {
    final extension = MediaFormats.extensionOf(url);
    if (extension != null && _pageExtensions.contains(extension)) return true;
    final path = url.path.toLowerCase();
    return path.contains('/embed') || path.contains('/player');
  }
}
