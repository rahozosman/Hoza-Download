import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_typography.dart';
import '../../../data/providers/settings_provider.dart';
import '../../../shared/widgets/hoza_button.dart';
import '../../../shared/widgets/sheen_text.dart';
import 'widgets/onboarding_stage.dart';
import 'widgets/onboarding_visuals.dart';

/// The welcome tour: four screens shown once, on a fresh install.
///
/// Each slide puts a working piece of the app on a stage and lets it perform
/// the step being described, with the copy underneath in a fixed
/// eyebrow / title / body rhythm. Progress lives at the top next to Skip, the
/// way a story bar does, which leaves the bottom of the screen to exactly one
/// action.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const List<OnboardingSlide> slides = [
    OnboardingSlide(
      scene: OnboardingScene.welcome,
      eyebrow: 'HOZA DOWNLOAD',
      title: 'Welcome to Hoza',
      body:
          'Video, photos and audio from the web, saved straight to your '
          'phone. '
          'No account, no sign-up, no waiting.',
    ),
    OnboardingSlide(
      scene: OnboardingScene.link,
      eyebrow: 'STEP ONE',
      title: 'Paste or share a link',
      body:
          'Copy a link from any app, or share it to Hoza. It reads what is '
          'there and shows you exactly what can be saved.',
    ),
    OnboardingSlide(
      scene: OnboardingScene.quality,
      eyebrow: 'STEP TWO',
      title: 'Pick quality and format',
      body:
          'MP4 or M4A, 480p up to the best the source offers. Set a default '
          'once in Settings and Hoza stops asking.',
    ),
    OnboardingSlide(
      scene: OnboardingScene.finish,
      eyebrow: 'STEP THREE',
      title: 'It finishes, and it stays yours',
      body:
          'Pause, resume and retry any transfer. Your history stays on this '
          'device — nothing is uploaded, ever.',
    ),
  ];

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pages = PageController();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );

  /// Which slide has actually settled. Only that one animates.
  int _settled = 0;

  /// Guards against a second tap while the replacement route is in flight.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Deferred one frame so the reduced-motion query has a MediaQuery to read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.reduceMotion) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pages.dispose();
    super.dispose();
  }

  /// The live page offset, fractional mid-swipe.
  double get _page => _pages.hasClients ? (_pages.page ?? 0) : 0;

  /// True from the moment the last slide is more than half way in, so the
  /// button has finished changing by the time the swipe settles.
  bool get _onLastSlide => _page > OnboardingScreen.slides.length - 1.5;

  void _next() {
    if (_onLastSlide) {
      _finish();
      return;
    }
    HapticFeedback.selectionClick();
    _pages.nextPage(duration: Motion.slow, curve: Motion.emphasized);
  }

  void _finish() {
    if (_leaving) return;
    _leaving = true;

    // Recorded before navigating: the write is best-effort and must not hold
    // up the handover to the app.
    ref.read(settingsProvider.notifier).completeOnboarding();
    HapticFeedback.mediumImpact();

    // Replayed from Settings the tour sits on top of the shell, so leaving it
    // means going back — pushing a replacement there would strand a second
    // shell underneath.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(Routes.shell);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final slides = OnboardingScreen.slides;

    // The stage takes a share of the screen rather than a fixed height, so a
    // small phone gets a smaller performance instead of a scrollbar.
    final stageHeight = math.min(
      232.0,
      MediaQuery.sizeOf(context).height * 0.3,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle(Theme.of(context).brightness),
      child: Scaffold(
        backgroundColor: palette.background,
        body: Stack(
          children: [
            // Only the parts that depend on the page offset listen to the
            // controller — the PageView itself is never rebuilt by it.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pages,
                builder: (context, _) =>
                    OnboardingBackdrop(page: _page, count: slides.length),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: Layout.maxContentWidth + Layout.pagePadding * 2,
                  ),
                  child: Column(
                    children: [
                      _TopBar(
                        pages: _pages,
                        count: slides.length,
                        page: () => _page,
                        isLast: () => _onLastSlide,
                        onSkip: _finish,
                        entrance: _entrance,
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _pages,
                          itemCount: slides.length,
                          onPageChanged: (index) {
                            HapticFeedback.selectionClick();
                            setState(() => _settled = index);
                          },
                          itemBuilder: (context, index) => _Slide(
                            slide: slides[index],
                            index: index,
                            active: _settled == index,
                            stageHeight: stageHeight,
                            controller: _pages,
                            // Only the slide already on screen at launch plays
                            // the entrance; the rest arrive by swipe, which is
                            // motion enough.
                            entrance: index == 0 ? _entrance : null,
                          ),
                        ),
                      ),
                      _BottomAction(
                        pages: _pages,
                        entrance: _entrance,
                        isLast: () => _onLastSlide,
                        onPressed: _next,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress and the way out, on one line.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.pages,
    required this.count,
    required this.page,
    required this.isLast,
    required this.onSkip,
    required this.entrance,
  });

  final PageController pages;
  final int count;
  final double Function() page;
  final bool Function() isLast;
  final VoidCallback onSkip;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: entrance,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Layout.pagePadding,
          Gap.md,
          Gap.xs,
          Gap.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: pages,
                builder: (context, _) =>
                    OnboardingRail(count: count, page: page()),
              ),
            ),
            const SizedBox(width: Gap.md),
            AnimatedBuilder(
              animation: pages,
              builder: (context, child) {
                // On the last slide the primary action already says it, so the
                // escape hatch steps out of the way.
                final hidden = isLast();
                return IgnorePointer(
                  ignoring: hidden,
                  child: AnimatedOpacity(
                    opacity: hidden ? 0 : 1,
                    duration: context.motion(Motion.base),
                    curve: Motion.standard,
                    child: child,
                  ),
                );
              },
              child: TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, Layout.minTouchTarget),
                ),
                child: const Text('Skip'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One action, always in the same place.
class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.pages,
    required this.entrance,
    required this.isLast,
    required this.onPressed,
  });

  final PageController pages;
  final Animation<double> entrance;
  final bool Function() isLast;
  final VoidCallback onPressed;

  static const Curve _in = Interval(0.34, 1, curve: Motion.emphasized);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: entrance,
      builder: (context, child) {
        final t = _in.transform(entrance.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Layout.pagePadding,
          Gap.md,
          Layout.pagePadding,
          Gap.lg,
        ),
        // The label swap cross-fades inside HozaButton, so "Next" becoming
        // "Get started" is a change of state rather than a new button.
        child: AnimatedBuilder(
          animation: pages,
          builder: (context, _) {
            final last = isLast();
            return HozaButton(
              label: last ? 'Get started' : 'Next',
              icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
              onPressed: onPressed,
            );
          },
        ),
      ),
    );
  }
}

/// One slide: a stage, then the copy.
///
/// The [PageView] already moves the whole slide by a page width. Adding a
/// fraction of that back, plus a little scale and fade, turns a flat sideways
/// slide into layers at different depths — the stage hangs back, the copy
/// leaves first.
class _Slide extends StatelessWidget {
  const _Slide({
    required this.slide,
    required this.index,
    required this.active,
    required this.stageHeight,
    required this.controller,
    required this.entrance,
  });

  final OnboardingSlide slide;
  final int index;
  final bool active;
  final double stageHeight;
  final PageController controller;
  final Animation<double>? entrance;

  // Staged so the composition assembles instead of appearing: the stage lands,
  // then the label, the promise, and the detail.
  static const Curve _stageIn = Interval(0, 0.62, curve: Motion.emphasized);
  static const Curve _eyebrowIn = Interval(
    0.16,
    0.74,
    curve: Motion.emphasized,
  );
  static const Curve _titleIn = Interval(0.22, 0.82, curve: Motion.emphasized);
  static const Curve _bodyIn = Interval(0.30, 0.92, curve: Motion.emphasized);

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final reduce = context.reduceMotion;
    final width = MediaQuery.sizeOf(context).width;
    final drive = entrance;

    final stage = OnboardingStage(
      scene: slide.scene,
      active: active,
      height: stageHeight,
    );

    final eyebrow = Row(
      children: [
        Container(
          width: 14,
          height: 2,
          decoration: BoxDecoration(
            gradient: palette.brandGradient,
            borderRadius: Radii.pillRadius,
          ),
        ),
        const SizedBox(width: Gap.xs),
        Text(
          slide.eyebrow,
          style: AppTypography.label.copyWith(color: palette.accent),
        ),
      ],
    );

    final titleStyle = AppTypography.display.copyWith(
      color: palette.textPrimary,
    );

    // Only the opening title carries the moving brand ramp. One thing on the
    // screen is ever alive at a time — and its ticker stands down with the
    // rest of the slide once you have swiped past it.
    final title = index == 0
        ? TickerMode(
            enabled: active,
            child: SheenText(slide.title, brand: true, style: titleStyle),
          )
        : Text(slide.title, style: titleStyle);

    final body = Text(
      slide.body,
      style: AppTypography.body.copyWith(
        color: palette.textSecondary,
        height: 1.6,
      ),
    );

    return AnimatedBuilder(
      animation: drive == null
          ? controller
          : Listenable.merge([controller, drive]),
      builder: (context, _) {
        final page = controller.hasClients
            ? (controller.page ?? index.toDouble())
            : index.toDouble();
        final t = reduce ? 0.0 : (page - index).clamp(-1.0, 1.0);
        final away = t.abs();
        final entered = drive?.value ?? 1;

        Widget staged(Curve curve, double lift, Widget child) {
          if (drive == null) return child;
          final v = curve.transform(entered.clamp(0.0, 1.0));
          return Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, lift * (1 - v)),
              child: child,
            ),
          );
        }

        // Centred in the page area rather than stacked from the top, so the
        // composition sits in the optical middle instead of leaving a hole
        // above the button. The scroll view is the escape valve for very
        // large text scales, not a scrolling page.
        return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: Layout.pagePadding),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: Gap.lg),
                  Transform.translate(
                    offset: Offset(t * width * 0.18, 0),
                    child: Transform.scale(
                      scale: 1 - 0.10 * away,
                      child: Opacity(
                        opacity: (1 - away * 1.15).clamp(0.0, 1.0),
                        child: staged(_stageIn, 26, stage),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.xxl),
                  Transform.translate(
                    offset: Offset(t * width * 0.06, 0),
                    child: Opacity(
                      opacity: (1 - away * 1.9).clamp(0.0, 1.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          staged(_eyebrowIn, 14, eyebrow),
                          const SizedBox(height: Gap.sm),
                          staged(_titleIn, 18, title),
                          const SizedBox(height: Gap.sm),
                          staged(_bodyIn, 22, body),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
