import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../data/providers/share_provider.dart';
import '../../../services/platform/share_surface.dart';
import '../../../services/share/pending_share_store.dart';
import '../../../services/share/share_service.dart';
import '../../downloader/presentation/link_sheet.dart';
import 'share_overlay_screen.dart';

/// Turns incoming shares into an open share sheet.
///
/// Mounted above the navigator so it is alive whichever window the engine is
/// painting into, and whether the share started the process or arrived while
/// Hoza was already running.
///
/// This is the only thing that ever puts the sheet's route on the navigator,
/// and it puts it there at most once: a link that arrives while the route is
/// up is handed to the route, which swaps the sheet it is showing. Two owners
/// of that route is how a second share ends up with two sheets stacked on top
/// of each other.
///
/// A share can also land in the full app's window — when the floating window
/// gave up waiting for its sheet and handed the link over. There the link is
/// shown as an ordinary sheet inside the app, and the transparent overlay
/// route is never used: it would paint nothing over an opaque window.
class ShareLinkListener extends ConsumerStatefulWidget {
  const ShareLinkListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// How long to wait for a finishing overlay route to leave the navigator
  /// before a fresh one is pushed for a new link.
  static const Duration routeHandover = Duration(seconds: 2);

  /// How long a share landing in the full app waits for the shell to come up
  /// behind it — a splash and, on a first launch, the welcome tour.
  static const Duration shellArrival = Duration(seconds: 8);

  @override
  ConsumerState<ShareLinkListener> createState() => _ShareLinkListenerState();
}

class _ShareLinkListenerState extends ConsumerState<ShareLinkListener> {
  StreamSubscription<Uri?>? _subscription;

  /// Set from the moment the route is pushed until it is gone again, so two
  /// links arriving in the same frame open one sheet, not two.
  bool _pushing = false;

  @override
  void initState() {
    super.initState();

    _subscription = ref
        .read(shareServiceProvider)
        .sharedLinks
        .listen(_receive, onError: (Object _) {});

    // The link that started the process is parked on the platform side until
    // something claims it. Subscribing above usually flushes it first; either
    // way the platform hands it over exactly once.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final initial = await ref.read(shareServiceProvider).consumeInitialLink();
      if (initial != null && mounted) {
        unawaited(_present(initial));
        return;
      }
      // No link from the platform: maybe one from the last run, which the
      // process was killed before showing.
      final pending = await _pendingStore?.take();
      if (pending != null && mounted) unawaited(_present(pending));
    });
  }

  /// Null when there is no database in this context (tests, first frame).
  PendingShareStore? get _pendingStore {
    try {
      return ref.read(pendingShareStoreProvider);
    } catch (_) {
      return null;
    }
  }

  void _receive(Uri? url) {
    if (url != null) {
      unawaited(_present(url));
      return;
    }
    // Shared text with no link in it. A share window opened for it has
    // nothing to show and must not sit over the user's app.
    if (ShareOverlayScreen.isMounted) {
      ShareOverlayScreen.noLink();
    } else {
      unawaited(ref.read(shareSurfaceProvider).close());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// The link most recently put on screen, and when. The platform can hand
  /// the same share over twice — once as the launching intent, once over the
  /// stream — and two arrivals of one link must open one sheet, not two
  /// stacked on top of each other.
  Uri? _lastPresented;
  DateTime? _lastPresentedAt;

  static const Duration _duplicateWindow = Duration(seconds: 3);

  Future<void> _present(Uri url) async {
    final now = DateTime.now();
    if (url == _lastPresented &&
        _lastPresentedAt != null &&
        now.difference(_lastPresentedAt!) < _duplicateWindow) {
      return;
    }
    _lastPresented = url;
    _lastPresentedAt = now;

    // Written before anything else can go wrong, cleared once a sheet shows
    // it; a process killed in between finds it here on the next launch.
    unawaited(_pendingStore?.remember(url));

    final host = await ref.read(shareSurfaceProvider).currentHost();
    if (!mounted) return;

    // While the floating share window has the route up, every link belongs
    // to it — even if the platform still reports the app as host for a
    // moment, which would otherwise open a second sheet in the same
    // navigator.
    if (host == ShareHost.app && !ShareOverlayScreen.isMounted) {
      await _presentInApp(url);
      return;
    }

    ref.read(overlayShareProvider.notifier).present(url);
    await _ensureRoute();
  }

  /// Shows the link as a sheet inside the running app.
  ///
  /// Any overlay route still on the navigator is retired first: it belongs to
  /// the share window, and the last thing it does is put the app's own shell
  /// in place, which is what the sheet then opens over.
  Future<void> _presentInApp(Uri url) async {
    // On a cold start the link can arrive before the navigator has built.
    await _waitUntil(() => widget.navigatorKey.currentState != null);
    if (!mounted) return;

    if (ShareOverlayScreen.isMounted) {
      ShareOverlayScreen.retire();
      await _waitUntil(() => !ShareOverlayScreen.isMounted);
      if (!mounted) return;
    }

    // The splash and the welcome tour leave by replacing whatever route is on
    // top — which would be this sheet. Wait for the shell to be in place.
    await _waitUntil(
      () => RouteStack.hasShell,
      limit: ShareLinkListener.shellArrival,
    );
    if (!mounted) return;

    // Fetched after every wait above, never carried across one.
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    unawaited(_pendingStore?.clear());
    await showLinkSheet(context, url);
  }

  /// Puts the sheet's route up unless it already is — because a share booted
  /// the engine straight onto it, or because an earlier share pushed it.
  ///
  /// A route that is already closing cannot take the link: it has stopped
  /// listening. The link is held in the provider, and a fresh route picks it
  /// up as soon as the old one has left.
  Future<void> _ensureRoute() async {
    if (_pushing) return;
    if (ShareOverlayScreen.isMounted) {
      if (!ShareOverlayScreen.isFinishing) return;
      await _waitUntil(() => !ShareOverlayScreen.isMounted);
      if (!mounted || _pushing || ShareOverlayScreen.isMounted) return;
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;

    _pushing = true;
    try {
      await navigator.pushNamed<void>(Routes.shareOverlay);
    } finally {
      _pushing = false;
    }
  }

  /// Polls [condition] until it holds or [limit] has passed. Routes leave
  /// the navigator across a few frames, so a few short waits cover it.
  Future<void> _waitUntil(
    bool Function() condition, {
    Duration limit = ShareLinkListener.routeHandover,
  }) async {
    const step = Duration(milliseconds: 40);
    var waited = Duration.zero;
    while (!condition() && waited < limit) {
      await Future<void>.delayed(step);
      waited += step;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
