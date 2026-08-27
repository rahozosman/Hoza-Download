// The extractor watchdog: asks each platform for a real public post the way
// the app does, and reports — or repairs — the patterns that read it.
//
// Run by `.github/workflows/extractor-watchdog.yml` once a day, and by hand:
//
//     flutter test tool/watchdog/watchdog_test.dart
//     flutter test tool/watchdog/watchdog_test.dart \
//         --dart-define=WATCHDOG_SIMULATE_BREAK=facebook
//
// It lives under `tool/`, not `test/`, so the ordinary test run never touches
// the network. It is a test file only because the resolver stack imports
// Flutter, and `flutter test` is the runner that can load it.
//
// Two questions are asked per platform, with the real provider code:
//
//  1. Does a known public post still resolve to a downloadable video?
//  2. Do the config's own patterns still find that video in the page? A post
//     can resolve on the Open Graph fallback alone while the patterns rot,
//     which is a break waiting to happen.
//
// A "no" to either starts the repair: every candidate pattern the platform
// has ever been known to use — plus a few generic ones — is tried against the
// pages just fetched, and each match is probed as a real media request. Only
// patterns whose address actually serves a video are adopted. The repaired
// list is written to `server/config/extractors.json` with a bumped version,
// and the workflow commits it; phones pick it up through the remote config.
//
// Nothing here can make things worse: a pattern is adopted only after its
// download was verified, and the previous patterns are kept behind the new
// ones as fallbacks.

import 'dart:convert';
import 'dart:io';

import 'package:hoza_download/data/models/media_option.dart';
import 'package:hoza_download/features/downloader/data/providers/media_probe.dart';
import 'package:hoza_download/features/downloader/data/providers/page_fetcher.dart';
import 'package:hoza_download/features/downloader/data/providers/social_media_provider.dart';
import 'package:hoza_download/features/downloader/data/resolvers/endpoint_health.dart';
import 'package:hoza_download/features/downloader/domain/source_provider.dart';
import 'package:hoza_download/services/config/remote_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Platform to break on purpose, to prove the repair works. Empty for none.
const String simulateBreak = String.fromEnvironment('WATCHDOG_SIMULATE_BREAK');

/// Set to `false` to only report, never rewrite the config.
const bool healEnabled = bool.fromEnvironment(
  'WATCHDOG_HEAL',
  defaultValue: true,
);

const String extractorsPath = 'server/config/extractors.json';
const String watchdogPath = 'server/config/watchdog.json';
const String outDir = 'build/watchdog';

/// How long one post lookup may take, matching the app's own budget.
const Duration lookupTimeout = Duration(seconds: 45);

/// Most patterns kept per platform once the repaired ones are put first.
const int maxPatternsPerPlatform = 8;

void main() {
  test('extractor watchdog', () async {
    final report = await Watchdog().run();
    // A platform that is broken and could not be repaired fails the job so
    // the workflow opens an issue; a repaired one passes so it can commit.
    final unrepaired = report.platforms.where((p) => p.status == 'broken');
    expect(
      unrepaired,
      isEmpty,
      reason:
          'Broken and not repaired: '
          '${unrepaired.map((p) => p.platform).join(', ')}',
    );
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// One way of asking a platform for a page — mirrors the provider's routes.
class Route {
  const Route(this.agent, {this.embed = false});

  final String agent;
  final bool embed;

  String get key => embed
      ? 'embed'
      : switch (agent) {
          BrowserProfile.userAgent => 'mobile',
          BrowserProfile.desktopUserAgent => 'desktop',
          _ => 'crawler',
        };
}

/// What the provider knows about each platform that the watchdog needs too.
class Site {
  const Site(this.name, this.referer, this.routes);

  final String name;
  final String referer;
  final List<Route> routes;

  static const List<Site> all = [
    Site('tiktok', 'https://www.tiktok.com/', [
      Route(BrowserProfile.userAgent),
      Route(BrowserProfile.crawlerUserAgent),
      Route(BrowserProfile.desktopUserAgent),
    ]),
    Site('instagram', 'https://www.instagram.com/', [
      Route(BrowserProfile.crawlerUserAgent, embed: true),
      Route(BrowserProfile.crawlerUserAgent),
      Route(BrowserProfile.userAgent),
      Route(BrowserProfile.desktopUserAgent),
    ]),
    Site('facebook', 'https://www.facebook.com/', [
      Route(BrowserProfile.crawlerUserAgent),
      Route(BrowserProfile.userAgent),
      Route(BrowserProfile.desktopUserAgent),
    ]),
  ];

  static Site? named(String name) =>
      all.where((s) => s.name == name).firstOrNull;

  /// Instagram's embed page for a post link; null elsewhere.
  Uri? embedUrl(Uri url) {
    if (name != 'instagram') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    if (!const {'p', 'reel', 'reels', 'tv'}.contains(segments[0])) return null;
    return Uri.https(
      'www.instagram.com',
      '/${segments[0]}/${segments[1]}/embed/captioned/',
    );
  }
}

/// A page one route returned, kept for pattern checks and repair.
class Page {
  const Page(this.route, this.url, this.html, this.cookieHeader);

  final Route route;
  final Uri url;
  final String html;
  final String? cookieHeader;
}

class PlatformReport {
  PlatformReport(this.platform);

  final String platform;

  /// `ok`, `repaired`, `broken`, or `skipped` (no test links).
  String status = 'skipped';
  final List<String> notes = [];
  final List<String> resolvedLinks = [];
  final List<String> failedLinks = [];
  final List<String> livePatterns = [];
  final List<String> adoptedPatterns = [];

  Map<String, Object?> toJson() => {
    'platform': platform,
    'status': status,
    'resolved': resolvedLinks,
    'failed': failedLinks,
    'livePatterns': livePatterns,
    'adoptedPatterns': adoptedPatterns,
    'notes': notes,
  };
}

class Report {
  final List<PlatformReport> platforms = [];
  bool configChanged = false;
  int version = 0;

  Map<String, Object?> toJson() => {
    'ranAt': DateTime.now().toUtc().toIso8601String(),
    'simulateBreak': simulateBreak,
    'configChanged': configChanged,
    'version': version,
    'platforms': platforms.map((p) => p.toJson()).toList(),
  };

  String toMarkdown() {
    final buffer = StringBuffer();
    for (final p in platforms) {
      final icon = switch (p.status) {
        'ok' => '✅',
        'repaired' => '🔧',
        'broken' => '❌',
        _ => '⏭️',
      };
      buffer.writeln('### $icon ${p.platform} — ${p.status}');
      if (p.resolvedLinks.isNotEmpty) {
        buffer.writeln('- Resolved: ${p.resolvedLinks.length} link(s)');
      }
      for (final link in p.failedLinks) {
        buffer.writeln('- Failed: $link');
      }
      if (p.livePatterns.isNotEmpty) {
        buffer.writeln('- Live patterns: ${p.livePatterns.length}');
      }
      for (final pattern in p.adoptedPatterns) {
        buffer.writeln('- Adopted: `$pattern`');
      }
      for (final note in p.notes) {
        buffer.writeln('- $note');
      }
      buffer.writeln();
    }
    if (configChanged) {
      buffer.writeln('Config rewritten as version $version.');
    }
    return buffer.toString();
  }
}

class Watchdog {
  /// Set up exactly like the app's shared client: no default agent (each
  /// request names its own, and Dart would otherwise swap it for the default
  /// on a redirect) and no transparent decompression.
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = null
    ..autoUncompress = false;

  Future<Report> run() async {
    final report = Report();
    final extractorsFile = File(extractorsPath);
    final extractors =
        jsonDecode(extractorsFile.readAsStringSync()) as Map<String, Object?>;
    final config =
        jsonDecode(File(watchdogPath).readAsStringSync())
            as Map<String, Object?>;
    final links = (config['links'] as Map).cast<String, Object?>();
    final candidates = (config['candidates'] as Map).cast<String, Object?>();
    final generic = (config['generic'] as List).cast<Object?>();

    Directory('$outDir/pages').createSync(recursive: true);

    final catalogs = (extractors['extractors'] as Map).cast<String, Object?>();
    var changed = false;

    for (final site in Site.all) {
      final result = PlatformReport(site.name);
      report.platforms.add(result);

      final testLinks = (links[site.name] as List? ?? const [])
          .cast<String>()
          .map(Uri.parse)
          .toList();
      if (testLinks.isEmpty) {
        result.notes.add('No test links configured.');
        continue;
      }

      var patterns = _patternsOf(catalogs[site.name]);
      if (simulateBreak == site.name) {
        result.notes.add('Patterns replaced with a broken one on purpose.');
        patterns = const [
          ExtractorPattern(r'"__hoza_watchdog_broken__"\s*:\s*"([^"]+)"', 'x'),
        ];
      }
      final catalog = ExtractorCatalog({site.name: patterns});

      // 1. End to end, with the real provider.
      final provider = SocialMediaProvider(
        _client,
        EndpointHealth(),
        catalog: catalog,
      );
      for (final link in testLinks) {
        final outcome = await provider.resolve(link, timeout: lookupTimeout);
        if (outcome is ResolvedMedia &&
            outcome.metadata.hasVariantsFor(MediaType.video)) {
          result.resolvedLinks.add(link.toString());
        } else {
          final why = outcome is UnsupportedSource
              ? '${outcome.reason.name}${outcome.detail == null ? '' : ': ${outcome.detail}'}'
              : 'no video variant';
          result.failedLinks.add('$link — $why');
        }
      }
      final resolves = result.resolvedLinks.isNotEmpty;

      // 2. Pattern health, on the pages the routes return.
      final pages = <Page>[];
      for (final link in testLinks) {
        pages.addAll(await _fetchPages(site, link));
      }
      _savePages(site, pages);
      if (pages.isEmpty) {
        result.notes.add('No route returned a page.');
      }
      final live = await _livePatterns(site, pages, patterns);
      result.livePatterns.addAll(live.map((p) => p.pattern));

      if (resolves && live.isNotEmpty) {
        result.status = 'ok';
        continue;
      }
      if (!resolves) {
        result.notes.add('No test link resolved to a video.');
      } else {
        result.notes.add(
          'Posts still resolve, but only through the Open Graph fallback: '
          'none of the configured patterns matched.',
        );
      }

      // 3. Repair.
      if (!healEnabled) {
        result.status = 'broken';
        result.notes.add('Repair disabled.');
        continue;
      }
      final library = [
        ..._patternsOf(candidates[site.name]),
        ..._patternsOf(generic),
      ];
      final working = await _livePatterns(site, pages, library);
      if (working.isEmpty) {
        result.status = 'broken';
        result.notes.add(
          'No candidate pattern found a working video address in '
          '${pages.length} page(s). This needs a code change.',
        );
        continue;
      }

      // Adopted patterns first, best label first as the library orders them;
      // the old ones stay behind as fallbacks.
      final repaired = <ExtractorPattern>[
        ...working,
        for (final old in patterns)
          if (!working.any((w) => w.pattern == old.pattern) &&
              simulateBreak != site.name)
            old,
      ].take(maxPatternsPerPlatform).toList();

      catalogs[site.name] = [
        for (final p in repaired) {'pattern': p.pattern, 'label': p.label},
      ];
      result.adoptedPatterns.addAll(working.map((p) => p.pattern));
      result.status = 'repaired';
      changed = true;
    }

    if (changed) {
      final version =
          (extractors['version'] is int ? extractors['version']! as int : 0) +
          1;
      extractors['version'] = version;
      report.version = version;
      final body = const JsonEncoder.withIndent('  ').convert(extractors);
      if (simulateBreak.isEmpty) {
        extractorsFile.writeAsStringSync('$body\n');
        report.configChanged = true;
      } else {
        // A drill never touches the real config; the result is left beside
        // the report so it can be inspected.
        File('$outDir/extractors.simulated.json').writeAsStringSync('$body\n');
      }
    }

    File('$outDir/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
    File('$outDir/report.md').writeAsStringSync(report.toMarkdown());
    stdout.writeln(report.toMarkdown());
    _client.close(force: true);
    return report;
  }

  static List<ExtractorPattern> _patternsOf(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(ExtractorPattern.fromJson).nonNulls.toList();
  }

  Future<List<Page>> _fetchPages(Site site, Uri link) async {
    final pages = <Page>[];
    for (final route in site.routes) {
      final target = route.embed ? site.embedUrl(link) : link;
      if (target == null) continue;
      try {
        final page = await PageFetcher.fetch(
          _client,
          target,
          headers: {HttpHeaders.userAgentHeader: route.agent},
          maxBytes: 2 * 1024 * 1024,
        ).timeout(const Duration(seconds: 40));
        final html = page.html;
        if (html != null && page.refusal == null) {
          pages.add(Page(route, page.url, html, page.cookieHeader));
        }
      } catch (_) {
        // A route that fails is one client's view; the others still count.
      }
    }
    return pages;
  }

  void _savePages(Site site, List<Page> pages) {
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      File(
        '$outDir/pages/${site.name}-${page.route.key}-$index.html',
      ).writeAsStringSync(page.html);
    }
  }

  /// The patterns that find, in at least one page, an address that really
  /// serves media when fetched the way the app fetches it.
  Future<List<ExtractorPattern>> _livePatterns(
    Site site,
    List<Page> pages,
    List<ExtractorPattern> patterns,
  ) async {
    final live = <ExtractorPattern>[];
    final verified = <Uri, bool>{};

    for (final pattern in patterns) {
      final regExp = RegExp(pattern.pattern, caseSensitive: false);
      var works = false;
      for (final page in pages) {
        for (final match in regExp.allMatches(page.html).take(3)) {
          final url = _absolute(match.group(1), page.url);
          if (url == null || MediaFormats.isManifest(url)) continue;
          final ok = verified[url] ??= await _servesMedia(
            site,
            url,
            page.cookieHeader,
          );
          if (ok) {
            works = true;
            break;
          }
        }
        if (works) break;
      }
      if (works) live.add(pattern);
    }
    return live;
  }

  Future<bool> _servesMedia(Site site, Uri url, String? cookies) async {
    try {
      final probe = await MediaProbe.of(
        _client,
        url,
        headers: {
          ...BrowserProfile.mediaHeaders(referer: site.referer),
          HttpHeaders.cookieHeader: ?cookies,
        },
        expectMedia: true,
      ).timeout(const Duration(seconds: 25));
      return probe.isSuccess &&
          MediaFormats.isMediaContentType(probe.contentType);
    } catch (_) {
      return false;
    }
  }

  /// A captured address made absolute, with the JSON escaping these pages
  /// wrap it in undone — the same clean-up the provider does.
  static Uri? _absolute(String? raw, Uri pageUrl) {
    if (raw == null || raw.isEmpty || raw.length > 2048) return null;
    var text = raw;
    for (var layer = 0; layer < 3 && text.contains(r'\'); layer++) {
      text = text
          .replaceAllMapped(
            RegExp(r'\\u([0-9a-fA-F]{4})'),
            (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
          )
          .replaceAll(r'\/', '/')
          .replaceAll(r'\\', r'\');
    }
    text = text.replaceAll('&amp;', '&');
    final parsed = Uri.tryParse(text);
    if (parsed == null) return null;
    final resolved = parsed.hasScheme ? parsed : pageUrl.resolveUri(parsed);
    if (resolved.scheme != 'https' && resolved.scheme != 'http') return null;
    return resolved;
  }
}
