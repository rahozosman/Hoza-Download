import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../../data/providers/downloads_provider.dart';
import '../../../shared/widgets/page_background.dart';
import '../../downloads/presentation/downloads_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'shell_controller.dart';
import 'widgets/hoza_nav_bar.dart';

/// Top-level frame: one background, three destinations, one nav bar.
///
/// Pages live in an [IndexedStack] so scroll positions and in-flight state
/// survive tab switches.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(shellTabProvider);
    // The Downloads tab wears how many transfers are alive right now, and
    // bumps when a new one lands there.
    final active = ref.watch(
      downloadsProvider.select(
        (state) => state.records.where((r) => r.status.isActive).length,
      ),
    );
    final bump = ref.watch(downloadBadgeBumpProvider);

    // The app has no AppBar, so nothing else would tell Android which way to
    // paint the status and navigation bar icons. Without this, the light theme
    // leaves white icons on a white background.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle(Theme.of(context).brightness),
      child: PageBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: _TabSwitcher(tab: tab),
          bottomNavigationBar: HozaNavBar(
            current: tab,
            onSelected: (next) =>
                ref.read(shellTabProvider.notifier).select(next),
            badges: {ShellTab.downloads: active},
            bumpToken: bump,
          ),
        ),
      ),
    );
  }
}

/// Keeps every destination alive while painting only the visible one.
///
/// The incoming page fades and lifts into place on each switch. Offscreen pages
/// are never painted — which also means a theme change repaints one screen
/// instead of three.
class _TabSwitcher extends StatefulWidget {
  const _TabSwitcher({required this.tab});

  final ShellTab tab;

  @override
  State<_TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<_TabSwitcher>
    with SingleTickerProviderStateMixin {
  /// Starts settled: the first destination is already on screen.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.base,
    value: 1,
  );

  late final CurvedAnimation _entrance = CurvedAnimation(
    parent: _controller,
    curve: Motion.emphasized,
  );

  @override
  void didUpdateWidget(covariant _TabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pages = [HomeScreen(), DownloadsScreen(), SettingsScreen()];

    final stack = IndexedStack(
      index: widget.tab.index,
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < pages.length; i++)
          // Hidden pages stay mounted so scroll offsets survive, but their
          // tickers are paused and they are hidden from screen readers.
          TickerMode(
            enabled: widget.tab.index == i,
            child: ExcludeSemantics(
              excluding: widget.tab.index != i,
              child: pages[i],
            ),
          ),
      ],
    );

    if (context.reduceMotion) return stack;

    return FadeTransition(
      opacity: _entrance,
      child: AnimatedBuilder(
        animation: _entrance,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - _entrance.value)),
          child: child,
        ),
        child: stack,
      ),
    );
  }
}

/// Bottom padding every scrollable page adds so content clears the floating
/// nav bar.
double shellContentInset(BuildContext context) =>
    HozaNavBar.scrimHeight +
    Layout.navBarHeight +
    MediaQuery.viewPaddingOf(context).bottom +
    Gap.md;
