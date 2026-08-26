import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_motion.dart';
import '../../data/models/media_option.dart';
import 'skeleton.dart';

/// Thumbnail for a media item.
///
/// Falls back to a tinted media-type mark whenever no image is available or the
/// fetch fails, so a card never collapses or shows a broken-image glyph.
class MediaThumbnail extends StatelessWidget {
  const MediaThumbnail({
    super.key,
    required this.mediaType,
    this.imageUrl,
    this.width = 64,
    this.aspectRatio = 16 / 10,
    this.borderRadius = Radii.tileRadius,
  });

  final MediaType mediaType;
  final String? imageUrl;
  final double width;
  final double aspectRatio;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;

    return SizedBox(
      width: width,
      height: width / aspectRatio,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: url == null || url.isEmpty
            ? _Fallback(mediaType: mediaType)
            : Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) {
                    return _FadeIn(child: child);
                  }
                  return const Skeleton(
                    height: double.infinity,
                    borderRadius: BorderRadius.zero,
                  );
                },
                errorBuilder: (context, _, _) =>
                    _Fallback(mediaType: mediaType),
              ),
      ),
    );
  }
}

/// Images fade in rather than popping, which hides decode jitter in lists.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Motion.base,
      curve: Motion.standard,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.mediaType});

  final MediaType mediaType;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final tint = switch (mediaType) {
      MediaType.video => palette.accent,
      MediaType.audio => palette.success,
      MediaType.image => palette.warning,
    };
    final icon = switch (mediaType) {
      MediaType.video => Icons.play_arrow_rounded,
      MediaType.audio => Icons.music_note_rounded,
      MediaType.image => Icons.photo_rounded,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: 0.18), palette.surfaceMuted],
        ),
      ),
      child: Center(child: Icon(icon, color: tint, size: 22)),
    );
  }
}
