import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../data/models/download_status.dart';
import '../../../../shared/widgets/download_progress_bar.dart';
import '../../../../shared/widgets/edge_glow.dart';
import '../../../../shared/widgets/hoza_card.dart';
import '../../../../shared/widgets/hoza_logo.dart';
import '../../../../shared/widgets/status_pill.dart';
import 'onboarding_visuals.dart';

/// The live composition above a slide's copy.
///
/// Every scene is built from the app's own surfaces — the same card, chips,
/// progress bar and status pill the real screens use — performing the action
/// the slide describes. Showing the product beats illustrating it: by the time
/// the tour ends the user has already seen the interface they are about to
/// use.
///
/// A scene only runs while its slide is the one on screen, and restarts its
/// story on arrival, so nothing animates off screen and nobody lands halfway
/// through a sentence.
class OnboardingStage extends StatefulWidget {
  const OnboardingStage({
    super.key,
    required this.scene,
    required this.active,
    required this.height,
  });

  final OnboardingScene scene;
  final bool active;
  final double height;

  @override
  State<OnboardingStage> createState() => _OnboardingStageState();
}

class _OnboardingStageState extends State<OnboardingStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6200),
  );

  /// Where a scene rests when motion is switched off. Each is the resolved
  /// state — typed, chosen, downloaded — so the still frame still says what
  /// the scene is about.
  double get _restPose => switch (widget.scene) {
    OnboardingScene.welcome => 0.35,
    OnboardingScene.link => 0.68,
    OnboardingScene.quality => 0.60,
    OnboardingScene.finish => 0.80,
  };

  void _sync() {
    if (context.reduceMotion) {
      _controller
        ..stop()
        ..value = _restPose;
      return;
    }
    if (widget.active) {
      _controller
        ..value = 0
        ..repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A theme change should not restart a scene mid-story.
    if (_controller.isAnimating) return;
    _sync();
  }

  @override
  void didUpdateWidget(covariant OnboardingStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active || widget.scene != oldWidget.scene) {
      _sync();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return switch (widget.scene) {
              OnboardingScene.welcome => _WelcomeScene(
                t: t,
                height: widget.height,
              ),
              OnboardingScene.link => _LinkScene(t: t),
              OnboardingScene.quality => _QualityScene(t: t),
              OnboardingScene.finish => _FinishScene(t: t),
            };
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 1 — the mark, reaching out.
// ---------------------------------------------------------------------------

class _WelcomeScene extends StatelessWidget {
  const _WelcomeScene({required this.t, required this.height});

  final double t;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final plate = (height * 0.42).clamp(76.0, 104.0);

    return Center(
      child: SizedBox.square(
        dimension: height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // A beacon rather than an ornament: rings leaving the mark read as
            // the app reaching out for media, which is what it does.
            Positioned.fill(
              child: CustomPaint(
                painter: _SignalPainter(t: t, color: palette.accent),
              ),
            ),
            // The mark, exactly as the launch screen and the Home masthead
            // draw it. This scene used to build its own light plate around a
            // hardcoded asset path, which is how the tour ended up one edit
            // away from showing a different tile than the rest of the app.
            HozaLogo(size: plate),
          ],
        ),
      ),
    );
  }
}

/// The download bar, drawn to look exactly like [DownloadProgressBar] but
/// following a scripted value instantly.
///
/// The shared widget tweens towards whatever it is given, which is right for a
/// real transfer reporting in bursts and wrong here: the tween would lag the
/// percentage beside it, so the bar would read 85% while the label said 100%.
class _ScriptedProgress extends StatelessWidget {
  const _ScriptedProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return ClipRRect(
      borderRadius: Radii.pillRadius,
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: palette.surfaceMuted),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.accent.withValues(alpha: 0.65),
                      palette.accent,
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

class _SignalPainter extends CustomPainter {
  const _SignalPainter({required this.t, required this.color});

  final double t;
  final Color color;

  static const int _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final near = size.shortestSide * 0.30;
    final far = size.shortestSide * 0.50;

    for (var i = 0; i < _rings; i++) {
      final phase = (t + i / _rings) % 1;
      // In quickly, out slowly: the pulse leaves rather than blinks.
      final fade = phase < 0.12 ? phase / 0.12 : 1.0;
      final alpha = (1 - phase) * fade * 0.45;
      if (alpha <= 0.01) continue;

      canvas.drawCircle(
        center,
        near + (far - near) * phase,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_SignalPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Scene 2 — a link arriving in the field.
// ---------------------------------------------------------------------------

class _LinkScene extends StatelessWidget {
  const _LinkScene({required this.t});

  final double t;

  static const String _url = 'https://hoza.media/clip-01';

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    // One pass of the real gesture: paste is pressed, the link lands a
    // character at a time, the field lights up, and it is accepted.
    final pressed = t > 0.05 && t < 0.13;
    final typed = const Interval(0.12, 0.58).transform(t);
    final accepted = const Interval(
      0.62,
      0.74,
      curve: Motion.springy,
    ).transform(t);
    final entering = const Interval(0, 0.06).transform(t);
    final leaving = const Interval(0.92, 1, curve: Motion.exit).transform(t);

    final shown = _url.substring(0, (typed * _url.length).round());
    final caretOn = typed > 0 && typed < 1 && (t * 16) % 1 < 0.5;

    return Center(
      child: Opacity(
        opacity: entering * (1 - leaving),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EdgeGlow(
              active: typed > 0.05 && leaving < 0.01,
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: Radii.cardRadius,
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.public_rounded,
                      size: 18,
                      color: palette.textTertiary,
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              shown,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: AppTypography.metric.copyWith(
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          if (caretOn)
                            Container(
                              width: 1.6,
                              height: 15,
                              margin: const EdgeInsetsDirectional.only(
                                start: 1,
                              ),
                              color: palette.accent,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.xs),
                    _FieldTrailing(accepted: accepted, pressed: pressed),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            // The second way in, stated once and then stepping aside as soon
            // as the link starts arriving.
            Opacity(
              opacity: (1 - typed * 1.8).clamp(0.0, 1.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.ios_share_rounded,
                    size: 13,
                    color: palette.textTertiary,
                  ),
                  const SizedBox(width: Gap.xxs),
                  Text(
                    'or Share to Hoza Download',
                    style: AppTypography.caption.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paste, pressed — then a tick. One control telling a two-beat story.
class _FieldTrailing extends StatelessWidget {
  const _FieldTrailing({required this.accepted, required this.pressed});

  final double accepted;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return SizedBox.square(
      dimension: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: (1 - accepted).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: pressed ? 0.8 : 1,
              child: Icon(
                Icons.content_paste_rounded,
                size: 17,
                color: pressed ? palette.accent : palette.textSecondary,
              ),
            ),
          ),
          Transform.scale(
            scale: accepted.clamp(0.0, 1.25),
            child: Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: palette.success,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 3 — the choice being made.
// ---------------------------------------------------------------------------

class _QualityScene extends StatelessWidget {
  const _QualityScene({required this.t});

  final double t;

  static const List<String> _qualities = ['480p', '720p', '1080p', 'Best'];

  /// Up the row and back down again. Wrapping straight from the last chip to
  /// the first would rewind across the whole row, which reads as a mistake
  /// being undone rather than as somebody looking through the options.
  static const List<int> _path = [0, 1, 2, 3, 2, 1];

  @override
  Widget build(BuildContext context) {
    // The selection dwells on a value before moving on. The pause is what
    // makes it read as somebody choosing rather than a scanner sweeping.
    final phase = (t * _path.length) % _path.length;
    final step = phase.floor();
    final travel = const Interval(
      0.6,
      1,
      curve: Motion.emphasized,
    ).transform(phase - step);

    final from = _path[step];
    final to = _path[(step + 1) % _path.length];
    final position = from + (to - from) * travel;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FormatToggle(selected: t < 0.5 ? 0 : 1),
          const SizedBox(height: Gap.lg),
          // Scales the whole row down together on a narrow phone, rather than
          // letting one label lose its last character.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _qualities.length; i++) ...[
                  if (i > 0) const SizedBox(width: Gap.xs),
                  _MiniChip(
                    label: _qualities[i],
                    // Proximity, not a boolean: the two chips either side of
                    // the moving choice cross-fade into each other, which is
                    // the slide, without a separate indicator to keep in sync.
                    selection: (1 - (position - i).abs()).clamp(0.0, 1.0),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.selection});

  final String label;
  final double selection;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    // Flattened against the muted fill so the chip stays opaque over the
    // page wash, exactly as HozaChip does on a real surface.
    final selectedFill = Color.alphaBlend(
      palette.accentSoft,
      palette.surfaceMuted,
    );

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: Color.lerp(palette.surfaceMuted, selectedFill, selection),
        shape: StadiumBorder(
          side: BorderSide(
            color: Color.lerp(palette.border, palette.accent, selection)!,
            width: 1 + 0.4 * selection,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: AppTypography.caption.copyWith(
          color: Color.lerp(palette.textSecondary, palette.accent, selection),
          fontWeight: selection > 0.5 ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// Two-up switch built in the same language as the theme picker in Settings,
/// so the tour teaches a control the user will meet again.
class _FormatToggle extends StatelessWidget {
  const _FormatToggle({required this.selected});

  final int selected;

  static const List<String> _formats = ['MP4', 'M4A'];

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Container(
      width: 168,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: Radii.pillRadius,
        border: Border.all(color: palette.border),
      ),
      child: SizedBox(
        height: 34,
        child: Stack(
          children: [
            AnimatedAlign(
              alignment: AlignmentDirectional(selected == 0 ? -1 : 1, 0),
              duration: context.motion(Motion.base),
              curve: Motion.emphasized,
              child: FractionallySizedBox(
                widthFactor: 1 / _formats.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: palette.brandGradient,
                    borderRadius: Radii.pillRadius,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < _formats.length; i++)
                  Expanded(
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: context.motion(Motion.base),
                        curve: Motion.standard,
                        style: AppTypography.caption.copyWith(
                          color: i == selected
                              ? palette.onAccent
                              : palette.textSecondary,
                          fontWeight: i == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        child: Text(_formats[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 4 — a transfer landing.
// ---------------------------------------------------------------------------

class _FinishScene extends StatelessWidget {
  const _FinishScene({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    // Ease-out on the fill so the last few percent take their time, the way a
    // real transfer does.
    final progress = const Interval(
      0.06,
      0.60,
      curve: Motion.standard,
    ).transform(t);
    final done = progress >= 1;
    final saved = const Interval(
      0.66,
      0.84,
      curve: Motion.emphasized,
    ).transform(t);

    // The card is hidden across the loop point, which also covers the progress
    // bar tweening back down to zero.
    final entering = const Interval(0, 0.06).transform(t);
    final leaving = const Interval(0.92, 1, curve: Motion.exit).transform(t);

    return Center(
      child: Opacity(
        opacity: entering * (1 - leaving),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HozaCard(
              padding: const EdgeInsets.all(Gap.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.surfaceMuted,
                          borderRadius: Radii.tileRadius,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                          color: palette.textTertiary,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Interview — full clip',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmall.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '1080p  •  MP4  •  24.8 MB',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  _ScriptedProgress(value: progress),
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: [
                      StatusPill(
                        status: done
                            ? DownloadStatus.completed
                            : DownloadStatus.downloading,
                        dense: true,
                      ),
                      const Spacer(),
                      Text(
                        '${(progress * 100).round()}%',
                        style: AppTypography.metric.copyWith(
                          color: done ? palette.success : palette.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.md),
            Opacity(
              opacity: saved,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - saved)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 13,
                      color: palette.textTertiary,
                    ),
                    const SizedBox(width: Gap.xxs),
                    Text(
                      'Saved on this device',
                      style: AppTypography.caption.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
