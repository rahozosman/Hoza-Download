import 'package:flutter/foundation.dart';

/// Development logging.
///
/// Silent in release builds: diagnostics help while building the app, but a
/// shipped binary should not narrate itself into logcat. Nothing here ever
/// receives a URL, file path, token or other user data — messages name the
/// operation and the failure category only.
abstract final class AppLog {
  /// A recoverable problem worth knowing about while developing.
  static void warn(String operation, Object? detail) {
    if (kReleaseMode) return;
    debugPrint('[Hoza] $operation${detail == null ? '' : ': $detail'}');
  }

  /// A failure that changed what the user sees.
  static void error(String operation, Object error, [StackTrace? stack]) {
    if (kReleaseMode) return;
    debugPrint('[Hoza] $operation failed: $error');
    if (stack != null) debugPrintStack(stackTrace: stack);
  }
}
