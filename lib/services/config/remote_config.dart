import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_info.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/platform_names.dart';
import '../../data/database/hoza_database.dart';
import '../../features/downloader/domain/source_provider.dart';
import '../networking/http_client_provider.dart';

/// One place a platform leaves its media URL, as a pattern with a label.
class ExtractorPattern {
  const ExtractorPattern(this.pattern, this.label);

  final String pattern;
  final String label;

  static ExtractorPattern? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final pattern = raw['pattern'];
    final label = raw['label'];
    if (pattern is! String || pattern.isEmpty || pattern.length > 1024) {
      return null;
    }
    // A pattern that does not compile would take the whole provider down;
    // it is dropped here, once, rather than on every lookup.
    try {
      RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return null;
    }
    return ExtractorPattern(pattern, label is String ? label : 'Original');
  }
}

/// Where each platform keeps its video URLs, best quality first.
///
/// The built-in lists are what ships with the app; the remote config can
/// replace any platform's list the day the platform changes its markup, so
/// the fix reaches phones without a store release.
class ExtractorCatalog {
  const ExtractorCatalog(this._video);

  final Map<String, List<ExtractorPattern>> _video;

  static const ExtractorCatalog builtIn = ExtractorCatalog({
    // TikTok hydrates its player from a JSON blob in the page. `playAddr` is
    // the file the site itself plays; `downloadAddr` is the one its own
    // "Save video" hands out, which carries the TikTok watermark. Only the
    // player's own address list is read: a slideshow's pictures come with
    // `urlList`s of their own, and those are photos, not renditions.
    PlatformNames.tiktok: [
      ExtractorPattern(r'"playAddr"\s*:\s*"([^"]+)"', 'Original'),
      ExtractorPattern(r'"downloadAddr"\s*:\s*"([^"]+)"', 'With watermark'),
      ExtractorPattern(
        r'"PlayAddr"\s*:\s*\{[^{}]{0,300}?"UrlList"\s*:\s*\[\s*"([^"]+)"',
        'Alternate',
      ),
    ],
    // Instagram publishes the file in its hydration JSON, and in the Open
    // Graph tags it serves for link previews. The embed page keeps the same
    // key inside a JSON string, quotes escaped, which the first pattern also
    // reads.
    PlatformNames.instagram: [
      ExtractorPattern(r'"video_url\\?"\s*:\s*\\?"([^"]+?)\\?"', 'Original'),
      ExtractorPattern(
        r'"video_versions".{0,200}?"url"\s*:\s*"([^"]+)"',
        'Original',
      ),
    ],
    // Facebook names its qualities in the page JSON, HD first.
    PlatformNames.facebook: [
      ExtractorPattern(r'"browser_native_hd_url"\s*:\s*"([^"]+)"', 'HD'),
      ExtractorPattern(r'"playable_url_quality_hd"\s*:\s*"([^"]+)"', 'HD'),
      ExtractorPattern(r'"hd_src"\s*:\s*"([^"]+)"', 'HD'),
      ExtractorPattern(r'"browser_native_sd_url"\s*:\s*"([^"]+)"', 'SD'),
      ExtractorPattern(r'"playable_url"\s*:\s*"([^"]+)"', 'SD'),
      ExtractorPattern(r'"sd_src"\s*:\s*"([^"]+)"', 'SD'),
    ],
  });

  /// The video patterns for [platform]: the remote list when the config has
  /// one, otherwise what shipped with the app.
  List<ExtractorPattern> videoFor(String platform) =>
      _video[platform] ?? builtIn._video[platform] ?? const [];

  static ExtractorCatalog fromJson(Object? raw) {
    if (raw is! Map) return builtIn;
    final video = <String, List<ExtractorPattern>>{};
    raw.forEach((platform, patterns) {
      if (platform is! String || patterns is! List) return;
      final parsed = patterns.map(ExtractorPattern.fromJson).nonNulls.toList();
      // An empty remote list means "keep the built-in ones", never "none".
      if (parsed.isNotEmpty) video[platform] = parsed;
    });
    return ExtractorCatalog(video);
  }
}

/// Whether a platform is switched on, and what to tell the user when not.
class PlatformSwitch {
  const PlatformSwitch({required this.enabled, this.message});

  final bool enabled;
  final String? message;

  static PlatformSwitch? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final enabled = raw['enabled'];
    final message = raw['message'];
    return PlatformSwitch(
      enabled: enabled is bool ? enabled : true,
      message: message is String && message.isNotEmpty ? message : null,
    );
  }
}

/// What the server tells the app about the world it is running in.
///
/// Everything here has a built-in default, so the app behaves the same
/// whether the config was fetched, cached from a previous run, or never
/// reachable at all. The config can only ever narrow or redirect — switch a
/// platform off with a message, swap extractor patterns, point the probes at
/// a different host — never make the app do something new.
class RemoteConfig {
  const RemoteConfig({
    this.version = 0,
    this.platforms = const {},
    this.extractors = ExtractorCatalog.builtIn,
    this.pingUrl,
    this.telemetryUrl,
    this.resolveUrl,
    this.minAppVersion,
    this.updateMessage,
  });

  static const RemoteConfig builtIn = RemoteConfig();

  final int version;

  /// Kill switches per platform, keyed by [PlatformNames].
  final Map<String, PlatformSwitch> platforms;

  final ExtractorCatalog extractors;

  /// An address that answers `204` — used to tell a working network from
  /// one Android merely believes in. Null means the public check is used.
  final Uri? pingUrl;

  /// Where anonymous failure counts are posted. Null means nowhere.
  final Uri? telemetryUrl;

  /// A server-side resolver to ask when the phone itself cannot read a
  /// link. Null means the app relies on itself.
  final Uri? resolveUrl;

  /// Below this version the app is told to update. Null means no floor.
  final String? minAppVersion;
  final String? updateMessage;

  /// Why a link on a switched-off platform is refused, or null when the
  /// platform is on.
  UnsupportedSource? refusalFor(Uri url) {
    final platform = platforms[PlatformNames.of(url)];
    if (platform == null || platform.enabled) return null;
    return UnsupportedSource(
      UnsupportedReason.noDownloadableVariant,
      detail:
          platform.message ??
          'This site is temporarily unavailable in Hoza. Please try again '
              'later.',
    );
  }

  /// Whether this app build is older than the config allows.
  bool get isOutdated {
    final floor = minAppVersion;
    if (floor == null) return false;
    return _compareVersions(AppInfo.version, floor) < 0;
  }

  static RemoteConfig fromJson(Map<String, Object?> json) {
    final platforms = <String, PlatformSwitch>{};
    final rawPlatforms = json['platforms'];
    if (rawPlatforms is Map) {
      rawPlatforms.forEach((name, value) {
        final parsed = PlatformSwitch.fromJson(value);
        if (name is String && parsed != null) platforms[name] = parsed;
      });
    }
    return RemoteConfig(
      version: json['version'] is int ? json['version']! as int : 0,
      platforms: platforms,
      extractors: ExtractorCatalog.fromJson(json['extractors']),
      pingUrl: _https(json['pingUrl']),
      telemetryUrl: _https(json['telemetryUrl']),
      resolveUrl: _https(json['resolveUrl']),
      minAppVersion: json['minAppVersion'] is String
          ? json['minAppVersion']! as String
          : null,
      updateMessage: json['updateMessage'] is String
          ? json['updateMessage']! as String
          : null,
    );
  }

  /// Only https addresses are accepted from the config: it may redirect
  /// probes and telemetry, but never onto a plain-text channel.
  static Uri? _https(Object? raw) {
    if (raw is! String) return null;
    final url = Uri.tryParse(raw);
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return null;
    return url;
  }

  static int _compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final left = parts(a);
    final right = parts(b);
    for (var i = 0; i < 3; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }
}

/// Fetches the config and keeps the last good copy on disk.
///
/// Order of trust: the copy cached from the last run first (so a platform
/// switched off yesterday stays off on a flight today), then the network,
/// asked with the cached `ETag` so an unchanged file costs one round trip and
/// no body. Anything malformed is ignored and the previous copy kept.
class RemoteConfigController extends Notifier<RemoteConfig> {
  static const Duration _refreshAfter = Duration(hours: 24);
  static const Duration _timeout = Duration(seconds: 10);

  static const String _keyBody = 'remote_config.body';
  static const String _keyEtag = 'remote_config.etag';
  static const String _keyFetchedAt = 'remote_config.fetched_at';

  @override
  RemoteConfig build() {
    if (AppInfo.remoteConfigUrl.isNotEmpty) {
      unawaited(_load());
    }
    return RemoteConfig.builtIn;
  }

  Future<void> _load() async {
    Database? db;
    try {
      db = ref.read(databaseProvider);
    } catch (_) {
      // No database in this context (tests); the network copy still counts.
    }

    String? etag;
    DateTime? fetchedAt;
    if (db != null) {
      final cached = await _readCache(db);
      etag = cached.etag;
      fetchedAt = cached.fetchedAt;
      final body = cached.body;
      if (body != null) _applyBody(body, from: 'cache');
    }

    final fresh =
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _refreshAfter;
    if (fresh) return;

    await _fetch(db, etag: etag);
  }

  Future<void> _fetch(Database? db, {String? etag}) async {
    final url = Uri.tryParse(AppInfo.remoteConfigUrl);
    if (url == null || url.scheme != 'https') return;

    try {
      final client = ref.read(httpClientProvider);
      final request = await client.getUrl(url).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        '${AppInfo.name.replaceAll(' ', '')}/${AppInfo.version}',
      );
      // The shared client leaves bodies compressed — right for media, wrong
      // for a text file. Ask for it plain, and unpack it below if the host
      // compresses anyway, as GitHub does; decoding gzip as text throws.
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (etag != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(_timeout);

      if (response.statusCode == HttpStatus.notModified) {
        await response.drain<void>();
        if (db != null) await _touch(db);
        return;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        AppLog.warn('Remote config', 'HTTP ${response.statusCode}');
        return;
      }

      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add).timeout(_timeout);
      List<int> bytes = builder.takeBytes();
      if (bytes.length > 256 * 1024) return;
      final encoding =
          (response.headers.value(HttpHeaders.contentEncodingHeader) ?? '')
              .toLowerCase();
      if (encoding.contains('gzip')) bytes = gzip.decode(bytes);
      final body = utf8.decode(bytes);
      if (body.length > 256 * 1024) return;
      if (!_applyBody(body, from: 'network')) return;

      if (db != null) {
        await _writeCache(
          db,
          body: body,
          etag: response.headers.value(HttpHeaders.etagHeader),
        );
      }
    } on TimeoutException {
      AppLog.warn('Remote config', 'timed out');
    } on IOException catch (error) {
      AppLog.warn('Remote config', error.runtimeType);
    } on FormatException {
      // Not text, or not the compression it claimed: the previous copy stays.
      AppLog.warn('Remote config', 'unreadable body');
    }
  }

  /// Parses and adopts [body]. Returns false — and changes nothing — when it
  /// is not a config.
  bool _applyBody(String body, {required String from}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) return false;
      final config = RemoteConfig.fromJson(decoded);
      state = config;
      AppLog.warn('Remote config', 'v${config.version} from $from');
      return true;
    } on FormatException {
      AppLog.warn('Remote config', 'malformed body from $from');
      return false;
    }
  }

  Future<({String? body, String? etag, DateTime? fetchedAt})> _readCache(
    Database db,
  ) async {
    try {
      final rows = await db.query(
        HozaDatabase.preferencesTable,
        where: '${HozaDatabase.preferenceKey} IN (?, ?, ?)',
        whereArgs: [_keyBody, _keyEtag, _keyFetchedAt],
      );
      final values = {
        for (final row in rows)
          row[HozaDatabase.preferenceKey] as String:
              row[HozaDatabase.preferenceValue] as String,
      };
      final at = int.tryParse(values[_keyFetchedAt] ?? '');
      return (
        body: values[_keyBody],
        etag: values[_keyEtag],
        fetchedAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      );
    } catch (error) {
      AppLog.warn('Remote config cache', error);
      return (body: null, etag: null, fetchedAt: null);
    }
  }

  Future<void> _writeCache(
    Database db, {
    required String body,
    String? etag,
  }) async {
    try {
      final batch = db.batch();
      void put(String key, String? value) {
        if (value == null) {
          batch.delete(
            HozaDatabase.preferencesTable,
            where: '${HozaDatabase.preferenceKey} = ?',
            whereArgs: [key],
          );
        } else {
          batch.insert(
            HozaDatabase.preferencesTable,
            {
              HozaDatabase.preferenceKey: key,
              HozaDatabase.preferenceValue: value,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      put(_keyBody, body);
      put(_keyEtag, etag);
      put(_keyFetchedAt, '${DateTime.now().millisecondsSinceEpoch}');
      await batch.commit(noResult: true);
    } catch (error) {
      AppLog.warn('Remote config cache', error);
    }
  }

  Future<void> _touch(Database db) async {
    try {
      await db.insert(
        HozaDatabase.preferencesTable,
        {
          HozaDatabase.preferenceKey: _keyFetchedAt,
          HozaDatabase.preferenceValue:
              '${DateTime.now().millisecondsSinceEpoch}',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Only the refresh clock; nothing lost.
    }
  }
}

final remoteConfigProvider =
    NotifierProvider<RemoteConfigController, RemoteConfig>(
      RemoteConfigController.new,
    );
