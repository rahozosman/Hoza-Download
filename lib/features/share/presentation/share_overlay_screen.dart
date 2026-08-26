import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../data/providers/share_provider.dart';
import '../../../services/platform/share_surface.dart';
import '../../../services/share/pending_share_store.dart';
import '../../downloader/presentation/link_sheet.dart';

/// The entire contents of the floating share window.
///
/// This route paints nothing at all: the Android window behind it is
/// translucent, so what the user sees is their own app — YouTube, a browser,
/// whatever they shared from — with Hoza's link sheet slid up over it. Closing
/// the sheet closes the window and puts them straight back where they were.
///
/// It is the only thing that shows link sheets in the share window. A link
/// that arrives while one is up replaces it; the route itself is never
/// stacked, see [ShareLinkListener].
class ShareOverlayScreen extends ConsumerStatefulWidget {
  const ShareOverlayScreen({super.key});

  /// How long an empty window waits for a link before giving up. A share whose
  /// text carried no usable link must not leave a window sitting on top of
  /// the app the user came from — but a link that is merely slow to cross
  /// from the platform on a cold start must not be thrown away either, so
  /// this is generous. Text with no link in it is closed explicitly, through
  /// [noLink], well before this.
  static const Duration linkTimeout = Duration(seconds: 4);

  /// Whether this route is on the navigator right now.
  ///
  /// Kept as a plain counter rather than a provider so it is exact from the
  /// first frame of the route's life, when the listener may already be
  /// deciding whether to push another one.
  static bool get isMounted => _instances > 0;
  static int _instances = 0;

  /// The live route, while there is one.
  static _ShareOverlayScreenState? _active;

  /// Whether the route on the navigator is already on its way out. A link
  /// that arrives now needs a fresh route, not this one.
  static bool get isFinishing => _active?._finished ?? false;

  /// Closes the route if it is waiting for a link that will never come: the
  /// share carried text with no link in it.
  static void noLink() {
    final active = _active;
    if (active == null || active._showing || active._pending != null) return;
    unawaited(active._finish());
  }

  /// Ends the route wherever it is, e.g. because the engine has moved into
  /// the full app's window, where a transparent sheet route has no place.
  static void retire() {
    final active = _active;
    if (active == null) return;
    unawaited(active._finish());
  }

  @override
  ConsumerState<ShareOverlayScreen> createState() => _ShareOverlayScreenState();
}

class _ShareOverlayScreenState extends ConsumerState<ShareOverlayScreen> {
  StreamSubscription<void>? _dismissals;
  StreamSubscription<ShareHost>? _hosts;
  Timer? _idle;

  /// The link to show, cleared once the user dismisses its sheet.
  Uri? _pending;

  bool _showing = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    ShareOverlayScreen._instances++;
    ShareOverlayScreen._active = this;

    final surface = ref.read(shareSurfaceProvider);
    _dismissals = surface.dismissals.listen(
      (_) => unawaited(_finish(closeWindow: false)),
    );
    // The full app window took the engine: whatever this sheet was doing, the
    // user is now looking at the app, and the share window behind it must not
    // linger to be found again later showing the app's own screens.
    _hosts = surface.hosts.listen((host) {
      if (host == ShareHost.app) unawaited(_finish());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final url = ref.read(overlayShareProvider);
      if (url != null) {
        unawaited(_show(url));
      } else {
        _idle = Timer(ShareOverlayScreen.linkTimeout, () => _finish());
      }
    });
  }

  @override
  void dispose() {
    ShareOverlayScreen._instances--;
    if (ShareOverlayScreen._active == this) ShareOverlayScreen._active = null;
    _idle?.cancel();
    _dismissals?.cancel();
    _hosts?.cancel();
    super.dispose();
  }

  Future<void> _show(Uri url) async {
    if (_finished) return;
    _idle?.cancel();

    if (_showing) {
      if (_pending == url) return;
      // A second share swaps the sheet instead of stacking on it; the loop
      // below picks the new link up as soon as the old sheet is gone.
      _pending = url;
      await Navigator.of(context).maybePop();
      return;
    }

    _pending = url;
    _showing = true;

    final surface = ref.read(shareSurfaceProvider);
    while (mounted && !_finished && _pending != null) {
      final showing = _pending!;
      // Every sheet reveals the window, not only the first. Android may have
      // replaced the window since the last one — a share window it recreated,
      // or a new one for a share that arrived while the old was closing —
      // and a window never revealed is one the user cannot see or dismiss.
      unawaited(surface.ready());
      // The sheet is up: the link no longer needs keeping for a next launch.
      try {
        unawaited(ref.read(pendingShareStoreProvider).clear());
      } catch (_) {
        // No database in this context; nothing was kept.
      }
      await showLinkSheet(context, showing, overlay: true);
      if (!mounted || _finished) return;
      if (_pending == showing) _pending = null;
    }

    _showing = false;
    unawaited(_finish());
  }

  Future<void> _finish({bool closeWindow = true}) async {
    if (_finished) return;
    _finished = true;
    _idle?.cancel();
    ref.read(overlayShareProvider.notifier).clear();

    if (closeWindow) await ref.read(shareSurfaceProvider).close();
    if (!mounted) return;

    // Leave the engine on the app's own route: the next time the full app
    // window attaches, it must not find a transparent sheet route on top. The
    // share window is closed or closing by now, so nothing of this is seen.
    final navigator = Navigator.of(context);
    navigator.popUntil(
      (route) => route.isFirst || route.settings.name == Routes.shareOverlay,
    );
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      unawaited(navigator.pushReplacementNamed(Routes.shell));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Uri?>(overlayShareProvider, (_, next) {
      if (next != null) unawaited(_show(next));
    });

    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(),
    );
  }
}
