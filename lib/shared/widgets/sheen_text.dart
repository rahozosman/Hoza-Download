import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_motion.dart';
import 'edge_glow.dart';

/// Text with a soft blue light drifting across it, forever.
///
/// The glyphs keep their own colour and their own contrast — only a narrow
/// accent-blue band travels over them, so a title reads as alive without ever
/// blinking or becoming harder to read. [brand] swaps the band for the brand
/// ramp itself, which is how the wordmark is drawn.
///
/// Under reduced motion the light stands still: plain text, or a static brand
/// gradient.
class SheenText extends StatefulWidget {
  const SheenText(
    this.data, {
    super.key,
    required this.style,
    this.brand = false,
    this.tint,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.period = const Duration(milliseconds: 4200),
  });

  final String data;
  final TextStyle style;

  /// Paint the brand ramp flowing through the glyphs instead of a single
  /// highlight over the base colour. For wordmarks only.
  final bool brand;

  /// The travelling colour. Defaults to the accent blue.
  final Color? tint;

  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  /// One full pass. Slow enough to be noticed only when the eye rests.
  final Duration period;

  @override
  State<SheenText> createState() => _SheenTextState();
}

class _SheenTextState extends State<SheenText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final base = widget.style.color ?? palette.textPrimary;

    final text = Text(
      widget.data,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
      style: widget.style.copyWith(color: base),
    );

    if (context.reduceMotion) {
      if (!widget.brand) return text;
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: palette.brandGradient.createShader,
        child: text,
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => _shader(bounds, palette, base),
          child: child,
        ),
        child: text,
      ),
    );
  }

  Shader _shader(Rect bounds, HozaPalette palette, Color base) {
    final t = _controller.value;

    if (widget.brand) {
      // Mirrored tiling makes a shift of exactly one width seamless, so the
      // ramp flows on without a seam at the end of each lap.
      return LinearGradient(
        colors: [palette.accent, palette.accentAlt, palette.accent],
        tileMode: TileMode.mirror,
        transform: SlideGradient(t),
      ).createShader(bounds);
    }

    // The band starts and ends fully off the text, so the loop has no jump.
    return LinearGradient(
      colors: [base, widget.tint ?? palette.accent, base],
      stops: const [0.32, 0.5, 0.68],
      transform: SlideGradient(-1 + t * 2),
    ).createShader(bounds);
  }
}
