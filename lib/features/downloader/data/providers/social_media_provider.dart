import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../../../core/utils/app_log.dart';
import '../../../../core/utils/media_titles.dart';
import '../../../../data/models/media_option.dart';
import '../../../../services/config/remote_config.dart';
import '../../domain/source_provider.dart';
import '../resolvers/endpoint_health.dart';
import 'media_probe.dart';
import 'page_fetcher.dart';
import 'page_media_scraper.dart';

/// Reads the media a social post carries in its own page.
///
/// TikTok, Instagram and Facebook all render the post server-side and leave
/// the media URL in the HTML — in the JSON the page hydrates itself from, or
/// in the Open Graph tags the platform publishes for link previews. This
/// provider reads those, then fetches the file with the `Referer` the CDN
/// expects, which is the difference between a working download and a 403.
///
/// Photo posts are read the same way: a TikTok slideshow, an Instagram photo
/// or carousel and a Facebook photo each leave their pictures in the page,
/// and every one of them is offered as its own download.
///
/// These platforms hand a *different page* to each kind of client, and only
/// some of those pages carry the media at all: TikTok answers a desktop agent
/// with a placeholder, and Meta's sites answer one with an error. So each post
/// is asked for down several routes at once, and the first page that actually
/// contains the media wins. Which route worked is remembered, so the next post
/// from the same platform starts with it.
///
/// Private posts stay private: a page that needs an account returns a login
/// wall with no media in it, and that is reported rather than worked around.
class SocialMediaProvider implements SourceProvider {
  SocialMediaProvider(
    this._client,
    this._health, {
    ExtractorCatalog catalog = ExtractorCatalog.builtIn,
    // ignore: prefer_initializing_formals
  }) : _catalog = catalog;

  final HttpClient _client;
  final EndpointHealth _health;

  /// Where each platform keeps its video URLs — the built-in lists, or the
  /// remote config's replacements once it has been fetched.
  final ExtractorCatalog _catalog;

  /// Upper bound on how many published video URLs are checked per post.
  static const int _maxCandidates = 4;

  /// Upper bound on how many of a post's photos are offered. A slideshow can
  /// run to dozens, and every one is probed before the sheet opens.
  static const int _maxImages = 20;

  /// How many photos are probed at once.
  static const int _photoProbeBatch = 4;

  /// These pages run to about a megabyte and keep the media URL well past
  /// where an ordinary page would have ended.
  static const int _maxPageBytes = 2 * 1024 * 1024;

  /// How many routes are asked at once.
  ///
  /// Two covers the pair of clients a platform usually splits its pages
  /// between, without pulling several megabytes of markup for a lookup that
  /// the first route would have answered.
  static const int _waveSize = 2;

  @override
  String get name => 'Social';

  @override
  bool canHandle(Uri url) => _siteFor(url) != null;

  @override
  Future<SourceResolution> resolve(Uri url, {required Duration timeout}) async {
    final site = _siteFor(url);
    if (site == null) {
      return const UnsupportedSource(UnsupportedReason.noProvider);
    }

    try {
      return await _resolve(site, url).timeout(timeout);
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

  /// Asks the platform down each of its routes, a wave at a time, and keeps
  /// the first page that actually contains the post's media.
  Future<SourceResolution> _resolve(_Site site, Uri url) async {
    final routes = _health.order(
      site.routes,
      (route) => _routeKey(site, route),
    );

    UnsupportedSource? refusal;

    for (var start = 0; start < routes.length; start += _waveSize) {
      final wave = routes.skip(start).take(_waveSize).toList();
      final result = await _firstPageWithMedia(site, url, wave);

      final found = result.attempt;
      if (found != null) {
        final built = await _build(site, found);
        if (built is ResolvedMedia) return built;
        // The page named the file but its server would not hand it over down
        // this route; another route may carry a session the server accepts.
        refusal = _clearer(refusal, built as UnsupportedSource);
        continue;
      }
      refusal = _clearer(refusal, result.refusal);
    }

    return refusal ?? _noMedia(site);
  }

  /// Of two refusals, the one that explains more: a sign-in wall says what
  /// the platform did, where a route the platform simply rejects says
  /// nothing about the post.
  static UnsupportedSource? _clearer(
    UnsupportedSource? current,
    UnsupportedSource? next,
  ) {
    if (next == null) return current;
    if (current == null) return next;
    return _rank(next) > _rank(current) ? next : current;
  }

  static int _rank(UnsupportedSource refusal) => switch (refusal.reason) {
    UnsupportedReason.restricted => 3,
    UnsupportedReason.noDownloadableVariant => refusal.detail == null ? 1 : 2,
    UnsupportedReason.lookupFailed => refusal.detail == null ? 0 : 1,
    UnsupportedReason.noProvider => 0,
  };

  /// Runs one wave of routes and completes as soon as one of them returns a
  /// page with media in it.
  ///
  /// The routes that lose are left to finish quietly; their answers are
  /// dropped, but what they said about the platform is remembered.
  Future<_WaveResult> _firstPageWithMedia(
    _Site site,
    Uri url,
    List<_Route> wave,
  ) {
    final found = Completer<_WaveResult>();
    var pending = wave.length;
    UnsupportedSource? refusal;

    for (final route in wave) {
      unawaited(
        _attempt(site, url, route).then((attempt) {
          if (attempt is _PageWithMedia && !found.isCompleted) {
            found.complete(_WaveResult(attempt: attempt));
          } else if (attempt is _PageRefused) {
            refusal = _clearer(refusal, attempt.refusal);
          }
          pending--;
          if (pending == 0 && !found.isCompleted) {
            found.complete(_WaveResult(refusal: refusal));
          }
        }),
      );
    }

    return found.future;
  }

  /// One route, asked once. Never throws: a route that fails is one client's
  /// view of the post, not the platform's answer.
  Future<_PageAttempt> _attempt(_Site site, Uri url, _Route route) async {
    final key = _routeKey(site, route);
    final startedAt = DateTime.now();

    final target = route.embed ? site.embedUrl(url) : url;
    if (target == null) {
      // Not a link the embed page can be built for; the other routes still
      // read the post itself.
      return const _PageRefused(
        UnsupportedSource(UnsupportedReason.lookupFailed),
      );
    }

    try {
      final page = await PageFetcher.fetch(
        _client,
        target,
        headers: {HttpHeaders.userAgentHeader: route.agent},
        // These pages carry their media URL deep in an embedded payload, well
        // past where an ordinary page would have ended.
        maxBytes: _maxPageBytes,
      );

      final refusal = page.refusal;
      if (refusal != null) {
        AppLog.warn('$key page', 'HTTP ${page.probe.statusCode}');
        _health.recordFailure(key);
        // A post the platform will not serve without an account reads as a
        // permission problem, which is exactly what it is.
        return _PageRefused(
          refusal.reason == UnsupportedReason.restricted
              ? _privateOrGone(site)
              : refusal,
        );
      }

      final html = page.html;
      if (html == null) {
        AppLog.warn('$key page', 'not a page: ${page.probe.contentType}');
        _health.recordFailure(key);
        return _PageRefused(
          UnsupportedSource(
            UnsupportedReason.noDownloadableVariant,
            detail: '${site.label} did not return a post page for that link.',
          ),
        );
      }

      // Everything that reads the page — a megabyte or two of markup run
      // through a few dozen patterns — happens on a worker isolate. Done on
      // the UI isolate it holds the frame for long enough to see, which is
      // the sheet freezing while it says it is reading the link. Only plain
      // values cross over: the markup, the address, and the patterns as
      // text, compiled again on the other side.
      final fetchedUrl = page.url;
      final patterns = [
        for (final pattern in _catalog.videoFor(site.name))
          (pattern.pattern, pattern.label),
      ];
      final parsed = await Isolate.run(
        () => _parsePage(site, html, fetchedUrl, patterns),
      );

      final scraped = parsed.scraped;
      final candidates = parsed.candidates;
      AppLog.warn(
        '$key page',
        '${html.length} chars, ${candidates.length} media candidates, '
            '${page.cookies.length} cookies',
      );
      if (candidates.isEmpty) {
        _health.recordFailure(key);
        return _PageRefused(
          parsed.loginWall ? _loginWall(site) : _noMedia(site),
        );
      }

      _health.recordSuccess(key, DateTime.now().difference(startedAt));
      return _PageWithMedia(
        // The embed page stands in for the post; the download is still
        // recorded against the post itself.
        pageUrl: route.embed ? url : page.url,
        html: html,
        scraped: scraped,
        candidates: candidates,
        details: parsed.details,
        cookieHeader: page.cookieHeader,
      );
    } catch (error) {
      AppLog.warn('$key page', error.runtimeType);
      _health.recordFailure(key);
      return const _PageRefused(
        UnsupportedSource(UnsupportedReason.lookupFailed),
      );
    }
  }

  /// Names one way of asking a platform for a page, so the registry can tell
  /// the routes apart without ever storing a user agent as a key.
  static String _routeKey(_Site site, _Route route) {
    final client = switch (route.agent) {
      BrowserProfile.userAgent => 'mobile',
      BrowserProfile.desktopUserAgent => 'desktop',
      BrowserProfile.crawlerUserAgent => 'crawler',
      _ => 'other',
    };
    return '${site.name}:${route.embed ? 'embed' : client}';
  }

  UnsupportedSource _privateOrGone(_Site site) => UnsupportedSource(
    UnsupportedReason.restricted,
    detail:
        '${site.label} did not share this post. It may be private, deleted, '
        'or only visible to signed-in accounts.',
  );

  /// The platform answered with its sign-in page instead of the post.
  ///
  /// Meta's sites do this for whole regions and for any visitor they do not
  /// trust, not only for private posts — so the message says what actually
  /// happened rather than guessing at the post's privacy.
  UnsupportedSource _loginWall(_Site site) => UnsupportedSource(
    UnsupportedReason.restricted,
    detail:
        '${site.label} only shows this post to signed-in users from your '
        'network. Hoza does not sign in to accounts, so it cannot fetch it.',
  );

  /// Whether a page that carried no media is the platform's login screen.
  static bool _looksLikeLoginWall(String html) => _loginMarkers.hasMatch(html);

  static final RegExp _loginMarkers = RegExp(
    r'LoginForm|login_form|"is_logged_in"\s*:\s*false|/login/\?next=|'
    r'loginPage|accounts/login',
  );

  UnsupportedSource _noMedia(_Site site) => UnsupportedSource(
    UnsupportedReason.restricted,
    detail:
        '${site.label} served this post without its video or photos. That '
        'happens when the post is private, deleted, age-restricted, or only '
        'visible to signed-in accounts.',
  );

  /// Media the page published: the post's video best quality first — the
  /// platform's own JSON, then the Open Graph tags as a fallback — and then
  /// its photos in the order the post shows them.
  /// Reads everything the resolver needs from a page in one pass, so the
  /// whole read can run on a worker isolate: a static function over plain
  /// values, with the video patterns handed in as text.
  static _ParsedPage _parsePage(
    _Site site,
    String html,
    Uri pageUrl,
    List<(String, String)> patterns,
  ) {
    final scraped = PageMediaScraper.parse(
      html,
      pageUrl,
      maxCandidates: _maxCandidates,
    );
    final extractors = [
      for (final (pattern, label) in patterns) _SiteExtractor(pattern, label),
    ];
    final candidates = _candidates(site, html, pageUrl, scraped, extractors);
    return _ParsedPage(
      scraped: scraped,
      candidates: candidates,
      details: site.detailsOf(html, pageUrl),
      loginWall: candidates.isEmpty && _looksLikeLoginWall(html),
    );
  }

  static List<_Candidate> _candidates(
    _Site site,
    String html,
    Uri pageUrl,
    ScrapedPage scraped,
    List<_SiteExtractor> extractors,
  ) {
    final videos = <_Candidate>[];
    final seen = <Uri>{};

    void addVideo(Uri url, String label) {
      if (videos.length >= _maxCandidates) return;
      if (!seen.add(url)) return;
      if (MediaFormats.isManifest(url)) return;
      videos.add(_Candidate(url, label, MediaType.video));
    }

    for (final extractor in extractors) {
      for (final match in extractor.pattern.allMatches(html)) {
        final url = _absolute(match.group(1), pageUrl);
        if (url != null) addVideo(url, extractor.label);
      }
    }
    for (final candidate in scraped.candidates) {
      addVideo(candidate, 'Original');
    }

    // A platform hands out the same picture under several signed URLs — the
    // carousel's cover is its first photo again — so photos are told apart by
    // the file they name, not the signature they carry.
    final photos = <_Photo>[];
    final seenFiles = <String>{};
    for (final photo in site.imageUrls(
      html,
      pageUrl,
      scraped,
      hasVideo: videos.isNotEmpty,
    )) {
      if (photos.length >= _maxImages) break;
      if (!seenFiles.add(_fileKey(photo.url))) continue;
      photos.add(photo);
    }

    return [
      ...videos,
      for (var index = 0; index < photos.length; index++)
        _Candidate(
          photos[index].url,
          photos.length == 1 ? 'Photo' : 'Photo ${index + 1}',
          MediaType.image,
          mirrors: photos[index].mirrors,
        ),
    ];
  }

  /// The file a URL names, without the host that serves it or the signature
  /// on the request: TikTok's mirrors differ only in those.
  static String _fileKey(Uri url) {
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? url.host : segments.last;
  }

  /// Probes every candidate: videos all at once — there are at most a few —
  /// and photos a handful at a time, so a long slideshow does not open
  /// twenty connections before the sheet can show anything. A photo whose
  /// first host refuses is asked for on its mirrors before it is given up.
  Future<List<_Probed>> _probeAll(
    List<_Candidate> candidates,
    Map<String, String> headers,
  ) async {
    final results = List<_Probed?>.filled(candidates.length, null);

    Future<void> probeAt(int index) async {
      final candidate = candidates[index];
      var probe = await _probeQuietly(candidate.url, headers);
      var url = candidate.url;
      for (final mirror in candidate.mirrors) {
        if (probe != null && probe.isSuccess) break;
        probe = await _probeQuietly(mirror, headers);
        url = mirror;
      }
      results[index] = _Probed(probe, url);
    }

    final videos = <int>[];
    final photos = <int>[];
    for (var index = 0; index < candidates.length; index++) {
      (candidates[index].kind == MediaType.image ? photos : videos).add(index);
    }

    await Future.wait([
      Future.wait(videos.map(probeAt)),
      () async {
        for (var start = 0; start < photos.length; start += _photoProbeBatch) {
          await Future.wait(
            photos.skip(start).take(_photoProbeBatch).map(probeAt),
          );
        }
      }(),
    ]);

    return [for (final result in results) result!];
  }

  Future<SourceResolution> _build(_Site site, _PageWithMedia found) async {
    final candidates = found.candidates;
    final pageUrl = found.pageUrl;
    final scraped = found.scraped;

    // The file itself is fetched as a phone browser would: these CDNs check
    // where the request came from before they hand the bytes over — and
    // TikTok's also checks that it is the same session that read the page,
    // which is what the page's cookies say. The cookies travel with the
    // variant so the download, and a resume hours later, ask the same way.
    final cookies = found.cookieHeader;
    final headers = {
      ...BrowserProfile.mediaHeaders(referer: site.referer),
      HttpHeaders.cookieHeader: ?cookies,
    };

    final probes = await _probeAll(candidates, headers);

    final variants = <MediaVariant>[];
    var refusedStatus = 0;
    for (var index = 0; index < candidates.length; index++) {
      final probe = probes[index].probe;
      if (probe == null || !probe.isSuccess) {
        AppLog.warn(
          '${site.name} media probe',
          probe == null
              ? 'no answer from ${candidates[index].url.host}'
              : 'HTTP ${probe.statusCode} from ${candidates[index].url.host}',
        );
        if (probe != null && refusedStatus == 0) {
          refusedStatus = probe.statusCode;
        }
        continue;
      }

      final candidate = candidates[index];
      // The address that answered, which may be a mirror of the first.
      final url = probes[index].url;
      final format =
          MediaFormats.fromContentType(probe.contentType) ??
          MediaFormats.fromUrl(url) ??
          // These CDNs routinely answer with a generic binary type; the
          // platform only ever serves MP4 video and JPEG photos from these
          // endpoints.
          (candidate.kind == MediaType.image
              ? MediaFormat.jpg
              : MediaFormat.mp4);

      // A "video" address that turns out to serve a picture is a poster
      // frame or a cover the page mislabelled, not a rendition worth listing
      // under a quality name.
      if (candidate.kind == MediaType.video &&
          format.mediaType == MediaType.image) {
        continue;
      }

      variants.add(
        MediaVariant(
          id: 'social-$index',
          label: candidate.label,
          format: format,
          url: url,
          heightPx: candidate.kind == MediaType.video && candidates.length == 1
              ? scraped.heightPx
              : null,
          estimatedBytes: probe.totalBytes,
          supportsResume: probe.supportsResume,
          headers: headers,
        ),
      );
    }

    if (variants.isEmpty) {
      // The page named the file, so this is the platform's media server
      // saying no to this request — a transport problem worth another try,
      // not a protected post.
      return UnsupportedSource(
        UnsupportedReason.lookupFailed,
        detail:
            "${site.label}'s media server did not hand over the file"
            '${refusedStatus == 0 ? '' : ' (HTTP $refusedStatus)'}. '
            'Try again in a moment.',
      );
    }

    // TikTok's phone page carries no title or preview tags at all; what it
    // knows about the post is in the same JSON the media addresses came from,
    // read alongside them on the worker isolate.
    final details = found.details;

    // The post's own caption names it best. The page title is only a
    // fallback, and never when it is the site's slogan — TikTok titles every
    // page "TikTok - Make Your Day", which would give every video the same
    // file name. With neither, the account and post ID keep names apart.
    final onlyPhotos = variants.every(
      (variant) => variant.mediaType == MediaType.image,
    );
    final title = MediaTitles.resolve(
      title: MediaTitles.specific(details.title) ?? scraped.title,
      source: site.label,
      url: pageUrl,
      author: details.author,
      noun: onlyPhotos ? 'photo' : 'video',
    );

    // A photo post's first picture is its own best preview.
    final firstPhoto = variants
        .where((variant) => variant.mediaType == MediaType.image)
        .firstOrNull;

    return ResolvedMedia(
      MediaMetadata(
        sourceUrl: pageUrl,
        source: site.label,
        title: title,
        thumbnailUrl:
            scraped.thumbnailUrl ??
            details.thumbnailUrl ??
            firstPhoto?.url.toString(),
        durationSeconds: scraped.durationSeconds ?? details.durationSeconds,
        variants: variants,
      ),
    );
  }

  Future<MediaProbe?> _probeQuietly(
    Uri url,
    Map<String, String> headers,
  ) async {
    try {
      // The page named a file; an HTML answer is a refusal dressed as 200.
      return await MediaProbe.of(
        _client,
        url,
        headers: headers,
        expectMedia: true,
      );
    } on IOException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// A URL lifted out of embedded JSON still carries JSON escaping: these
  /// platforms escape every slash, and write the query separators as
  /// backslash-u escapes. Left as-is, the CDN would reject the request.
  ///
  /// Instagram's embed page goes one further and stores its JSON inside a
  /// JSON string, so a URL from there is escaped twice; each layer is peeled
  /// off in turn until none is left.
  static Uri? _absolute(String? raw, Uri pageUrl) {
    if (raw == null || raw.isEmpty || raw.length > 2048) return null;

    var unescaped = raw;
    for (var layer = 0; layer < 3 && unescaped.contains(r'\'); layer++) {
      unescaped = _jsonUnescape(unescaped);
    }
    unescaped = unescaped.replaceAll('&amp;', '&');

    final parsed = Uri.tryParse(unescaped);
    if (parsed == null) return null;

    final Uri resolved;
    try {
      resolved = parsed.hasScheme ? parsed : pageUrl.resolveUri(parsed);
    } on FormatException {
      return null;
    }

    final scheme = resolved.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return resolved.host.isEmpty ? null : resolved;
  }

  /// One layer of JSON string escaping, undone: `\/` and `\"` become the
  /// character itself, `&` and its kind become the character they name.
  static String _jsonUnescape(String text) =>
      text.replaceAllMapped(_jsonEscape, (match) {
        final hex = match.group(2);
        if (hex != null) {
          final code = int.parse(hex, radix: 16);
          return code == 0 ? '' : String.fromCharCode(code);
        }
        return switch (match.group(1)!) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          final other => other,
        };
      });

  static final RegExp _jsonEscape = RegExp(r'\\(u([0-9a-fA-F]{4})|.)');

  static _Site? _siteFor(Uri url) {
    final parts = url.host.toLowerCase().split('.');
    for (var index = 0; index < parts.length - 1; index++) {
      final domain = parts.sublist(index).join('.');
      for (final site in _Site.values) {
        if (site.domains.contains(domain)) return site;
      }
    }
    return null;
  }
}

/// What one route came back with.
sealed class _PageAttempt {
  const _PageAttempt();
}

/// Everything one read of a page produced, carried back from the worker
/// isolate as plain values.
class _ParsedPage {
  const _ParsedPage({
    required this.scraped,
    required this.candidates,
    required this.details,
    required this.loginWall,
  });

  final ScrapedPage scraped;
  final List<_Candidate> candidates;
  final _PageDetails details;

  /// Whether a page with no media in it was the platform's sign-in screen.
  final bool loginWall;
}

class _PageWithMedia extends _PageAttempt {
  const _PageWithMedia({
    required this.pageUrl,
    required this.html,
    required this.scraped,
    required this.candidates,
    required this.details,
    this.cookieHeader,
  });

  final Uri pageUrl;
  final String html;
  final ScrapedPage scraped;
  final List<_Candidate> candidates;

  /// What the page's own JSON said about the post.
  final _PageDetails details;

  /// The session the page handed this client, to present when fetching the
  /// media. Null when the page set no cookies.
  final String? cookieHeader;
}

class _PageRefused extends _PageAttempt {
  const _PageRefused(this.refusal);

  final UnsupportedSource refusal;
}

/// How a wave of routes ended: either one of them found the media, or none
/// did and the clearest refusal is carried forward.
class _WaveResult {
  const _WaveResult({this.attempt, this.refusal});

  final _PageWithMedia? attempt;
  final UnsupportedSource? refusal;
}

/// One media URL the page published, with the quality the page called it.
class _Candidate {
  const _Candidate(this.url, this.label, this.kind, {this.mirrors = const []});

  final Uri url;
  final String label;

  /// What the page said the file is. The server's own answer takes precedence
  /// once the file is probed; this decides only when it says nothing useful.
  final MediaType kind;

  /// The same file on other hosts, to try in order when [url] is refused.
  final List<Uri> mirrors;
}

/// One picture of a post, with the mirrors the page listed for it.
class _Photo {
  const _Photo(this.url, {this.mirrors = const []});

  final Uri url;
  final List<Uri> mirrors;
}

/// What a probe found, and at which address — the first mirror that
/// answered, when the page listed several.
class _Probed {
  const _Probed(this.probe, this.url);

  final MediaProbe? probe;
  final Uri url;
}

/// One way of asking a platform for a post: which client to be, and whether
/// to ask for the post page or the platform's embeddable rendition of it.
class _Route {
  const _Route(this.agent, {this.embed = false});

  final String agent;

  /// Ask for the embed page instead of the post page. Instagram's embed is
  /// the one public page that carries every photo of a post at full size.
  final bool embed;
}

/// Where each platform keeps the media URL, and what the CDN wants to see on
/// the request that fetches it.
enum _Site {
  /// TikTok answers a desktop agent with a placeholder shell; the mobile page
  /// is the one that carries the post's own data.
  tiktok(
    'TikTok',
    {'tiktok.com'},
    'https://www.tiktok.com/',
    [
      _Route(BrowserProfile.userAgent),
      _Route(BrowserProfile.crawlerUserAgent),
      _Route(BrowserProfile.desktopUserAgent),
    ],
  ),

  /// Instagram's post page only ever previews a photo, cropped and shrunk;
  /// its embed page carries the full-size picture, every picture of a
  /// carousel, and the video of a reel — so that is asked first.
  instagram(
    'Instagram',
    {'instagram.com', 'instagr.am'},
    'https://www.instagram.com/',
    [
      _Route(BrowserProfile.crawlerUserAgent, embed: true),
      _Route(BrowserProfile.crawlerUserAgent),
      _Route(BrowserProfile.userAgent),
      _Route(BrowserProfile.desktopUserAgent),
    ],
  ),

  /// Facebook refuses a plain browser agent outright and only serves the real
  /// page to the agent its own link previews are built with.
  facebook(
    'Facebook',
    {'facebook.com', 'fb.watch', 'fb.com'},
    'https://www.facebook.com/',
    [
      _Route(BrowserProfile.crawlerUserAgent),
      _Route(BrowserProfile.userAgent),
      _Route(BrowserProfile.desktopUserAgent),
    ],
  );

  const _Site(this.label, this.domains, this.referer, this.routes);

  final String label;
  final Set<String> domains;

  /// The page the CDN expects the request to have come from.
  final String referer;

  /// Routes to try, best first, until one returns a page with media in it.
  final List<_Route> routes;

  /// The platform's embeddable page for [url], or null when the link is not
  /// one the embed page can be built for (or the platform has no such page).
  Uri? embedUrl(Uri url) {
    if (this != _Site.instagram) return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    if (!const {'p', 'reel', 'reels', 'tv'}.contains(segments[0])) return null;
    return Uri.https(
      'www.instagram.com',
      '/${segments[0]}/${segments[1]}/embed/captioned/',
    );
  }

  /// The photos the page carries, in the order the post shows them.
  ///
  /// [hasVideo] says whether the same page already named a video: a video's
  /// poster frame sits in the page as a picture too, and is not what anyone
  /// means by the post's photos.
  List<_Photo> imageUrls(
    String html,
    Uri pageUrl,
    ScrapedPage scraped, {
    required bool hasVideo,
  }) => switch (this) {
    _Site.tiktok => _tiktokImages(html, pageUrl),
    _Site.instagram => [
      for (final url in _instagramImages(html, pageUrl, hasVideo: hasVideo))
        _Photo(url),
    ],
    _Site.facebook => [
      for (final url in _facebookImages(
        html,
        pageUrl,
        scraped,
        hasVideo: hasVideo,
      ))
        _Photo(url),
    ],
  };

  /// TikTok lists a slideshow's pictures under `imagePost.images`, each with
  /// a few mirrors of the same file — kept, so a host that refuses is not
  /// the end of the photo. The array is cut out by its own brackets so that
  /// the cover that follows it — the first picture again — and the pictures
  /// elsewhere in the page are left alone.
  static List<_Photo> _tiktokImages(String html, Uri pageUrl) {
    final start = _tiktokImagesStart.firstMatch(html);
    if (start == null) return const [];

    var depth = 1;
    var end = start.end;
    while (end < html.length && depth > 0) {
      final char = html.codeUnitAt(end);
      if (char == 0x5B) {
        depth++;
      } else if (char == 0x5D) {
        depth--;
      }
      end++;
    }

    final photos = <_Photo>[];
    for (final match in _tiktokImageList.allMatches(
      html.substring(start.end, end),
    )) {
      final urls = [
        for (final quoted in _quotedString.allMatches(match.group(1)!))
          ?SocialMediaProvider._absolute(quoted.group(1), pageUrl),
      ];
      if (urls.isEmpty) continue;
      photos.add(_Photo(urls.first, mirrors: urls.skip(1).toList()));
    }
    return photos;
  }

  static final RegExp _tiktokImagesStart = RegExp(
    r'"imagePost"\s*:\s*\{\s*"images"\s*:\s*\[',
  );
  static final RegExp _tiktokImageList = RegExp(
    r'"imageURL"\s*:\s*\{\s*"urlList"\s*:\s*\[([^\]]*)\]',
  );
  static final RegExp _quotedString = RegExp(r'"([^"]+)"');

  /// In the embed page's JSON every item says whether it is a video just
  /// before it names its picture, so a video's poster frame is told apart
  /// from a photo by the flag that precedes it. The keys arrive with their
  /// quotes escaped, since the JSON is stored inside a JSON string.
  static List<Uri> _instagramImages(
    String html,
    Uri pageUrl, {
    required bool hasVideo,
  }) {
    final found = <Uri>[];
    var isVideo = false;
    for (final match in _instagramItem.allMatches(html)) {
      final flag = match.group(1);
      if (flag != null) {
        isVideo = flag == 'true';
        continue;
      }
      if (isVideo) continue;
      final url = SocialMediaProvider._absolute(match.group(2), pageUrl);
      if (url != null) found.add(url);
    }
    if (found.isNotEmpty) return found;

    // A single photo's embed page sometimes carries no JSON at all and just
    // shows the picture, full size, in the page itself.
    if (hasVideo || _instagramVideoMarker.hasMatch(html)) return const [];
    final image = _instagramEmbeddedImage.firstMatch(html)?.group(0);
    final url = SocialMediaProvider._absolute(
      image == null ? null : _imgSrc.firstMatch(image)?.group(1),
      pageUrl,
    );
    return url == null ? const [] : [url];
  }

  static final RegExp _instagramItem = RegExp(
    r'is_video\\?"\s*:\s*(true|false)|display_url\\?"\s*:\s*\\?"([^"]+?)\\?"',
  );
  static final RegExp _instagramVideoMarker = RegExp(
    r'is_video\\?"\s*:\s*true|GraphVideo|video_url',
  );
  static final RegExp _instagramEmbeddedImage = RegExp(
    r'<img\b[^>]*\bEmbeddedMediaImage\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _imgSrc = RegExp(
    r'\bsrc\s*=\s*"([^"]+)"',
    caseSensitive: false,
  );

  /// Facebook names a photo in the page JSON, and a photo permalink's own
  /// preview tag is the photo at full size — unlike a video's, which is only
  /// its poster frame, so the preview counts only for a photo link.
  static List<Uri> _facebookImages(
    String html,
    Uri pageUrl,
    ScrapedPage scraped, {
    required bool hasVideo,
  }) {
    final found = <Uri>[];
    for (final pattern in _facebookImagePatterns) {
      for (final match in pattern.allMatches(html)) {
        final url = SocialMediaProvider._absolute(match.group(1), pageUrl);
        if (url != null) found.add(url);
      }
    }
    if (found.isNotEmpty || hasVideo) return found;
    if (!_isFacebookPhotoLink(pageUrl)) return const [];

    final preview = Uri.tryParse(scraped.thumbnailUrl ?? '');
    if (preview == null || preview.host.isEmpty) return const [];
    return [preview];
  }

  static final List<RegExp> _facebookImagePatterns = [
    RegExp(r'"photo_image"\s*:\s*\{\s*"uri"\s*:\s*"([^"]+)"'),
    RegExp(
      r'"currMedia"[\s\S]{0,600}?"image"\s*:\s*\{\s*"uri"\s*:\s*"([^"]+)"',
    ),
  ];

  static bool _isFacebookPhotoLink(Uri url) =>
      url.path.contains('/photo') || url.queryParameters.containsKey('fbid');

  /// What the page's own JSON says about the post, for the platforms whose
  /// pages carry no preview tags. Every field is optional.
  _PageDetails detailsOf(String html, Uri pageUrl) => switch (this) {
    _Site.tiktok => _PageDetails(
      // The caption, read from the post's own record when the page carries
      // one, so a "desc" belonging to the sound or a hashtag is not mistaken
      // for it. The account that posted it is kept apart, for the fallback
      // name.
      title:
          _jsonString(_tiktokItemDesc.firstMatch(html)?.group(1)) ??
          _jsonString(_tiktokDesc.firstMatch(html)?.group(1)),
      author: _jsonString(_tiktokNickname.firstMatch(html)?.group(1)),
      thumbnailUrl: SocialMediaProvider._absolute(
        _tiktokCover.firstMatch(html)?.group(1),
        pageUrl,
      )?.toString(),
      durationSeconds: int.tryParse(
        _tiktokDuration.firstMatch(html)?.group(1) ?? '',
      ),
    ),
    // The embed page has no preview tags either; the caption sits in its
    // JSON — inside a JSON string, so escaped twice — and the account in
    // the caption's own link.
    _Site.instagram => _PageDetails(
      title: _jsonString(
        _instagramCaption.firstMatch(html)?.group(1),
        layers: 2,
      ),
      author:
          _instagramCaptionUser.firstMatch(html)?.group(1)?.trim() ??
          _instagramSharedBy.firstMatch(html)?.group(1),
    ),
    _ => const _PageDetails(),
  };

  /// `edge_media_to_caption":{"edges":[{"node":{"text":"…"` with every quote
  /// escaped. Inside the caption a quote is `\\\"` and a newline `\\n`; the
  /// caption ends at the first lone `\"`.
  static final RegExp _instagramCaption = RegExp(
    r'edge_media_to_caption\\"[\s\S]{0,80}?\\"text\\"\s*:\s*\\"'
    r'((?:\\\\\\"|\\\\(?:\\\\|[^"\\])|[^"\\])*?)\\"',
  );
  static final RegExp _instagramCaptionUser = RegExp(
    r'class="CaptionUsername"[^>]*>([^<]{1,80})</a>',
  );
  static final RegExp _instagramSharedBy = RegExp(
    r'Instagram post shared by (?:&#064;|@)([A-Za-z0-9._]{1,60})',
  );

  /// The post record TikTok hydrates its player from opens with the post's
  /// ID and caption: `"itemStruct":{"id":"7…","desc":"…"`.
  static final RegExp _tiktokItemDesc = RegExp(
    r'"itemStruct"\s*:\s*\{\s*"id"\s*:\s*"\d+"\s*,\s*"desc"\s*:\s*'
    r'"((?:[^"\\]|\\.)*)"',
  );
  static final RegExp _tiktokDesc = RegExp(r'"desc"\s*:\s*"((?:[^"\\]|\\.)*)"');
  static final RegExp _tiktokNickname = RegExp(
    r'"nickname"\s*:\s*"((?:[^"\\]|\\.)*)"',
  );
  static final RegExp _tiktokCover = RegExp(r'"cover"\s*:\s*"([^"]+)"');
  static final RegExp _tiktokDuration = RegExp(
    r'"video"\s*:\s*\{[^}]{0,200}?"duration"\s*:\s*(\d+)',
  );

  /// A JSON string literal's contents, unescaped, or null when empty.
  /// [layers] is how many times the text was escaped: twice for JSON that
  /// was itself stored in a JSON string.
  static String? _jsonString(String? raw, {int layers = 1}) {
    if (raw == null) return null;
    var text = raw;
    for (var layer = 0; layer < layers; layer++) {
      text = SocialMediaProvider._jsonUnescape(text);
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? null : text;
  }
}

/// Title, preview and length read from a platform's own page JSON.
class _PageDetails {
  const _PageDetails({
    this.title,
    this.author,
    this.thumbnailUrl,
    this.durationSeconds,
  });

  final String? title;

  /// Display name of the account that posted it.
  final String? author;
  final String? thumbnailUrl;
  final int? durationSeconds;
}

/// A compiled place in the page where a platform leaves its media URL.
class _SiteExtractor {
  _SiteExtractor(String pattern, this.label)
    : pattern = RegExp(pattern, caseSensitive: false);

  final RegExp pattern;
  final String label;
}
