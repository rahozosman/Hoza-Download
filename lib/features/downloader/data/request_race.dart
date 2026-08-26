import 'dart:async';
import 'dart:io';

import '../../../services/networking/http_client_provider.dart';
import 'request_profiles.dart';

/// How a raced request ended.
sealed class RaceOutcome {
  const RaceOutcome();
}

/// A server actually served the file.
class RaceWon extends RaceOutcome {
  const RaceWon({required this.response, required this.profile});

  final HttpClientResponse response;

  /// The way of asking that worked, so the caller can keep using it.
  final RequestProfile profile;
}

/// Every attempt got an answer and none of them was the file.
class RaceRefused extends RaceOutcome {
  const RaceRefused(this.statusCode);

  /// The clearest of the refusals — a "gone" says more than a "forbidden".
  final int statusCode;
}

/// No attempt got an answer at all: the network, not the server.
class RaceErrored extends RaceOutcome {
  const RaceErrored(this.error);

  final Object error;
}

/// Asks one server several ways at once and keeps the answer that works.
///
/// A refusal is usually about *how* the file was asked for, not whether it can
/// be had: the same CDN that turns away a bare client serves the file to a
/// request shaped like the browser it was published for. Trying those shapes
/// one after another costs a round trip each and usually times out before it
/// finds the one that works, so they all go out together and the first real
/// answer wins.
///
/// Losing attempts are dropped the moment their headers arrive, before their
/// body is read, so the extra attempts cost a connection each and no
/// meaningful bandwidth.
abstract final class RequestRace {
  /// How many ways are asked at once. Enough to cover the shapes servers
  /// actually want, few enough that it never reads as hammering the host.
  static const int maxAttempts = 4;

  static Future<RaceOutcome> open(
    HttpClient client,
    Uri url, {
    required List<RequestProfile> profiles,
    String? range,
    bool expectMedia = true,
    Duration timeout = NetworkTimeouts.connect,
  }) async {
    final candidates = profiles.take(maxAttempts).toList();
    if (candidates.isEmpty) {
      return const RaceErrored(
        HttpException('There is no way to ask for this file.'),
      );
    }

    final settled = Completer<RaceOutcome>();
    final attempts = <_Attempt>[];
    final refusals = <int>[];
    Object? failure;
    var pending = candidates.length;

    void settleIfDone() {
      if (settled.isCompleted || pending > 0) return;
      settled.complete(
        refusals.isEmpty
            ? RaceErrored(
                failure ?? const HttpException('The server did not answer.'),
              )
            : RaceRefused(_clearest(refusals)),
      );
    }

    for (final profile in candidates) {
      final attempt = _Attempt(profile);
      attempts.add(attempt);

      unawaited(
        attempt
            .run(
              client,
              url,
              range: range,
              expectMedia: expectMedia,
              timeout: timeout,
            )
            .then((outcome) async {
              switch (outcome) {
                case RaceWon():
                  // A second winner is one attempt too many; let it go.
                  if (settled.isCompleted) {
                    await discard(outcome.response);
                  } else {
                    attempt.won = true;
                    settled.complete(outcome);
                  }
                case RaceRefused(:final statusCode):
                  refusals.add(statusCode);
                case RaceErrored(:final error):
                  failure ??= error;
              }
            })
            .whenComplete(() {
              pending--;
              settleIfDone();
            }),
      );
    }

    final outcome = await settled.future;
    for (final attempt in attempts) {
      attempt.abandon();
    }
    return outcome;
  }

  /// Closes a response without reading its body.
  static Future<void> discard(HttpClientResponse response) async {
    try {
      await response.listen(null, cancelOnError: true).cancel();
    } catch (_) {
      // The connection is being thrown away; how it ends does not matter.
    }
  }

  /// Whether this response is the file rather than something about the file.
  static bool _servesFile(HttpClientResponse response, bool expectMedia) {
    final status = response.statusCode;
    if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
      return false;
    }
    if (!expectMedia) return true;

    // A block, consent or login page answers 200 with markup: a refusal
    // wearing a success. Another way of asking may still be served the file.
    final type = response.headers.contentType?.mimeType.toLowerCase();
    if (type == null) return true;
    return !type.startsWith('text/') &&
        type != 'application/json' &&
        type != 'application/xhtml+xml';
  }

  /// The refusal worth reporting. A range the server cannot satisfy has to
  /// surface because it means the partial on disk is stale, and "gone" tells
  /// the user more than "forbidden".
  static int _clearest(List<int> codes) {
    for (final code in codes) {
      if (code == HttpStatus.requestedRangeNotSatisfiable) return code;
    }
    for (final code in codes) {
      if (code == HttpStatus.notFound || code == HttpStatus.gone) return code;
    }
    return codes.first;
  }
}

class _Attempt {
  _Attempt(this.profile);

  final RequestProfile profile;

  HttpClientRequest? _request;
  HttpClientResponse? _response;

  /// Set on the attempt whose response the caller kept.
  bool won = false;
  bool _abandoned = false;

  Future<RaceOutcome> run(
    HttpClient client,
    Uri url, {
    required String? range,
    required bool expectMedia,
    required Duration timeout,
  }) async {
    try {
      final request = await client.getUrl(url);
      _request = request;
      if (_abandoned) {
        request.abort();
        return const RaceErrored(_Abandoned());
      }

      request.followRedirects = true;
      request.maxRedirects = 5;
      profile.headers.forEach(request.headers.set);
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);

      final response = await request.close().timeout(timeout);
      _response = response;
      if (_abandoned) {
        await RequestRace.discard(response);
        return const RaceErrored(_Abandoned());
      }

      if (RequestRace._servesFile(response, expectMedia)) {
        return RaceWon(response: response, profile: profile);
      }

      final status = response.statusCode;
      await RequestRace.discard(response);
      return RaceRefused(status);
    } catch (error) {
      return RaceErrored(error);
    }
  }

  /// Drops this attempt, whatever stage it reached. Never touches a winner.
  void abandon() {
    if (won || _abandoned) return;
    _abandoned = true;

    final response = _response;
    if (response != null) {
      unawaited(RequestRace.discard(response));
      return;
    }
    try {
      _request?.abort();
    } catch (_) {
      // Aborting a request that already finished is not a problem.
    }
  }
}

/// Marks an attempt the caller stopped caring about. Never surfaces: by the
/// time attempts are abandoned the race already has its outcome.
class _Abandoned implements Exception {
  const _Abandoned();

  @override
  String toString() => 'Attempt abandoned';
}
