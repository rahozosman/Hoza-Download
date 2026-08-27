import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/constants/app_info.dart';
import '../../../data/providers/settings_provider.dart';
import '../../../shared/widgets/flight_overlay.dart';
import '../../../shared/widgets/hoza_logo.dart';
import '../../../shared/widgets/page_background.dart';
import '../../../shared/widgets/sheen_text.dart';

/// Branded entry.
///
/// The system splash has already put the icon in the middle of a midnight
/// screen; this picks it up in the same place on the same canvas the app
/// uses, so nothing jumps. Around it a brand ring draws itself once — the
/// app's whole idea, a download completing — the mark settles in, the name
/// and two lines about the app follow, and a soft light breathes behind it
/// until the screen dissolves into Home.
///
/// Every movement here carries one message: arrival, then readiness. Under
/// reduced motion the screen is simply shown, and held for less time.
///
/// A shared link never lands here — it opens the floating share sheet
/// instead, with no app start to cover.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// The whole entrance: ring, mark, name, tagline, signature.
  ///
  /// A splash is a cost paid on every single launch, so the budget here is
  /// deliberately tight: entrance plus dwell plus exit comes to well under a
  /// second and a half. What used to sit in that time — a paragraph explaining
  /// the app — is not a thing anyone reads twice, and the welcome tour already
  /// says it properly.
  static const Duration _entrance = Duration(milliseconds: 760);

  /// How long the finished screen is held before it leaves. Long enough for
  /// the mark to be seen whole, short enough that the app never feels slow.
  static const Duration _dwell = Duration(milliseconds: 380);

  /// Hold when nothing animates.
  static const Duration _stillHold = Duration(milliseconds: 620);

  /// The dissolve into Home, played on the content itself before the route
  /// cross-fade, so the mark fades out rather than being covered.
  static const Duration _exit = Duration(milliseconds: 260);

  /// One breath of the light behind the mark, in and back out.
  static const Duration _breath = Duration(milliseconds: 2400);

  /// When the canvas starts easing from the system scheme to the app's, and
  /// how long it takes — inside the entrance, so it lands with the name.
  static const Duration _bridgeDelay = Duration(milliseconds: 140);
  static const Duration _bridge = Duration(milliseconds: 480);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: SplashScreen._entrance,
  );

  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: SplashScreen._breath,
  );

  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: SplashScreen._exit,
  );

  /// Every derived curve, so none of them outlives the screen. A
  /// [CurvedAnimation] subscribes to its controller and has to be let go of
  /// explicitly; six of them left behind is a listener leak per launch.
  final List<CurvedAnimation> _curves = <CurvedAnimation>[];

  // The entrance is one timeline, staged so each piece follows the last:
  // ring, then mark, then name, then the tagline, then the signature. The
  // stages overlap by design — each begins while the one before it is still
  // settling, which is what keeps a short entrance from reading as a list of
  // separate pops.
  late final Animation<double> _ring = _stage(0.0, 0.58, Motion.emphasized);
  late final Animation<double> _mark = _stage(0.12, 0.64, Motion.emphasized);
  late final Animation<double> _name = _stage(0.38, 0.82, Motion.standard);
  late final Animation<double> _tagline = _stage(0.52, 0.94, Motion.standard);
  late final Animation<double> _signature = _stage(0.66, 1.0, Motion.standard);

  /// The light behind the mark, easing between two soft intensities.
  late final Animation<double> _glow = Tween<double>(
    begin: 0.72,
    end: 1,
  ).animate(_curve(_breathe, Curves.easeInOut));

  late final Animation<double> _fadeOut = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(_curve(_exit, Motion.exit));

  late final Animation<double> _driftOut = Tween<double>(
    begin: 1,
    end: 1.03,
  ).animate(_curve(_exit, Motion.exit));

  bool _reduceMotion = false;

  /// Whether the canvas has moved from the system's scheme to the app's.
  ///
  /// The launch window Android paints before Flutter follows the system
  /// day/night scheme; the app's theme is the user's own choice. When the two
  /// differ, the first frame is painted in the system scheme — continuous
  /// with the launch window — and the canvas then eases into the app's own
  /// colours as part of the entrance, the lights coming up or down.
  bool _bridged = false;

  Animation<double> _stage(double from, double to, Curve curve) =>
      _curve(_entrance, Interval(from, to, curve: curve));

  /// Builds a curve and remembers it, so [dispose] can release every one.
  CurvedAnimation _curve(AnimationController parent, Curve curve) {
    final animation = CurvedAnimation(parent: parent, curve: curve);
    _curves.add(animation);
    return animation;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = context.reduceMotion;
  }

  @override
  void initState() {
    super.initState();
    // Reduced motion is read on the first frame; the timeline waits for it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    if (!mounted) return;

    if (_reduceMotion) {
      setState(() => _bridged = true);
      await Future<void>.delayed(SplashScreen._stillHold);
    } else {
      // The colours start moving once the ring is under way, so the change
      // of scheme reads as part of the arrival rather than a correction.
      unawaited(
        Future<void>.delayed(SplashScreen._bridgeDelay, () {
          if (mounted) setState(() => _bridged = true);
        }),
      );
      await _entrance.forward();
      if (!mounted) return;
      _breathe.repeat(reverse: true);
      await Future<void>.delayed(SplashScreen._dwell);
      if (!mounted) return;
    }
    if (!mounted) return;

    // Preferences are already on hand — main reads them before the first frame
    // — so the tour decision costs nothing and never flashes the wrong screen.
    final seen = ref.read(settingsProvider).onboardingComplete;

    // Into Home, the mark does not fade: it leaves the centre of the screen
    // and shrinks into the masthead while the shell rises beneath it, so the
    // launch and the app are one continuous picture. Into the welcome tour,
    // which has no masthead, the whole screen dissolves as before.
    final from = _reduceMotion || !seen ? null : Flight.rectOf(_markKey);
    if (from == null) {
      if (!_reduceMotion) await _exit.forward();
      if (!mounted) return;
      unawaited(
        Navigator.of(
          context,
        ).pushReplacementNamed(seen ? Routes.shell : Routes.onboarding),
      );
      return;
    }

    FlightTargets.homeMarkInFlight.value = true;
    setState(() => _markHandedOff = true);
    // Everything but the mark dissolves; the mark itself is now the overlay
    // copy, which outlives this screen.
    unawaited(_exit.forward());
    final navigator = Navigator.of(context);
    final flight = Flight.runToKey(
      context,
      from: from,
      key: FlightTargets.homeMark,
      child: const HozaLogo(size: _Emblem._markSize),
      // The masthead takes its own mark back the moment the flying one lands
      // on it — same place, same size, so the hand-back cannot be seen.
      // Waiting for the whole flight to be torn down instead leaves a frame
      // or two with no mark anywhere, which is the blink at the end of it.
      onLanded: () => FlightTargets.homeMarkInFlight.value = false,
    );
    unawaited(navigator.pushReplacementNamed(Routes.shell));
    await flight;
    // Nothing flew — reduced motion, or no overlay to fly in. Either way the
    // masthead cannot be left waiting for a mark that is never coming.
    FlightTargets.homeMarkInFlight.value = false;
  }

  /// The mark's place on screen, for the hand-off to measure.
  final GlobalKey _markKey = GlobalKey(debugLabel: 'splashMark');

  /// True once the overlay copy has taken over from the mark drawn here.
  bool _markHandedOff = false;

  @override
  void dispose() {
    // Curves first: each holds a listener on a controller below it.
    for (final curve in _curves) {
      curve.dispose();
    }
    _entrance.dispose();
    _breathe.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    final systemTheme =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark
        ? AppTheme.dark
        : AppTheme.light;

    return AnimatedTheme(
      data: _bridged ? appTheme : systemTheme,
      duration: _reduceMotion ? Duration.zero : SplashScreen._bridge,
      curve: Motion.standard,
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final palette = context.colors;

    final cluster = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Emblem(
          ring: _ring,
          mark: _mark,
          glow: _glow,
          still: _reduceMotion,
          markKey: _markKey,
          hideMark: _markHandedOff,
        ),
        const SizedBox(height: Gap.lg),
        _Rise(
          progress: _name,
          still: _reduceMotion,
          child: SheenText(
            AppInfo.name,
            brand: true,
            textAlign: TextAlign.center,
            style: AppTypography.display.copyWith(
              fontSize: 32,
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: Gap.xs),
        _Rise(
          progress: _tagline,
          still: _reduceMotion,
          child: Text(
            AppInfo.tagline,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    final signature = _Rise(
      progress: _signature,
      still: _reduceMotion,
      offset: 6,
      child: Text(
        'Version ${AppInfo.version}  ·  ${AppInfo.developerShort}',
        textAlign: TextAlign.center,
        style: AppTypography.caption.copyWith(color: palette.textTertiary),
      ),
    );

    Widget body = Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Layout.pagePadding),
            child: cluster,
          ),
        ),
        Positioned(left: 0, right: 0, bottom: Gap.xl, child: signature),
      ],
    );

    if (!_reduceMotion) {
      // The whole screen dissolves and drifts a touch outward on the way to
      // Home, so the hand-over reads as one motion, not a cut.
      body = FadeTransition(
        opacity: _fadeOut,
        child: ScaleTransition(scale: _driftOut, child: body),
      );
    }

    return Scaffold(
      backgroundColor: palette.background,
      body: PageBackground(child: SafeArea(child: body)),
    );
  }
}

/// The icon in the middle, the brand ring drawing itself around it, and the
/// light behind both.
class _Emblem extends StatelessWidget {
  const _Emblem({
    required this.ring,
    required this.mark,
    required this.glow,
    required this.still,
    required this.markKey,
    required this.hideMark,
  });

  final Animation<double> ring;
  final Animation<double> mark;
  final Animation<double> glow;
  final bool still;

  /// Where the mark is, for the hand-off into Home.
  final GlobalKey markKey;

  /// True once an overlay copy of the mark is flying; the one drawn here
  /// steps aside so there is never a second mark under the first.
  final bool hideMark;

  /// The ring's diameter. The mark sits inside with a clear margin so the
  /// ring reads as its own line rather than as a border on the tile.
  static const double _ringSize = 150;
  static const double _markSize = 92;
  static const double _glowSize = 232;

  /// The two hues the mark is drawn in: the cloud, and the arrow falling into
  /// the tray beneath it.
  ///
  /// The light around the mark and the ring enclosing it are both mixed from
  /// these rather than from the app's blue-to-violet ramp. A warm drawing
  /// standing in cool light reads as two objects that happen to overlap; lit
  /// by its own colours, the emblem reads as one. This is the only place in
  /// the app that leaves the palette, and it leaves it to serve the artwork.
  static const Color _markCool = Color(0xFF3BAFD4);
  static const Color _markWarm = Color(0xFFFFA61F);

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    Widget light = DecoratedBox(
      decoration: BoxDecoration(
        // Warm at the core, where the arrow and tray are, cooling outward to
        // the cloud — the drawing's own order, spread into the air around it.
        gradient: RadialGradient(
          colors: [
            _markWarm.withValues(alpha: 0.30),
            _markCool.withValues(alpha: 0.20),
            _markCool.withValues(alpha: 0),
          ],
          stops: const [0, 0.48, 1],
        ),
      ),
    );
    if (!still) light = FadeTransition(opacity: glow, child: light);

    Widget logo = SizedBox(
      key: markKey,
      width: _markSize,
      height: _markSize,
      child: Opacity(
        opacity: hideMark ? 0 : 1,
        child: const HozaLogo(size: _markSize),
      ),
    );
    if (!still) {
      logo = AnimatedBuilder(
        animation: mark,
        builder: (context, child) {
          final t = mark.value;
          // The mark is first drawn as a line — cloud, arrow, tray — and the
          // tile then rises through the drawing as it lands: the icon being
          // made, then being there.
          return Stack(
            alignment: Alignment.center,
            children: [
              if (t < 0.98)
                Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: SizedBox(
                    width: _markSize,
                    height: _markSize,
                    child: CustomPaint(
                      painter: _MarkOutlinePainter(
                        progress: (t / 0.7).clamp(0.0, 1.0),
                        cool: _markCool,
                        warm: _markWarm,
                      ),
                    ),
                  ),
                ),
              Opacity(
                opacity: ((t - 0.3) / 0.5).clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, -14 * (1 - t)),
                  child: Transform.scale(scale: 0.84 + 0.16 * t, child: child),
                ),
              ),
            ],
          );
        },
        child: logo,
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: _glowSize,
        height: _glowSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: light),
            SizedBox(
              width: _ringSize,
              height: _ringSize,
              child: still
                  ? CustomPaint(
                      painter: _RingPainter(
                        progress: 1,
                        track: palette.borderStrong,
                        head: _markCool,
                        tail: _markWarm,
                        tip: palette.textPrimary,
                      ),
                    )
                  : AnimatedBuilder(
                      animation: ring,
                      builder: (context, _) => CustomPaint(
                        painter: _RingPainter(
                          progress: ring.value,
                          track: palette.borderStrong,
                          head: _markCool,
                          tail: _markWarm,
                          tip: palette.textPrimary,
                        ),
                      ),
                    ),
            ),
            logo,
          ],
        ),
      ),
    );
  }
}

/// A thin brand ring that draws clockwise from the top: a download completing.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.head,
    required this.tail,
    required this.tip,
  });

  final double progress;

  /// The faint circle the light travels on.
  final Color track;

  /// The two ends of the sweep, and the bright point on its leading edge.
  final Color head;
  final Color tail;
  final Color tip;

  static const double _stroke = 2.6;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);

    // The faint track the light travels on, so the ring has somewhere to go
    // before it has arrived.
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = track.withValues(alpha: 0.55),
    );

    if (progress <= 0) return;
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [head, tail, head],
        transform: const GradientRotation(start),
      ).createShader(rect);
    canvas.drawArc(rect, start, sweep, false, paint);

    // A small bright point on the tip while the ring is still drawing, so the
    // eye follows the progress rather than watching a line thicken.
    if (progress < 1) {
      final angle = start + sweep;
      final leading = Offset(
        rect.center.dx + rect.width / 2 * math.cos(angle),
        rect.center.dy + rect.height / 2 * math.sin(angle),
      );
      canvas.drawCircle(
        leading,
        _stroke * 1.15,
        Paint()..color = tip.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.head != head ||
      old.tail != tail ||
      old.tip != tip;
}

/// Fades a line in while it rises into place. Static when [still].
class _Rise extends StatelessWidget {
  const _Rise({
    required this.progress,
    required this.child,
    required this.still,
    this.offset = 12,
  });

  final Animation<double> progress;
  final Widget child;
  final bool still;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (still) return child;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, offset * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// The Hoza mark as a single travelling line: a cloud, an arrow falling out
/// of it, and the tray it lands in. Drawn once, at launch, before the tile
/// itself appears through it.
class _MarkOutlinePainter extends CustomPainter {
  const _MarkOutlinePainter({
    required this.progress,
    required this.cool,
    required this.warm,
  });

  final double progress;
  final Color cool;
  final Color warm;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas.scale(s, s);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Cloud first, then the arrow, then the tray: the order the eye reads the
    // icon in, and the order a download happens in.
    final cloud = Path()
      ..moveTo(30, 50)
      ..cubicTo(20, 50, 18, 34, 32, 33)
      ..cubicTo(34, 20, 54, 18, 60, 30)
      ..cubicTo(72, 26, 82, 36, 76, 46)
      ..cubicTo(84, 50, 80, 60, 70, 58)
      ..moveTo(30, 50)
      ..lineTo(38, 50);
    final arrow = Path()
      ..moveTo(54, 40)
      ..lineTo(54, 70)
      ..moveTo(44, 61)
      ..lineTo(54, 71)
      ..lineTo(64, 61);
    final tray = Path()
      ..moveTo(28, 68)
      ..lineTo(28, 82)
      ..quadraticBezierTo(28, 86, 32, 86)
      ..lineTo(76, 86)
      ..quadraticBezierTo(80, 86, 80, 82)
      ..lineTo(80, 68);

    final layers = [(cloud, cool), (arrow, warm), (tray, warm)];
    final slice = 1 / layers.length;
    for (var i = 0; i < layers.length; i++) {
      final local = ((progress - i * slice) / slice).clamp(0.0, 1.0);
      if (local <= 0) break;
      paint.color = layers[i].$2;
      for (final metric in layers[i].$1.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * local), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MarkOutlinePainter old) =>
      old.progress != progress || old.cool != cool || old.warm != warm;
}
