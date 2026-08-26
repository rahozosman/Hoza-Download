import 'package:flutter/material.dart';

import '../features/about/presentation/about_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/share/presentation/share_overlay_screen.dart';
import '../features/shell/presentation/app_shell.dart';
import '../features/splash/presentation/splash_screen.dart';
import 'theme/app_motion.dart';

/// Named routes. The app is intentionally shallow: a splash, the tabbed shell,
/// the floating share sheet, and modal sheets on top of those.
abstract final class Routes {
  static const String splash = '/';
  static const String shell = '/shell';

  /// The welcome tour. Shown once, straight after the splash, on a fresh
  /// install; never again once it has been finished or skipped.
  static const String onboarding = '/welcome';

  /// Developer and app details, pushed over the shell.
  static const String about = '/about';

  /// The route the engine boots on when a share opened the floating window.
  /// Matches `HozaEngine.ROUTE_SHARE` on the Android side.
  static const String shareOverlay = '/share';
}

/// Keeps track of which named routes are on the navigator.
///
/// The splash and the welcome tour both leave by *replacing* the route on
/// top, whatever it is; a sheet opened over them would be the thing replaced.
/// Anything that wants to open over the app waits for [hasShell] first.
class RouteStack extends NavigatorObserver {
  RouteStack._();

  static final RouteStack instance = RouteStack._();

  static final List<Route<dynamic>> _routes = [];

  /// Whether the tabbed shell is on the navigator, at any depth.
  static bool get hasShell =>
      _routes.any((route) => route.settings.name == Routes.shell);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _routes.remove(oldRoute);
    if (newRoute != null) _routes.add(newRoute);
  }
}

abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      Routes.shell => fade(const AppShell(), settings),
      Routes.onboarding => fade(const OnboardingScreen(), settings),
      Routes.about => fade(const AboutScreen(), settings),
      Routes.shareOverlay => overlay(settings),
      _ => fade(const SplashScreen(), settings),
    };
  }

  /// The share window boots straight onto its own route, which the default
  /// generator would expand into `/` + `/share` — a splash the user would see
  /// flash over the app they shared from.
  static List<Route<dynamic>> onGenerateInitialRoutes(String initialRoute) {
    return <Route<dynamic>>[onGenerateRoute(RouteSettings(name: initialRoute))];
  }

  /// Cross-fade transition used for the few full-page routes in the app.
  static PageRoute<T> fade<T>(Widget page, [RouteSettings? settings]) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: Motion.slow,
      reverseTransitionDuration: Motion.base,
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Motion.standard),
        child: child,
      ),
    );
  }

  /// The share sheet's route.
  ///
  /// Opaque so the app underneath is not painted — the window is translucent,
  /// so what shows through is the app the link came from. The sheet plays its
  /// own entrance, so the route itself has no transition of its own.
  static PageRoute<T> overlay<T>([RouteSettings? settings]) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const ShareOverlayScreen(),
    );
  }
}
