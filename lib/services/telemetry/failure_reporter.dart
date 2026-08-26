import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_info.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/platform_names.dart';
import '../../features/downloader/domain/download_engine.dart';
import '../../features/downloader/domain/source_provider.dart';
import '../config/remote_config.dart';
import '../networking/http_client_provider.dart';

/// Counts what went right and wrong per platform, and posts the counts.
///
/// The point is to learn that Instagram broke for everyone at 3 pm, not
/// what anyone downloaded: an event carries the platform's name, the kind of
/// outcome, the app version and the Android version — never a URL, a title,
/// a file name or anything that identifies the phone. Events are batched and
/// sent quietly; a server that is down costs nothing but the batch.
class FailureReporter {
  FailureReporter(this._client, {required Uri endpoint})
    // ignore: prefer_initializing_formals
    : _endpoint = endpoint {
    _flushTimer = Timer.periodic(_flushEvery, (_) => unawaited(flush()));
  }

  final HttpClient _client;
  final Uri _endpoint;

  static const Duration _flushEvery = Duration(seconds: 60);
  static const Duration _timeout = Duration(seconds: 10);
  static const int _flushAt = 20;
  static const int _keepAtMost = 100;

  final List<Map<String, Object?>> _pending = [];
  Timer? _flushTimer;
  bool _sending = false;

  void resolved(Uri url, String provider) =>
      _add('resolved', PlatformNames.of(url), provider: provider);

  void refused(Uri url, String provider, UnsupportedSource refusal) => _add(
    'refused',
    PlatformNames.of(url),
    provider: provider,
    reason: refusal.reason.name,
  );

  void downloadFailed(Uri url, DownloadErrorKind kind) =>
      _add('download_failed', PlatformNames.of(url), reason: kind.name);

  void downloadCompleted(Uri url) =>
      _add('download_completed', PlatformNames.of(url));

  void _add(String event, String platform, {String? provider, String? reason}) {
    _pending.add({
      'event': event,
      'platform': platform,
      'provider': ?provider,
      'reason': ?reason,
      'app': AppInfo.version,
      'os': Platform.operatingSystemVersion,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    // The oldest go first: a burst of failures is what matters, not history.
    while (_pending.length > _keepAtMost) {
      _pending.removeAt(0);
    }
    if (_pending.length >= _flushAt) unawaited(flush());
  }

  Future<void> flush() async {
    if (_sending || _pending.isEmpty) return;
    _sending = true;
    final batch = List<Map<String, Object?>>.from(_pending);
    try {
      final request = await _client.postUrl(_endpoint).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'events': batch}));
      final response = await request.close().timeout(_timeout);
      await response.drain<void>();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _pending.removeRange(0, batch.length.clamp(0, _pending.length));
      }
    } on TimeoutException {
      // Kept for the next flush.
    } on IOException catch (error) {
      AppLog.warn('Telemetry', error.runtimeType);
    } finally {
      _sending = false;
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}

/// Null until the remote config names a place to send events to.
final failureReporterProvider = Provider<FailureReporter?>((ref) {
  final endpoint = ref.watch(
    remoteConfigProvider.select((config) => config.telemetryUrl),
  );
  if (endpoint == null) return null;
  final reporter = FailureReporter(
    ref.watch(httpClientProvider),
    endpoint: endpoint,
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});
