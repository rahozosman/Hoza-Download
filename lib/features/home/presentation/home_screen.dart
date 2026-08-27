import 'package:flutter/material.dart';

import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_motion.dart';
import '../../../shared/widgets/connection_banner.dart';
import '../../../shared/widgets/scroll_reveal.dart';
import '../../shell/presentation/app_shell.dart';
import 'widgets/home_footer.dart';
import 'widgets/home_header.dart';
import 'widgets/home_stats.dart';
import 'widgets/paste_link_card.dart';

/// Landing screen: start a download.
///
/// Home has one job, and everything on it serves that job. The lists that used
/// to sit here were a second copy of the Downloads tab — the same rows, fewer
/// of them, one tap away from the real thing — and they pushed the one action
/// the screen exists for up against the top of the glass. What is left is the
/// masthead, the field the link goes into, and a single card reporting what
/// has been downloaded so far, which is also the way through to the rest.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Owned here rather than left implicit, so the masthead can read the scroll
  /// offset and drift against the content.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.maxContentWidth),
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              Layout.pagePadding,
              Gap.md,
              Layout.pagePadding,
              shellContentInset(context),
            ),
            children: [
              _HeroBlock(controller: _scroll),
              const SizedBox(height: Gap.xl),
              const ScrollReveal(index: 2, child: HomeStats()),
              const SizedBox(height: Gap.xxl),
              const ScrollReveal(index: 3, child: HomeFooter()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The masthead and the primary action, drawn as one block.
///
/// Nothing is painted behind them: the page's own background carries the
/// header and the paste card, so the top of Home reads as one column rather
/// than a lit rectangle sitting on it.
class _HeroBlock extends StatelessWidget {
  const _HeroBlock({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScrollReveal(
          child: _ParallaxHeader(
            controller: controller,
            child: const HomeHeader(),
          ),
        ),
        const SizedBox(height: Gap.sm),
        const ConnectionBanner(),
        const SizedBox(height: Gap.lg),
        const ScrollReveal(index: 1, child: PasteLinkCard()),
      ],
    );
  }
}

/// Lets the masthead fall behind the content as the page scrolls.
///
/// It travels at roughly two thirds of the list's speed and dims on the way
/// out, so the top of Home reads as depth rather than a block sliding off.
class _ParallaxHeader extends StatelessWidget {
  const _ParallaxHeader({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  /// Scroll distance over which the effect plays out; past it, the header is
  /// gone anyway.
  static const double _range = 140;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final offset = controller.hasClients
              ? controller.offset.clamp(0.0, _range)
              : 0.0;
          final t = offset / _range;

          return Opacity(
            opacity: 1 - t * 0.8,
            child: Transform.translate(
              offset: Offset(0, offset * 0.35),
              child: child,
            ),
          );
        },
        child: child,
      ),
    );
  }
}
