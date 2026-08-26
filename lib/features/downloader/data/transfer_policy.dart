/// What a media host will and will not serve, learned by asking it.
///
/// Most hosts hand over a whole file to a plain `GET`. YouTube's media servers
/// (`*.googlevideo.com`) do not: they answer a request with no `Range`, or an
/// open-ended one, with `403` for any stream longer than a few seconds, and
/// only serve bounded ranges — the shape their own players send. Verified on
/// 2026-08-26 against both the Android and iOS player endpoints: `bytes=0-`
/// and no range were refused; `bytes=0-N` was served for every N up to 10 MiB.
///
/// So a transfer from such a host is made as a sequence of bounded range
/// requests on one connection, each well inside the served size.
abstract final class TransferPolicy {
  /// Largest single request made to a host that only serves bounded ranges.
  ///
  /// Well under the 10 MiB that was observed to be served, because the limit
  /// is the host's to change, and a request that is refused costs the whole
  /// download rather than one round trip.
  static const int boundedRequestBytes = 4 * 1024 * 1024;

  /// The most one request to [url] may ask for, or null when the host serves
  /// whole files and the ordinary single-request transfer applies.
  static int? maxRequestBytes(Uri url) =>
      _requiresBoundedRanges(url) ? boundedRequestBytes : null;

  static bool _requiresBoundedRanges(Uri url) {
    final host = url.host.toLowerCase();
    return host == 'googlevideo.com' || host.endsWith('.googlevideo.com');
  }
}
