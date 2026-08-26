import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/constants/app_info.dart';
import '../../core/utils/app_log.dart';

/// Crash, freeze and uncaught-error reporting, through Sentry.
///
/// Switched on by building with a DSN:
///
///     flutter build apk --dart-define=SENTRY_DSN=https://...@sentry.io/...
///
/// Without one — every local run and build until then — nothing is
/// initialised and nothing leaves the phone. With one, each report carries
/// what is needed to find the fault and no more: the stack trace, the app and
/// Android versions, the screen the user was on, and whether the UI thread
/// was stuck (an ANR). No link, title, file name or account is ever attached.
abstract final class CrashReporting {
  /// Set at build time; empty means off.
  static const String _dsn = String.fromEnvironment('SENTRY_DSN');

  static bool get enabled => _dsn.isNotEmpty;

  /// Starts reporting, then hands over to [appRunner].
  ///
  /// Call after the app's own error handlers are installed: Sentry keeps the
  /// handler that was there and calls it after recording, so logging keeps
  /// working exactly as before.
  static Future<void> run(FutureOr<void> Function() appRunner) async {
    if (!enabled) {
      await appRunner();
      return;
    }

    try {
      await SentryFlutter.init((options) {
        options.dsn = _dsn;
        options.release = '${AppInfo.name}@${AppInfo.version}';
        options.environment = kReleaseMode ? 'production' : 'development';

        // Crashes and freezes only: no performance tracing, no session
        // replay, no screenshots, no personal data.
        options.tracesSampleRate = 0;
        options.sendDefaultPii = false;
        options.attachScreenshot = false;

        // A UI thread stuck for five seconds is exactly the "screen froze"
        // report worth seeing, with the stack of what it was doing.
        options.anrEnabled = true;
        options.anrTimeoutInterval = const Duration(seconds: 5);

        options.enableAutoSessionTracking = true;
        options.debug = false;
      }, appRunner: () => appRunner());
    } catch (error, stack) {
      // Reporting must never be the thing that stops the app from starting.
      AppLog.error('Starting crash reporting', error, stack);
      await appRunner();
    }
  }
}
