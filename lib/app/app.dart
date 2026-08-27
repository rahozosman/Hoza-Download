import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/constants/app_info.dart';
import '../data/providers/settings_provider.dart';
import '../features/share/presentation/share_link_listener.dart';
import '../services/config/remote_config.dart';
import 'router.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';

/// Application root.
///
/// Watches only the theme mode, so changing a preference elsewhere never
/// rebuilds the whole tree.
class HozaApp extends ConsumerWidget {
  const HozaApp({super.key});

  /// Upper bound on system text scaling. Beyond this, cards and chips start to
  /// clip; clamping keeps large-text users on a layout that still works.
  static const double _maxTextScale = 1.6;

  /// Shares are presented above the navigator, so the listener needs a handle
  /// on it rather than a context inside it.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    // Woken here, at the root, so the remote config is fetched as the app
    // starts rather than on the first link lookup: the patterns a share needs
    // should already be in place by the time the sheet asks for them. Listened
    // to, not watched — a fresh config must not rebuild the whole tree.
    ref.listen(remoteConfigProvider, (_, _) {});

    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // Bounded on purpose: every pixel in the app is repainted for the length
      // of this cross-fade, so it stays short rather than luxurious.
      themeAnimationDuration: Motion.base,
      themeAnimationCurve: Motion.standard,
      navigatorKey: navigatorKey,
      // The second records which screen a crash report came from; it does
      // nothing until crash reporting is switched on.
      navigatorObservers: [RouteStack.instance, SentryNavigatorObserver()],
      // No explicit initial route: the platform picks it, so a share opens the
      // floating sheet directly instead of booting the whole app first.
      onGenerateRoute: AppRouter.onGenerateRoute,
      onGenerateInitialRoutes: AppRouter.onGenerateInitialRoutes,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(maxScaleFactor: _maxTextScale),
          ),
          child: ShareLinkListener(
            navigatorKey: navigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
