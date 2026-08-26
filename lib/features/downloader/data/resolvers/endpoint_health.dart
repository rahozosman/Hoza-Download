import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Remembers how each backend has been behaving, so a fleet asks the servers
/// that are answering before the ones that are not.
///
/// No backend is ever struck off. One that failed is pushed to the back of the
/// queue and left alone for a while, which is the difference between a lookup
/// that spends its whole budget on a dead host and one that reaches a working
/// host on the first try. Nothing is persisted: which server is healthy is a
/// fact about the last few minutes, not about the device.
class EndpointHealth {
  final Map<String, _Endpoint> _endpoints = HashMap<String, _Endpoint>();

  /// How long a backend is left alone after failing once. Doubles with each
  /// consecutive failure, so a host that is down stops costing round trips.
  static const Duration _restAfterFailure = Duration(seconds: 20);
  static const Duration _maxRest = Duration(minutes: 8);

  /// Failures past this point no longer lengthen the rest.
  static const int _maxBackoffSteps = 5;

  /// Score given to a backend nothing is known about: ahead of the slow and
  /// the failing, behind one that has recently answered quickly.
  static const int _unknownScore = 20;

  /// Whether this backend is currently being left alone.
  bool isResting(String key) {
    final until = _endpoints[key]?.restingUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void recordSuccess(String key, Duration latency) {
    _endpoints[key] = _Endpoint(
      failures: 0,
      restingUntil: null,
      latencyMs: latency.inMilliseconds,
    );
  }

  void recordFailure(String key) {
    final current = _endpoints[key];
    final failures = (current?.failures ?? 0) + 1;
    final steps = failures.clamp(1, _maxBackoffSteps);
    var rest = _restAfterFailure * (1 << (steps - 1));
    if (rest > _maxRest) rest = _maxRest;

    _endpoints[key] = _Endpoint(
      failures: failures,
      restingUntil: DateTime.now().add(rest),
      latencyMs: current?.latencyMs,
    );
  }

  /// [candidates] reordered best first: the quick and recently-answering lead,
  /// the resting go last.
  ///
  /// Declaration order breaks every tie, so a fleet with no history is asked
  /// in exactly the order its author wrote it.
  List<T> order<T>(List<T> candidates, String Function(T) keyOf) {
    final ranked =
        <_Ranked<T>>[
          for (var index = 0; index < candidates.length; index++)
            _Ranked(
              candidates[index],
              index,
              _scoreOf(keyOf(candidates[index])),
            ),
        ]..sort((a, b) {
          final byScore = a.score.compareTo(b.score);
          return byScore != 0 ? byScore : a.index.compareTo(b.index);
        });

    return [for (final entry in ranked) entry.value];
  }

  int _scoreOf(String key) {
    final endpoint = _endpoints[key];
    if (endpoint == null) return _unknownScore;
    if (isResting(key)) return 1000000 + endpoint.failures;

    // Latency is deliberately coarse: a tenth of a second between two working
    // servers is noise, and reordering the fleet over it would throw away the
    // connection that is already warm.
    final latency = (endpoint.latencyMs ?? 1000) ~/ 100;
    return (latency > 19 ? 19 : latency) + endpoint.failures * 40;
  }
}

class _Endpoint {
  const _Endpoint({
    required this.failures,
    required this.restingUntil,
    required this.latencyMs,
  });

  /// Failures in a row. Reset by the first success.
  final int failures;

  /// When this backend may be asked again, or null when it is in good standing.
  final DateTime? restingUntil;

  /// How long the last successful answer took.
  final int? latencyMs;
}

class _Ranked<T> {
  const _Ranked(this.value, this.index, this.score);

  final T value;

  /// Position in the fleet as written, used only to break ties.
  final int index;

  final int score;
}

/// One health registry for the app, so what the sheet learned about a server
/// is still known when the next link is pasted.
final endpointHealthProvider = Provider<EndpointHealth>(
  (ref) => EndpointHealth(),
);
