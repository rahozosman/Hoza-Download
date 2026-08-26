import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/config/remote_config.dart';
import '../../../services/networking/http_client_provider.dart';
import '../../../services/telemetry/failure_reporter.dart';
import '../domain/source_provider.dart';
import 'link_canonicalizer.dart';
import 'providers/direct_media_provider.dart';
import 'providers/page_media_provider.dart';
import 'providers/social_media_provider.dart';
import 'providers/youtube_provider.dart';
import 'resolvers/endpoint_health.dart';

/// Routes a link through every provider that claims it, best first.
///
/// The link is first brought to its canonical form — short links expanded,
/// tracking stripped — so the provider that claims it sees the post's real
/// address. The first provider to claim a link is the specialist for it, so
/// it goes first — but it is not the only chance the link gets. A provider
/// that could not read the link hands over to the next one that claims it,
/// which is what turns a single backend having a bad day into a slower lookup
/// rather than a failed one. A link no provider claims resolves to
/// [UnsupportedReason.noProvider], and the UI says so plainly rather than
/// guessing.
///
/// Answers are remembered for a few minutes: the same link is very often
/// shared twice in a row — share, cancel, share again — and the second sheet
/// should open at once rather than read the page all over again.
class SourceRegistry {
  SourceRegistry(
    this.providers, {
    required HttpClient client,
    RemoteConfig? config,
    FailureReporter? reporter,
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _config = config,
       // ignore: prefer_initializing_formals
       _reporter = reporter;

  final List<SourceProvider> providers;
  final HttpClient _client;
  final RemoteConfig? _config;
  final FailureReporter? _reporter;

  /// Whole-lookup budget, however many providers the chain ends up asking.
  ///
  /// The sheet can never spin forever, so the chain shares one deadline
  /// instead of each provider getting its own.
  static const Duration lookupTimeout = Duration(seconds: 45);

  /// Longest any single provider may hold the chain up.
  ///
  /// A platform lookup is more than one round trip — the page, then the media
  /// it names — so this is longer than a single request's budget, and short
  /// enough that one slow provider still leaves time for the next.
  static const Duration providerTimeout = Duration(seconds: 25);

  /// Below this there is no point starting another provider; the remaining
  /// time would run out mid-request and report a timeout either way.
  static const Duration _minimumSlice = Duration(seconds: 3);

  /// How long a resolved answer stays good for. Shorter than any CDN
  /// signature, so a cached address is never handed out already expired.
  static const Duration cacheFor = Duration(minutes: 10);

  static const int _maxCached = 32;

  final Map<String, _CachedResolution> _cache = {};

  SourceProvider? providerFor(Uri url) {
    for (final provider in providers) {
      if (provider.canHandle(url)) return provider;
    }
    return null;
  }

  /// Reads what the sources publish for [url].
  ///
  /// [fresh] skips the cache — for a retry, or for a download whose address
  /// has expired and needs a new one. [cancel] stops the chain between
  /// providers once nobody is waiting for the answer.
  Future<SourceResolution> resolve(
    Uri url, {
    bool fresh = false,
    LookupCancel? cancel,
  }) async {
    final canonical = await LinkCanonicalizer.canonical(_client, url);
    if (cancel?.isCancelled ?? false) {
      return const UnsupportedSource(UnsupportedReason.lookupFailed);
    }

    final key = canonical.toString();
    if (!fresh) {
      final cached = _cache[key];
      if (cached != null && !cached.isStale) return cached.resolution;
    }
    _cache.remove(key);

    final result = await _resolveUncached(canonical, cancel);
    if (result is ResolvedMedia) {
      _remember(key, result);
    }
    return result;
  }

  /// Forgets everything remembered, e.g. after the extractor catalog changed.
  void clearCache() => _cache.clear();

  void _remember(String key, ResolvedMedia resolution) {
    if (_cache.length >= _maxCached) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CachedResolution(resolution, DateTime.now().add(cacheFor));
  }

  Future<SourceResolution> _resolveUncached(
    Uri url,
    LookupCancel? cancel,
  ) async {
    // A platform switched off from the config answers for every provider:
    // the message says what is going on instead of a lookup that fails.
    final blocked = _config?.refusalFor(url);
    if (blocked != null) return blocked;

    final claimants = providers.where((p) => p.canHandle(url)).toList();
    if (claimants.isEmpty) {
      return const UnsupportedSource(UnsupportedReason.noProvider);
    }

    final deadline = DateTime.now().add(lookupTimeout);

    // The specialist's answer is the one worth reporting: it knows what the
    // link is, where a later provider only knows it could not read a page.
    UnsupportedSource? firstRefusal;

    for (final provider in claimants) {
      if (cancel?.isCancelled ?? false) break;

      var slice = deadline.difference(DateTime.now());
      if (slice < _minimumSlice) break;
      if (slice > providerTimeout) slice = providerTimeout;

      final outcome = await _ask(provider, url, slice);
      switch (outcome) {
        case ResolvedMedia():
          _reporter?.resolved(url, provider.name);
          return outcome;
        case UnsupportedSource():
          firstRefusal ??= outcome;
          // A source that says the content is protected has answered for
          // every provider behind it. Asking the rest would only be a slower
          // way to arrive at the same no.
          if (outcome.reason == UnsupportedReason.restricted) {
            _reporter?.refused(url, provider.name, outcome);
            return outcome;
          }
      }
    }

    final refusal =
        firstRefusal ?? const UnsupportedSource(UnsupportedReason.lookupFailed);
    if (!(cancel?.isCancelled ?? false)) {
      _reporter?.refused(url, claimants.first.name, refusal);
    }
    return refusal;
  }

  Future<SourceResolution> _ask(
    SourceProvider provider,
    Uri url,
    Duration timeout,
  ) async {
    try {
      return await provider.resolve(url, timeout: timeout).timeout(timeout);
    } catch (_) {
      // Providers are expected to translate their own failures; anything that
      // escapes is still surfaced as a retryable lookup failure, never a
      // crash, and never the end of the chain.
      return const UnsupportedSource(UnsupportedReason.lookupFailed);
    }
  }
}

class _CachedResolution {
  const _CachedResolution(this.resolution, this.until);

  final ResolvedMedia resolution;
  final DateTime until;

  bool get isStale => DateTime.now().isAfter(until);
}

final sourceRegistryProvider = Provider<SourceRegistry>((ref) {
  final client = ref.watch(httpClientProvider);
  final health = ref.watch(endpointHealthProvider);
  final config = ref.watch(remoteConfigProvider);
  final reporter = ref.watch(failureReporterProvider);

  return SourceRegistry(
    <SourceProvider>[
      // Most specific first. Each platform provider knows where its own media
      // lives; the direct-file provider is the cheap path for a link that
      // already names a file, and the page provider claims everything else —
      // which also makes it the last resort for a link a specialist could not
      // read.
      YoutubeProvider(client, health),
      SocialMediaProvider(client, health, catalog: config.extractors),
      DirectMediaProvider(client),
      PageMediaProvider(client),
    ],
    client: client,
    config: config,
    reporter: reporter,
  );
});
