import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import 'edge_glow.dart';
import 'press_scale.dart';

/// The single card surface used across Hoza: elevated fill, hairline border,
/// generous radius. Tappable cards get the shared press-scale feedback.
///
/// Elevation is done with light, not shadow. A black drop shadow vanishes on
/// a midnight page; what actually reads as "raised" there is a surface a
/// shade lighter than the page and a thin bright line along its top edge,
/// where a light from above would catch it. So every card is filled with
/// [HozaPalette.surfaceElevated] under a barely-there brand sheen, and wears
/// a one-pixel highlight on its top edge — which also keeps long lists cheap
/// to paint.
class HozaCard extends StatelessWidget {
  const HozaCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(Gap.md),
    this.borderRadius = Radii.cardRadius,
    this.color,
    this.borderColor,
    this.semanticLabel,
    this.glow = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// Overrides the sheen with a flat fill.
  final Color? color;
  final Color? borderColor;
  final String? semanticLabel;

  /// Runs the travelling edge light around the card. For the one card on a
  /// screen that is the point of the screen — never for a list of them.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final base = palette.surfaceElevated;
    final dark = Theme.of(context).brightness == Brightness.dark;

    // The caught light along the top edge: a lifted border colour in the
    // dark, a touch of white in the light, fading out towards the corners so
    // it reads as a highlight and not as a second border.
    final highlight = dark
        ? Color.lerp(palette.borderStrong, Colors.white, 0.35)!
        : Colors.white.withValues(alpha: 0.85);

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        gradient: color != null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    palette.accent.withValues(alpha: 0.05),
                    base,
                  ),
                  base,
                ],
              ),
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? palette.border),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Padding(padding: padding, child: child),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        highlight.withValues(alpha: 0),
                        highlight.withValues(alpha: highlight.a * 0.9),
                        highlight.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.5, 1],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Inside the press scale, so the light stays glued to the border while
    // the card dips under a finger.
    final lit = glow
        ? EdgeGlow(borderRadius: borderRadius, child: surface)
        : surface;

    if (onTap == null && onLongPress == null) return lit;

    return PressScale(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: semanticLabel,
      child: lit,
    );
  }
}

/// A small rounded square holding an icon — used for media type, settings rows
/// and empty-state marks.
class HozaIconTile extends StatelessWidget {
  const HozaIconTile({
    super.key,
    required this.icon,
    this.size = 40,
    this.foreground,
    this.background,
  });

  final IconData icon;
  final double size;
  final Color? foreground;

  /// Overrides the accent wash with a flat fill.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final tint = foreground ?? palette.accent;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        gradient: background != null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint.withValues(alpha: 0.20),
                  tint.withValues(alpha: 0.08),
                ],
              ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: tint),
    );
  }
}
