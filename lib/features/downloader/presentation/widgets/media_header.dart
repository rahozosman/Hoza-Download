import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/theme/status_visuals.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/media_option.dart';
import '../../../../shared/widgets/edge_glow.dart';
import '../../../../shared/widgets/flight_overlay.dart';
import '../../../../shared/widgets/media_thumbnail.dart';

/// Poster, source and title — the identity block at the top of the sheet.
///
/// The poster carries what belongs on a poster: the running time in its
/// corner, and a badge saying whether the sheet is about to save a video or
/// only its sound. Both follow the current selection, so switching between
/// Video and Audio is answered up here as well as down in the picker.
class MediaHeader extends StatelessWidget {
  const MediaHeader({
    super.key,
    required this.source,
    required this.title,
    required this.mediaType,
    this.thumbnailUrl,
    this.durationSeconds,
    this.subtitle,
    this.showSource = true,
    this.posterKey,
    this.flyFrom,
  });

  final String source;
  final String title;
  final MediaType mediaType;
  final String? thumbnailUrl;
  final int? durationSeconds;

  /// Identifies the poster, so a download starting from this header can send
  /// its picture flying to the Downloads tab.
  final GlobalKey? posterKey;

  /// Where the poster was before this header appeared — a list row — so it
  /// arrives here by flying rather than by cutting in.
  final Rect? flyFrom;

  /// Extra line under the title, e.g. the chosen quality and format.
  final String? subtitle;

  /// Whether the site name is repeated here. Off where the sheet's own title
  /// already names it, so the block does not say the same thing twice.
  final bool showSource;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final visuals = MediaVisuals.of(mediaType, palette);

    final poster = _Poster(
      key: posterKey,
      mediaType: mediaType,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      visuals: visuals,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (flyFrom != null)
          _FlightIn(
            from: flyFrom!,
            thumbnail: MediaThumbnail(
              mediaType: mediaType,
              imageUrl: thumbnailUrl,
              width: _Poster._width,
              aspectRatio: _Poster._aspect,
            ),
            child: poster,
          )
        else
          poster,
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSource) ...[
                Row(
                  children: [
                    Icon(Icons.public_rounded, size: 12, color: palette.accent),
                    const SizedBox(width: Gap.xxs),
                    Expanded(
                      child: Text(
                        source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.label.copyWith(
                          color: palette.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.xxs),
              ],
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title.copyWith(color: palette.textPrimary),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Gap.xs),
                _SubtitleChip(text: subtitle!, visuals: visuals),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Holds the poster's place while its picture flies in from where the user
/// tapped, then reveals it the instant the flight lands.
///
/// The sheet is not a page, so Flutter's own hero cannot do this; the flight
/// runs on the overlay from the row's rectangle to this widget's, measured
/// on the sheet's first frame.
class _FlightIn extends StatefulWidget {
  const _FlightIn({
    required this.from,
    required this.thumbnail,
    required this.child,
  });

  final Rect from;
  final Widget thumbnail;
  final Widget child;

  @override
  State<_FlightIn> createState() => _FlightInState();
}

class _FlightInState extends State<_FlightIn> {
  final GlobalKey _landing = GlobalKey();
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fly());
  }

  Future<void> _fly() async {
    if (!mounted) return;
    final to = Flight.rectOf(_landing);
    if (to == null || context.reduceMotion) {
      setState(() => _landed = true);
      return;
    }
    await Flight.run(
      context,
      from: widget.from,
      to: to,
      child: widget.thumbnail,
      duration: const Duration(milliseconds: 420),
      lift: 10,
    );
    if (mounted) setState(() => _landed = true);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _landing,
      child: AnimatedOpacity(
        opacity: _landed ? 1 : 0,
        duration: context.motion(Motion.fast),
        child: widget.child,
      ),
    );
  }
}

/// The artwork, with the running time and the media type sitting on it.
class _Poster extends StatelessWidget {
  const _Poster({
    super.key,
    required this.mediaType,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.visuals,
  });

  final MediaType mediaType;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final MediaVisuals visuals;

  static const double _width = 104;
  static const double _aspect = 16 / 10;

  /// The chips that sit on the artwork are read against a photograph, not
  /// against a theme surface, so they keep their own ground in both themes.
  static const Color _onArtwork = Color(0xCC05070E);

  @override
  Widget build(BuildContext context) {
    final duration = durationSeconds;

    return SizedBox(
      width: _width,
      height: _width / _aspect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // A light runs the poster's outline, so the frame holding the video
          // is the thing on the sheet that reads as alive. The frame itself
          // tints with the selection, answering the Video/Audio switch at the
          // same moment the picker does.
          EdgeGlow(
            borderRadius: Radii.tileRadius,
            // Finer than the default hairline, because the poster is a small
            // tile and the same line reads heavier on a short perimeter.
            thickness: 0.9,
            // Still a slower lap than everything else on the sheet, so the two
            // lights never look like they are racing each other.
            period: const Duration(milliseconds: 7600),
            child: AnimatedContainer(
              duration: context.motion(Motion.base),
              curve: Motion.standard,
              decoration: BoxDecoration(
                borderRadius: Radii.tileRadius,
                border: Border.all(color: visuals.tint.withValues(alpha: 0.38)),
                boxShadow: [
                  BoxShadow(
                    color: visuals.tint.withValues(alpha: 0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _TintSweep(
                tint: visuals.tint,
                borderRadius: Radii.tileRadius,
                child: MediaThumbnail(
                  mediaType: mediaType,
                  imageUrl: thumbnailUrl,
                  width: _width,
                  aspectRatio: _aspect,
                ),
              ),
            ),
          ),

          Positioned(top: 5, left: 5, child: _TypeDot(visuals: visuals)),

          if (duration != null)
            Positioned(
              right: 5,
              bottom: 5,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: _onArtwork,
                  borderRadius: Radii.pillRadius,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.xs - 2,
                    vertical: 2,
                  ),
                  child: Text(
                    Formatters.duration(duration),
                    style: AppTypography.metric.copyWith(
                      color: const Color(0xFFF3F6FC),
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The disc on the poster that names what will be saved.
class _TypeDot extends StatelessWidget {
  const _TypeDot({required this.visuals});

  final MediaVisuals visuals;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: visuals.label,
      child: AnimatedContainer(
        duration: context.motion(Motion.base),
        curve: Motion.standard,
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: visuals.gradient,
          boxShadow: [visuals.halo],
        ),
        // The glyph rolls over rather than cutting — a quarter turn and a
        // fade, play becoming note becoming photo — so the badge and the
        // switch below it move as one.
        child: AnimatedSwitcher(
          duration: context.motion(Motion.base),
          switchInCurve: Motion.springy,
          switchOutCurve: Motion.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: RotationTransition(
              turns: Tween<double>(begin: -0.25, end: 0).animate(animation),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                child: child,
              ),
            ),
          ),
          child: Icon(
            visuals.icon,
            key: ValueKey<IconData>(visuals.icon),
            size: 13,
            color: context.colors.onAccent,
          ),
        ),
      ),
    );
  }
}

/// The chosen quality and format, as a chip in the type's own hue.
class _SubtitleChip extends StatelessWidget {
  const _SubtitleChip({required this.text, required this.visuals});

  final String text;
  final MediaVisuals visuals;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: context.motion(Motion.fast),
      curve: Motion.standard,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: 3),
      decoration: BoxDecoration(
        color: visuals.tintSoft,
        borderRadius: Radii.pillRadius,
        border: Border.all(color: visuals.tint.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(color: visuals.tint),
      ),
    );
  }
}

/// A wash of the new hue crossing the poster when the media type changes.
///
/// The frame around the poster already eases to the new colour; this is the
/// colour *arriving* — a soft diagonal band in the new tint that sweeps the
/// picture once, left to right, and is gone. Nothing happens on first build:
/// the sweep is a response to a choice, not decoration.
class _TintSweep extends StatefulWidget {
  const _TintSweep({
    required this.tint,
    required this.borderRadius,
    required this.child,
  });

  final Color tint;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<_TintSweep> createState() => _TintSweepState();
}

class _TintSweepState extends State<_TintSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  @override
  void didUpdateWidget(covariant _TintSweep old) {
    super.didUpdateWidget(old);
    if (old.tint != widget.tint && !context.reduceMotion) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _controller.isAnimating
                    ? CustomPaint(
                        painter: _SweepPainter(
                          t: Curves.easeInOut.transform(_controller.value),
                          tint: widget.tint,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  const _SweepPainter({required this.t, required this.tint});

  final double t;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final band = size.width * 0.55;
    final x = -band + t * (size.width + band);
    final rect = Rect.fromLTWH(x, 0, band, size.height);
    canvas.save();
    // Leaning, so the band reads as light moving across rather than a bar.
    canvas.skew(-0.35, 0);
    canvas.drawRect(
      rect.shift(Offset(size.height * 0.35, 0)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            tint.withValues(alpha: 0),
            tint.withValues(alpha: 0.45 * (1 - t * 0.5)),
            tint.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.t != t || old.tint != tint;
}
