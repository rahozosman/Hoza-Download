import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data' show BytesBuilder;

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
/// A video is offered at the highest quality the platform publishes, not
/// only the one file its page happens to name: TikTok's embeddable player
/// lists heavier encodes than its phone page, and Instagram keeps its best
/// rendition in a DASH manifest, as separate picture and sound tracks that
/// are merged once both are down. TikTok's stamped "Save video" file is
/// never offered at all.
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
    this.tiktokHd = false,
    // ignore: prefer_initializing_formals
  }) : _catalog = catalog;

  final HttpClient _client;
  final EndpointHealth _health;

  /// Whether TikTok's HD file is looked up through tikwm.com.
  ///
  /// Off unless the user's setting turns it on: the lookup sends the post's
  /// link to a service outside TikTok, which nothing does without asking.
  final bool tiktokHd;

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

    // TikTok's player API is asked alongside the page rather than after it,
    // so the heavier encodes it lists cost the lookup no extra wait.
    final renditions = site == _Site.tiktok ? _tiktokRenditions(url) : null;

    UnsupportedSource? refusal;

    for (var start = 0; start < routes.length; start += _waveSize) {
      final wave = routes.skip(start).take(_waveSize).toList();
      final result = await _firstPageWithMedia(site, url, wave);

      final found = result.attempt;
      if (found != null) {
        final built = await _build(site, found, renditions);
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

  /// How long a page with only the single file waits for a sibling route
  /// that may carry the platform's quality ladder.
  static const Duration _ladderGrace = Duration(seconds: 4);

  /// Runs one wave of routes and completes as soon as one of them returns a
  /// page with media in it.
  ///
  /// On a platform that keeps its best quality in a manifest only some of its
  /// pages carry, a page without one is held for a moment while the rest of
  /// the wave is still out: Instagram's embed page tends to answer first with
  /// only the capped single file, and its post page a beat later with the
  /// whole ladder. The wait is bounded, so a slow sibling never costs the
  /// post.
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
    _PageWithMedia? held;
    Timer? grace;

    void settle(_WaveResult result) {
      grace?.cancel();
      if (!found.isCompleted) found.complete(result);
    }

    for (final route in wave) {
      unawaited(
        _attempt(site, url, route).then((attempt) {
          pending--;
          if (attempt is _PageWithMedia) {
            if (attempt.adaptive || !site.publishesAdaptiveStreams) {
              settle(_WaveResult(attempt: attempt));
            } else if (held == null) {
              held = attempt;
              grace = Timer(
                _ladderGrace,
                () => settle(_WaveResult(attempt: held)),
              );
            }
          } else if (attempt is _PageRefused) {
            refusal = _clearer(refusal, attempt.refusal);
          }
          if (pending == 0) {
            settle(_WaveResult(attempt: held, refusal: refusal));
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
      // A stamped rendition is never offered, not even as a last resort: a
      // video with someone else's @name sliding across it is not the video
      // anyone asked to save. An older cached config may still name one.
      if (_isWatermarked(label, url)) return;
      videos.add(_Candidate(url, label, MediaType.video));
    }

    // The platform's quality ladder, where the page publishes one, ahead of
    // the single files: it is where the highest quality lives.
    final ladder = site.publishesAdaptiveStreams
        ? _adaptiveRenditions(html, pageUrl)
        : const <_Candidate>[];

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
      hasVideo: videos.isNotEmpty || ladder.isNotEmpty,
    )) {
      if (photos.length >= _maxImages) break;
      if (!seenFiles.add(_fileKey(photo.url))) continue;
      photos.add(photo);
    }

    return [
      ...ladder,
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

  /// Upper bound on how many rungs of a quality ladder are offered per post.
  static const int _maxRenditions = 4;

  /// The quality ladder a page's DASH manifest publishes: each picture size
  /// once, at the highest bitrate published for it, paired with the best
  /// soundtrack.
  ///
  /// Instagram keeps its best rendition here and only here — the single file
  /// it also publishes is capped below what the manifest carries. Every track
  /// in the manifest is a whole file at its own address, so nothing is
  /// streamed: the picture and the sound are fetched and merged, as YouTube's
  /// are. Tracks Android's MP4 muxer will not take (VP9, AV1) are passed over,
  /// and a manifest without a soundtrack offers nothing, since the single
  /// file is then already the whole post.
  static List<_Candidate> _adaptiveRenditions(String html, Uri pageUrl) {
    final manifest = _dashManifest(html);
    if (manifest == null) return const [];

    ({Uri url, int bandwidth})? sound;
    final pictures = <int, ({Uri url, int bandwidth, String codecs})>{};

    for (final match in _dashRepresentation.allMatches(manifest)) {
      final attributes = {
        for (final attribute in _xmlAttribute.allMatches(match.group(1)!))
          attribute.group(1)!: attribute.group(2)!,
      };
      final url = _absolute(
        _dashBaseUrl.firstMatch(match.group(2)!)?.group(1),
        pageUrl,
      );
      if (url == null) continue;

      final mimeType = (attributes['mimeType'] ?? '').toLowerCase();
      final codecs = (attributes['codecs'] ?? '').toLowerCase();
      final bandwidth = int.tryParse(attributes['bandwidth'] ?? '') ?? 0;

      if (mimeType.startsWith('audio/')) {
        if (!codecs.startsWith('mp4a')) continue;
        if (sound == null || bandwidth > sound.bandwidth) {
          sound = (url: url, bandwidth: bandwidth);
        }
      } else if (mimeType.startsWith('video/')) {
        if (!_muxableVideoCodecs.hasMatch(codecs)) continue;
        final side = _shortSide(
          int.tryParse(attributes['width'] ?? ''),
          int.tryParse(attributes['height'] ?? ''),
        );
        if (side == null) continue;
        final kept = pictures[side];
        if (kept == null || bandwidth > kept.bandwidth) {
          pictures[side] = (url: url, bandwidth: bandwidth, codecs: codecs);
        }
      }
    }

    final soundtrack = sound?.url;
    if (soundtrack == null || pictures.isEmpty) return const [];

    final sides = pictures.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final side in sides.take(_maxRenditions))
        _Candidate(
          pictures[side]!.url,
          _qualityLabel(side, codec: pictures[side]!.codecs),
          MediaType.video,
          heightPx: side,
          audioUrl: soundtrack,
        ),
    ];
  }

  /// The DASH manifest a page carries, as markup, or null when it has none.
  ///
  /// It sits in the page as a JSON string — escaped once in the post page and
  /// twice in the embed page, which keeps its JSON inside a JSON string — so
  /// layers are peeled off until the manifest reads as markup again.
  static String? _dashManifest(String html) {
    final at = html.indexOf('video_dash_manifest');
    if (at < 0) return null;
    final stop = at + _maxManifestChars;
    var text = html.substring(at, stop < html.length ? stop : html.length);
    for (var layer = 0; layer < 3 && !text.contains('</MPD>'); layer++) {
      text = _jsonUnescape(text);
    }
    final start = text.indexOf('<MPD');
    final end = start < 0 ? -1 : text.indexOf('</MPD>', start);
    return end < 0 ? null : text.substring(start, end);
  }

  /// A manifest with a full ladder runs to about ten thousand characters
  /// escaped; this leaves room for a much longer one.
  static const int _maxManifestChars = 96 * 1024;

  static final RegExp _dashRepresentation = RegExp(
    r'<Representation\b([^>]*)>([\s\S]*?)</Representation>',
  );
  static final RegExp _xmlAttribute = RegExp(r'([A-Za-z:]+)="([^"]*)"');
  static final RegExp _dashBaseUrl = RegExp(r'<BaseURL>([^<]+)</BaseURL>');

  /// Video codecs Android's MP4 muxer copies as they are.
  static final RegExp _muxableVideoCodecs = RegExp(r'^(?:avc[13]|hvc1|hev1)');

  /// A rendition's size as people name it: its short side, so a portrait
  /// video 1080 pixels wide reads as the 1080p it is, and a 1080p quality
  /// preference finds it. Null when either dimension is missing.
  static int? _shortSide(int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width < height ? width : height;
  }

  /// `1080p`, with the codec named only when it is the one some players
  /// still stumble on.
  static String _qualityLabel(int shortSide, {String? codec}) {
    final name = (codec ?? '').toLowerCase();
    final hevc =
        name.startsWith('hvc1') ||
        name.startsWith('hev1') ||
        name.contains('265') ||
        name.contains('hevc') ||
        name.contains('bytevc1');
    return hevc ? '${shortSide}p HEVC' : '${shortSide}p';
  }

  /// How long TikTok's player API may take before the post is offered
  /// without it.
  static const Duration _playerApiTimeout = Duration(seconds: 8);

  /// The player API's answer for one post is a few dozen kilobytes.
  static const int _maxPlayerApiBytes = 1024 * 1024;

  static final Uri _tiktokPlayerApi = Uri.https(
    'www.tiktok.com',
    '/player/api/v1/items',
  );

  /// The post ID in a TikTok video link: `/@name/video/7…` or `/v/7….html`.
  static final RegExp _tiktokPostId = RegExp(r'/(?:video|v)/(\d{8,})');

  /// How long the tikwm.com lookup may take — its answer, then the front of
  /// the HD file it names — before the post is offered without it.
  static const Duration _tikwmTimeout = Duration(seconds: 12);

  static final Uri _tikwmApi = Uri.https('www.tikwm.com', '/api/');

  /// How much of a file is read to find its picture size. TikTok writes the
  /// index that holds it at the front of the file, well inside this.
  static const int _mp4HeaderBytes = 256 * 1024;

  /// Every clean rendition of a TikTok video post found beyond its page: the
  /// HD file through tikwm.com when [tiktokHd] allows it, then the files
  /// TikTok's embeddable player lists. Empty when the link names no video
  /// post or neither answers; the page's own address still stands either way.
  ///
  /// The page TikTok serves a phone names one file, and it is often the
  /// lightest encode the post has. The player other sites embed TikToks with
  /// is fed from an API that answers without an account and lists the files
  /// that player may choose between — a heavier, sharper encode among them
  /// more often than not. They are the player's own files, so none carries
  /// the stamp "Save video" burns in. None of TikTok's own answers goes above
  /// 576p for a visitor without an account; only tikwm.com reaches the HD
  /// file.
  Future<List<_Candidate>> _tiktokRenditions(Uri url) async {
    final id = _tiktokPostId.firstMatch(url.path)?.group(1);
    if (id == null) return const [];
    final (hd, player) = await (
      tiktokHd
          ? _guarded('tiktok:tikwm', _tikwmTimeout, () => _readTikwm(url), null)
          : Future<_Candidate?>.value(),
      _guarded(
        'tiktok:player',
        _playerApiTimeout,
        () => _readTiktokPlayer(id),
        const <_Candidate>[],
      ),
    ).wait;
    return [?hd, ...player];
  }

  /// [work], bounded in time and never throwing: a lookup beyond the page only
  /// ever adds renditions, so its failure is logged and passed over.
  static Future<T> _guarded<T>(
    String tag,
    Duration timeout,
    Future<T> Function() work,
    T fallback,
  ) async {
    try {
      return await work().timeout(timeout);
    } catch (error) {
      AppLog.warn(tag, error.runtimeType);
      return fallback;
    }
  }

  Future<List<_Candidate>> _readTiktokPlayer(String id) async {
    final request = await _client.getUrl(
      _tiktokPlayerApi.replace(queryParameters: {'item_ids': id}),
    );
    _askForJson(request);
    request.headers
      ..set(HttpHeaders.userAgentHeader, BrowserProfile.userAgent)
      ..set(HttpHeaders.refererHeader, _Site.tiktok.referer);
    final answer = await _readJson(await request.close(), 'tiktok:player');
    final renditions = _tiktokPlayerRenditions(answer);
    AppLog.warn('tiktok:player', '${renditions.length} renditions');
    return renditions;
  }

  /// TikTok's HD file for a post, found through tikwm.com, labelled with the
  /// size the file itself declares. Null when the post has no encode above
  /// the one TikTok already hands out, or the service does not answer.
  ///
  /// tikwm.com holds the kind of session TikTok serves its HD encode to, and
  /// answers with addresses on TikTok's own CDN, so the bytes still come from
  /// TikTok. Only the post's link is sent, and the watermarked address in the
  /// answer is never read.
  Future<_Candidate?> _readTikwm(Uri url) async {
    final form = utf8.encode(
      'url=${Uri.encodeQueryComponent(url.toString())}&hd=1',
    );
    final request = await _client.postUrl(_tikwmApi);
    _askForJson(request);
    request.headers
      ..set(HttpHeaders.userAgentHeader, BrowserProfile.userAgent)
      ..set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded; charset=utf-8',
      );
    request.contentLength = form.length;
    request.add(form);

    final address = _tikwmHdAddress(
      await _readJson(await request.close(), 'tiktok:tikwm'),
    );
    if (address == null) return null;

    final picture = await _mp4Picture(
      address,
      BrowserProfile.mediaHeaders(referer: _Site.tiktok.referer),
    );
    if (picture == null) {
      AppLog.warn('tiktok:tikwm', 'HD file did not declare its size');
      return null;
    }
    AppLog.warn('tiktok:tikwm', 'HD ${picture.side}p ${picture.codec}');
    return _Candidate(
      address,
      _qualityLabel(picture.side, codec: picture.codec),
      MediaType.video,
      heightPx: picture.side,
    );
  }

  /// The HD address in tikwm.com's answer, when it names a different file
  /// from the one TikTok already hands out: for a post with no better encode
  /// the service names the ordinary file as its HD one, and the two sizes it
  /// reports then match.
  static Uri? _tikwmHdAddress(Object? answer) {
    if (answer is! Map) return null;
    final data = answer['data'];
    if (answer['code'] != 0 || data is! Map) {
      AppLog.warn('tiktok:tikwm', 'no answer: ${answer['msg']}');
      return null;
    }
    final hdBytes = _intOf(data['hd_size']);
    if (hdBytes == null || hdBytes == _intOf(data['size'])) return null;
    final raw = data['hdplay'];
    final address = raw is String ? _absolute(raw, _tikwmApi) : null;
    if (address == null || _isWatermarked('', address)) return null;
    return address;
  }

  /// The picture size and codec an MP4 file declares at its front, or null
  /// when the front does not say.
  Future<({int side, String codec})?> _mp4Picture(
    Uri url,
    Map<String, String> headers,
  ) async {
    final request = await _client.getUrl(url);
    headers.forEach(request.headers.set);
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=0-${_mp4HeaderBytes - 1}',
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      return null;
    }
    final front = BytesBuilder(copy: false);
    await for (final chunk in response) {
      front.add(chunk);
      if (front.length >= _mp4HeaderBytes) break;
    }
    return _mp4PictureOf(front.takeBytes());
  }

  /// Reads the track header (`tkhd`) boxes: each ends with its track's width
  /// and height in 16.16 fixed point, which are zero for a sound track.
  static ({int side, String codec})? _mp4PictureOf(List<int> data) {
    int u32(int at) =>
        (data[at] << 24) | (data[at + 1] << 16) | (data[at + 2] << 8) |
        data[at + 3];

    for (var at = 4; at + 4 <= data.length; at++) {
      // `tkhd`
      if (data[at] != 0x74 ||
          data[at + 1] != 0x6B ||
          data[at + 2] != 0x68 ||
          data[at + 3] != 0x64) {
        continue;
      }
      final start = at - 4;
      final size = u32(start);
      if (size < 84 || size > 200 || start + size > data.length) continue;
      final side = _shortSide(
        u32(start + size - 8) >> 16,
        u32(start + size - 4) >> 16,
      );
      if (side == null) continue;
      final text = latin1.decode(data);
      final hevc = text.contains('hvc1') || text.contains('hev1');
      return (side: side, codec: hevc ? 'hvc1' : 'avc1');
    }
    return null;
  }

  /// Asks for an answer that can be read: the shared client leaves bodies
  /// compressed, which is right for media and wrong for JSON.
  static void _askForJson(HttpClientRequest request) => request.headers
    ..set(HttpHeaders.acceptHeader, 'application/json')
    ..set(HttpHeaders.acceptEncodingHeader, 'identity');

  /// A JSON answer, decoded, or null when it is not a 200 or runs too large.
  static Future<Object?> _readJson(
    HttpClientResponse response,
    String tag,
  ) async {
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      AppLog.warn(tag, 'HTTP ${response.statusCode}');
      return null;
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response) {
      body.add(chunk);
      if (body.length > _maxPlayerApiBytes) return null;
    }
    List<int> bytes = body.takeBytes();
    // Told apart by its first two bytes rather than by the header: TikTok's
    // own APIs have been seen sending gzip without saying so.
    if (bytes.length > 1 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = gzip.decode(bytes);
    }
    return jsonDecode(utf8.decode(bytes));
  }

  /// The renditions in the player API's answer: the file the player opens
  /// on, sized by the post's own dimensions, then each encode it lists. The
  /// API is undocumented, so every field is checked rather than trusted.
  static List<_Candidate> _tiktokPlayerRenditions(Object? answer) {
    if (answer is! Map) return const [];
    final items = answer['items'];
    if (items is! List || items.isEmpty) return const [];
    final item = items.first;
    final info = item is Map ? item['video_info'] : null;
    if (info is! Map) return const [];

    final renditions = <_Candidate>[];
    void add(Object? urls, Object? width, Object? height, {Object? codec}) {
      if (urls is! List || renditions.length >= _maxRenditions) return;
      final addresses = [
        for (final raw in urls)
          if (raw is String) ?_absolute(raw, _tiktokPlayerApi),
      ];
      if (addresses.isEmpty) return;
      final side = _shortSide(_intOf(width), _intOf(height));
      renditions.add(
        _Candidate(
          addresses.first,
          side == null
              ? 'Original'
              : _qualityLabel(side, codec: codec is String ? codec : null),
          MediaType.video,
          mirrors: addresses.skip(1).toList(),
          heightPx: side,
        ),
      );
    }

    final meta = info['meta'];
    add(
      info['url_list'],
      meta is Map ? meta['width'] : null,
      meta is Map ? meta['height'] : null,
    );
    final profiles = info['profiles'];
    if (profiles is List) {
      for (final profile in profiles) {
        if (profile is! Map) continue;
        final address = profile['play_addr'];
        if (address is! Map) continue;
        add(
          address['url_list'],
          address['width'],
          address['height'],
          codec: profile['codec_type'],
        );
      }
    }
    return renditions;
  }

  static int? _intOf(Object? value) => switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };

  /// Whether an address serves the post with the platform's stamp burned
  /// into the picture — on TikTok, the poster's @name sliding across the
  /// video and the TikTok logo in the corner.
  ///
  /// TikTok publishes every video twice: the player streams a clean file,
  /// while "Save video" hands out a stamped one. The page says which is
  /// which twice over — in the field the address sits in, which the
  /// extractor catalog labels, and in the address itself, which asks the CDN
  /// for the stamp in its own query.
  static bool _isWatermarked(String label, Uri url) =>
      label.toLowerCase().contains('watermark') ||
      _watermarkQuery.hasMatch(url.query);

  static final RegExp _watermarkQuery = RegExp(
    r'(?:^|&)(?:watermark=1|logo_name=)',
    caseSensitive: false,
  );

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

  /// Probes each soundtrack a quality ladder pairs its pictures with — once,
  /// however many pictures share it.
  Future<Map<Uri, MediaProbe?>> _probeSounds(
    List<_Candidate> candidates,
    Map<String, String> headers,
  ) async {
    final sounds = {for (final candidate in candidates) ?candidate.audioUrl};
    final probes = await Future.wait(
      sounds.map((url) => _probeQuietly(url, headers)),
    );
    return Map.fromIterables(sounds, probes);
  }

  /// [_fileKey], when it is specific enough to say two addresses name the
  /// same file: TikTok names each file by a long hash, where an API address
  /// like `/aweme/v1/play/` names only the endpoint.
  static String? _sharedFileKey(Uri url) {
    final key = _fileKey(url);
    return key.length >= 16 ? key : null;
  }

  Future<SourceResolution> _build(
    _Site site,
    _PageWithMedia found,
    Future<List<_Candidate>>? pendingRenditions,
  ) async {
    final pageUrl = found.pageUrl;
    final scraped = found.scraped;

    // The platform's own renditions go first, and a page address naming one
    // of the same files is folded away rather than probed and listed a
    // second time under a vaguer name.
    final renditions = pendingRenditions == null
        ? const <_Candidate>[]
        : await pendingRenditions;
    final published = {
      for (final rendition in renditions)
        for (final url in [rendition.url, ...rendition.mirrors])
          ?_sharedFileKey(url),
    };
    final candidates = [
      ...renditions,
      for (final candidate in found.candidates)
        if (candidate.kind != MediaType.video ||
            !published.contains(_sharedFileKey(candidate.url)))
          candidate,
    ];

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

    final (probes, sounds) = await (
      _probeAll(candidates, headers),
      _probeSounds(candidates, headers),
    ).wait;

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

      // A picture published apart from its sound is only worth listing with
      // the soundtrack that goes with it; silent, it is not the post.
      final soundUrl = candidate.audioUrl;
      final sound = soundUrl == null ? null : sounds[soundUrl];
      if (soundUrl != null && (sound == null || !sound.isSuccess)) {
        AppLog.warn(
          '${site.name} media probe',
          'soundtrack refused by ${soundUrl.host}',
        );
        continue;
      }

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
          heightPx:
              candidate.heightPx ??
              (candidate.kind == MediaType.video && candidates.length == 1
                  ? scraped.heightPx
                  : null),
          estimatedBytes: probe.totalBytes,
          // Both halves of a merged download have to pick up where they
          // stopped for the whole of it to.
          supportsResume:
              probe.supportsResume && (sound?.supportsResume ?? true),
          headers: headers,
          audioUrl: soundUrl,
          audioBytes: sound?.totalBytes,
        ),
      );
    }

    // One tile per quality name. Several addresses often name the same
    // rendition — a page files its video under more than one key, and the
    // player API lists the file it opens on among its encodes — and where
    // two different files share a name, the heavier is the sharper encode.
    // The list is ranked best first, so the sheet opens on the highest
    // quality the post has, whatever it weighs.
    final heaviest = <String, MediaVariant>{};
    for (final variant in variants) {
      if (variant.mediaType != MediaType.video) continue;
      final kept = heaviest[variant.label];
      if (kept == null ||
          (variant.totalEstimatedBytes ?? 0) >
              (kept.totalEstimatedBytes ?? 0)) {
        heaviest[variant.label] = variant;
      }
    }
    variants.removeWhere(
      (variant) =>
          variant.mediaType == MediaType.video &&
          !identical(heaviest[variant.label], variant),
    );

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

  /// Whether the page published the platform's quality ladder, not only its
  /// single file.
  bool get adaptive => candidates.any((candidate) => candidate.audioUrl != null);
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
  const _Candidate(
    this.url,
    this.label,
    this.kind, {
    this.mirrors = const [],
    this.heightPx,
    this.audioUrl,
  });

  final Uri url;
  final String label;

  /// What the page said the file is. The server's own answer takes precedence
  /// once the file is probed; this decides only when it says nothing useful.
  final MediaType kind;

  /// The same file on other hosts, to try in order when [url] is refused.
  final List<Uri> mirrors;

  /// The picture's short side, when the platform said how big the file is.
  final int? heightPx;

  /// The soundtrack to merge in, for a picture published as a track of its
  /// own — which is how a platform's highest quality usually comes.
  final Uri? audioUrl;
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

  /// Whether some of this platform's pages publish a DASH manifest holding
  /// renditions above the single file every page names.
  bool get publishesAdaptiveStreams => this == _Site.instagram;

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
