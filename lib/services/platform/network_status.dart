import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';
import '../config/remote_config.dart';

/// What the device's connection looks like right now.
@immutable
class NetworkStatus {
  const NetworkStatus({
    required this.connected,
    required this.metered,
    this.captivePortal = false,
  });

  /// Assumed until the platform says otherwise — an unknown connection must
  /// never be treated as offline and block a download.
  static const NetworkStatus unknown = NetworkStatus(
    connected: true,
    metered: false,
  );

  final bool connected;

  /// True on mobile data and on hotspots the user marked as metered.
  final bool metered;

  /// The network answers, but with its own sign-in page: a hotel or airport
  /// Wi-Fi the user has not logged into yet. Nothing downloads until they do.
  final bool captivePortal;

  bool get isOffline => !connected;

  @override
  bool operator ==(Object other) =>
      other is NetworkStatus &&
      other.connected == connected &&
      other.metered == metered &&
      other.captivePortal == captivePortal;

  @override
  int get hashCode => Object.hash(connected, metered, captivePortal);

  static NetworkStatus fromPlatform(Object? raw) {
    if (raw is! Map) return unknown;
    return NetworkStatus(
      connected: raw['connected'] as bool? ?? true,
      metered: raw['metered'] as bool? ?? false,
    );
  }
}

/// Live connectivity, used for the offline state and the Wi-Fi-only preference.
class NetworkService {
  NetworkService({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel =
          methodChannel ?? const MethodChannel('com.hoza.download/network'),
      _eventChannel =
          eventChannel ??
          const EventChannel('com.hoza.download/network_events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<NetworkStatus> get changes =>
      _eventChannel.receiveBroadcastStream().map(NetworkStatus.fromPlatform);

  Future<NetworkStatus> current() async {
    try {
      final raw = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
        'status',
      );
      return NetworkStatus.fromPlatform(raw);
    } on PlatformException catch (error) {
      AppLog.warn('Reading network status', error.code);
      return NetworkStatus.unknown;
    } on MissingPluginException {
      return NetworkStatus.unknown;
    }
  }
}

final networkServiceProvider = Provider<NetworkService>(
  (ref) => NetworkService(),
);

/// The current connection, refreshed as the platform reports changes.
///
/// The platform's word is not the last word on being offline. Android can
/// call a connected phone disconnected — for a moment during a Wi-Fi to
/// mobile hand-over, or for longer behind a VPN or a restricted profile —
/// and a queue held on that verdict looks like an app that has stopped
/// working. So an offline verdict is checked against the network itself, by
/// resolving a name, and checked again every few seconds until one of the
/// two says the phone is online.
class NetworkStatusController extends Notifier<NetworkStatus> {
  StreamSubscription<NetworkStatus>? _subscription;
  Timer? _verification;
  bool _heardFromStream = false;

  /// What the platform last said, before any correction.
  NetworkStatus _reported = NetworkStatus.unknown;

  /// How many verifications in a row have found the network unusable. Drives
  /// the back-off so a phone that really is offline for an hour is not asked
  /// every five seconds.
  int _misses = 0;

  /// An address that answers `204 No Content` with no body. A `200` with a
  /// page instead means a captive portal has taken the request. Served over
  /// https so the app's cleartext policy does not get in the way.
  static const String _publicPing =
      'https://connectivitycheck.gstatic.com/generate_204';

  /// Fallback when the ping host itself is blocked: a name that resolves
  /// proves DNS works, which is nearly always a working network.
  static const List<String> _probeHosts = ['cloudflare.com', 'google.com'];

  static const Duration _probeTimeout = Duration(seconds: 4);
  static const List<Duration> _backoff = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 60),
  ];

  @override
  NetworkStatus build() {
    final service = ref.watch(networkServiceProvider);

    _subscription = service.changes.listen(
      (status) {
        _heardFromStream = true;
        _apply(status);
      },
      onError: (Object _) {
        // A broken stream must not strand the app in a stale offline state.
        _apply(NetworkStatus.unknown);
      },
    );
    ref.onDispose(() {
      _subscription?.cancel();
      _verification?.cancel();
    });

    unawaited(
      service.current().then((status) {
        // The stream may already have said something newer.
        if (!_heardFromStream) _apply(status);
      }),
    );
    return NetworkStatus.unknown;
  }

  void _apply(NetworkStatus reported) {
    _reported = reported;
    _misses = 0;
    _verification?.cancel();
    _verification = null;
    if (reported.connected) {
      state = reported;
      return;
    }
    // Offline according to the platform: say so only once the network agrees.
    unawaited(_verify());
  }

  Future<void> _verify() async {
    final reported = _reported;
    final verdict = await _probe();
    // The platform may have changed its mind while the probe was out.
    if (!identical(_reported, reported)) return;

    switch (verdict) {
      case _Probe.online:
        _misses = 0;
        // Online after all; the platform's metered flag is still the best
        // guess. Keep checking: the platform will not send an event for a
        // network it never noticed, so this is what notices it going away.
        state = NetworkStatus(connected: true, metered: reported.metered);
      case _Probe.captivePortal:
        _misses = 0;
        state = NetworkStatus(
          connected: false,
          metered: reported.metered,
          captivePortal: true,
        );
      case _Probe.offline:
        _misses++;
        state = reported;
    }
    _scheduleVerification();
  }

  /// The next look comes sooner while the picture is changing and later once
  /// it has settled, with a little jitter so many phones do not ask at once.
  void _scheduleVerification() {
    final step = _backoff[_misses.clamp(0, _backoff.length - 1)];
    final jitter = Duration(
      milliseconds: (step.inMilliseconds * 0.2 * Random().nextDouble()).round(),
    );
    _verification?.cancel();
    _verification = Timer(step + jitter, () => unawaited(_verify()));
  }

  Future<_Probe> _probe() async {
    final ping = await _ping(
      ref.read(remoteConfigProvider).pingUrl ?? Uri.parse(_publicPing),
    );
    if (ping != null) return ping;
    // The ping host is unreachable or blocked; DNS still tells online from
    // offline, though not a captive portal from either.
    return await _resolvesAnyHost() ? _Probe.online : _Probe.offline;
  }

  /// Null when the ping host could not be reached at all.
  Future<_Probe?> _ping(Uri url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _probeTimeout;
      final request = await client.getUrl(url).timeout(_probeTimeout);
      request.followRedirects = false;
      final response = await request.close().timeout(_probeTimeout);
      final status = response.statusCode;
      final type = (response.headers.contentType?.mimeType ?? '').toLowerCase();
      await response.drain<void>().timeout(_probeTimeout);

      if (status == HttpStatus.noContent) return _Probe.online;
      // A redirect or a page where a 204 was promised is the portal talking.
      if (status >= 300 && status < 400) return _Probe.captivePortal;
      if (status == HttpStatus.ok && type.contains('html')) {
        return _Probe.captivePortal;
      }
      return _Probe.online;
    } on TimeoutException {
      return null;
    } on IOException {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<bool> _resolvesAnyHost() async {
    for (final host in _probeHosts) {
      try {
        final addresses = await InternetAddress.lookup(
          host,
        ).timeout(_probeTimeout);
        if (addresses.isNotEmpty) return true;
      } on SocketException {
        // Try the next one.
      } on TimeoutException {
        // Try the next one.
      }
    }
    return false;
  }
}

enum _Probe { online, captivePortal, offline }

final networkStatusProvider =
    NotifierProvider<NetworkStatusController, NetworkStatus>(
      NetworkStatusController.new,
    );
