/// Turns what a site said about a post into a name that tells one download
/// from the next.
///
/// Social platforms publish the *site's* title on every post page — TikTok's
/// is "TikTok - Make Your Day", Facebook's login wall is "Facebook" — so a
/// downloader that trusts the page title saves every video under the same
/// name. Nothing here is trusted as a title unless it says something about
/// the post itself; anything else falls back to the post's own ID, which is
/// different for every video by construction.
abstract final class MediaTitles {
  /// Site-wide titles platforms put on every page. Compared case-insensitively
  /// after trimming, so "TikTok - Make Your Day" and "tiktok – make your day"
  /// both count.
  static final List<RegExp> _generic = [
    RegExp(r'^tiktok(\s*[-–—|:]\s*make\s+your\s+day)?$', caseSensitive: false),
    RegExp(r'^make\s+your\s+day$', caseSensitive: false),
    // "Name on TikTok" is the account's page title, shared by every post.
    RegExp(r'^.+\s+on\s+(tiktok|instagram|facebook)$', caseSensitive: false),
    RegExp(r'^instagram$', caseSensitive: false),
    RegExp(r'^facebook(\s*[-–—|:].*)?$', caseSensitive: false),
    RegExp(r'^log\s*in\b.*', caseSensitive: false),
    RegExp(r'^sign\s*up\b.*', caseSensitive: false),
    RegExp(r'^(video|reel|reels|watch|post|untitled)$', caseSensitive: false),
    RegExp(r'^error$', caseSensitive: false),
    RegExp(r'^(page\s+not\s+found|not\s+found|404)$', caseSensitive: false),
  ];

  /// Whether [title] names the site rather than the post.
  static bool isGeneric(String? title) {
    if (title == null) return true;
    final text = title.trim();
    if (text.isEmpty) return true;
    return _generic.any((pattern) => pattern.hasMatch(text));
  }

  /// [title] if it describes the post, otherwise null.
  static String? specific(String? title) =>
      isGeneric(title) ? null : title!.trim();

  /// Path segments that introduce a post ID on the supported platforms:
  /// `/@user/video/123`, `/reel/ABC/`, `/p/ABC/`, `/videos/123`.
  static const Set<String> _idMarkers = {
    'video',
    'videos',
    'reel',
    'reels',
    'p',
    'photo',
    'shorts',
  };

  static final RegExp _idShape = RegExp(r'^[A-Za-z0-9_-]{4,40}$');

  /// The identifier the platform gave this post, read from its URL, or null
  /// when the link carries nothing that looks like one.
  static String? postIdOf(Uri url) {
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();

    for (var index = 0; index < segments.length - 1; index++) {
      if (_idMarkers.contains(segments[index].toLowerCase())) {
        final candidate = segments[index + 1];
        if (_idShape.hasMatch(candidate)) return candidate;
      }
    }

    // Facebook's watch pages: /watch/?v=123.
    final query = url.queryParameters['v'];
    if (query != null && _idShape.hasMatch(query)) return query;

    if (segments.isNotEmpty) {
      final last = segments.last;
      // A trailing numeric ID (TikTok, Facebook) or an opaque slug
      // (Instagram short codes are 11 characters).
      if (RegExp(r'^\d{6,}$').hasMatch(last) ||
          RegExp(r'^[A-Za-z0-9_-]{8,}$').hasMatch(last) &&
              !last.contains('.')) {
        return last;
      }
    }
    return null;
  }

  /// A name for a post whose page told us nothing usable: the account that
  /// posted it and the post's ID, so two posts never share it.
  ///
  /// "Name – TikTok 7234567890", "TikTok video 7234567890", "TikTok video".
  /// [noun] is what the post is — "video" unless it is a photo post.
  static String fallback({
    required String source,
    required Uri url,
    String? author,
    String noun = 'video',
  }) {
    final id = postIdOf(url);
    final by = specific(author);
    if (by != null) {
      return id == null ? '$by – $source' : '$by – $source $id';
    }
    return id == null ? '$source $noun' : '$source $noun $id';
  }

  /// The best name for a post: its own title when it has one, otherwise
  /// [fallback].
  static String resolve({
    required String? title,
    required String source,
    required Uri url,
    String? author,
    String noun = 'video',
  }) =>
      specific(title) ??
      fallback(source: source, url: url, author: author, noun: noun);
}
