import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Timeouts applied to every outbound request.
///
/// Nothing in the app may wait indefinitely: a link check and a stalled
/// transfer both have to end in success or a message the user can act on.
abstract final class NetworkTimeouts {
  static const Duration connect = Duration(seconds: 15);
  static const Duration idle = Duration(seconds: 30);

  /// Whole-request budget for a metadata lookup.
  static const Duration metadata = Duration(seconds: 15);

  /// How long a transfer may go without receiving a byte before it is treated
  /// as stalled.
  static const Duration transferStall = Duration(seconds: 45);
}

/// One shared [HttpClient] for the app.
///
/// Reusing a client keeps connections alive between the metadata check and the
/// download that follows it, which makes the share flow feel instant.
final httpClientProvider = Provider<HttpClient>((ref) {
  final client = HttpClient()
    ..connectionTimeout = NetworkTimeouts.connect
    ..idleTimeout = NetworkTimeouts.idle
    // No default agent: every request sets its own. With a default in place,
    // Dart's redirect follower keeps the *default* on the redirected hop and
    // drops the agent the request asked for — so a page fetched as a link
    // crawler arrived at facebook.com's regional redirect as "HozaDownload",
    // and was refused with a 400. Requests that want the app's own agent use
    // [RequestProfiles] or say so themselves.
    ..userAgent = null
    // Media is already compressed, and transparent decompression would make
    // Content-Length disagree with the bytes actually written to disk.
    ..autoUncompress = false;

  ref.onDispose(() => client.close(force: true));
  return client;
});
