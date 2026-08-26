import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_log.dart';

/// What the app shows, and what it records, when a widget fails to build.
///
/// Flutter's default is the red error box. It is the right default for a
/// framework and the wrong one for a shipped app: a fault that lasts two
/// frames — a first-frame race, a value that is briefly out of range — paints
/// a full red screen the user cannot act on and cannot report, and nothing
/// anywhere records what actually threw.
///
/// This replaces both halves of that. The user sees the app's own canvas, the
/// same midnight the launch window paints, so a momentary fault reads as the
/// app still starting rather than as a crash. The fault itself is never
/// swallowed: every one goes through [AppLog] with its stack, so the next run
/// names it in the console.
abstract final class ErrorBoundary {
  /// Installs the handlers. Call once, before `runApp`.
  static void install() {
    // Framework errors: layout, paint, gesture and build failures the
    // framework catches on its own.
    FlutterError.onError = (details) {
      AppLog.error(
        'Widget ${details.library ?? 'framework'}',
        details.exception,
        details.stack,
      );
      // Still hand it to the default in debug, so it keeps its place in the
      // console output a developer is already reading.
      if (!kReleaseMode) FlutterError.presentError(details);
    };

    // Errors that escape the framework entirely — an async callback that
    // threw with nothing to catch it.
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLog.error('Uncaught', error, stack);
      return true;
    };

    ErrorWidget.builder = (details) {
      // FlutterError.onError has already logged this one.
      return const _QuietFailure();
    };
  }
}

/// The panel shown in place of a widget that could not be built.
///
/// Deliberately the simplest widget that can stand in for anything: no theme
/// lookup, no text, no directionality. An error widget is built *because*
/// something in the tree above it is already broken, and one that reaches for
/// an inherited widget of its own can fail in turn — which is how a single
/// fault becomes an unrecoverable loop.
///
/// The colour is the dark canvas the native launch window uses, so a failure
/// during startup is continuous with the screen that preceded it.
class _QuietFailure extends StatelessWidget {
  const _QuietFailure();

  /// Matches `HozaPalette.dark.background`, copied rather than imported: this
  /// widget must not depend on a theme that may be the thing that failed.
  static const Color _canvas = Color(0xFF080E1C);

  @override
  Widget build(BuildContext context) => const ColoredBox(color: _canvas);
}
