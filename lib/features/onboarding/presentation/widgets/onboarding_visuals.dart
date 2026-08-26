import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';

/// Which live composition a slide puts on its stage.
///
/// Each scene shows the app doing the thing the slide describes, built from
/// the same surfaces, chips and bars the real screens use — so the tour is a
/// preview of the product rather than a set of illustrations about it.
enum OnboardingScene { welcome, link, quality, finish }

/// One page of the welcome tour.
@immutable
class OnboardingSlide {
  const OnboardingSlide({
    required this.scene,
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final OnboardingScene scene;

  /// Where this sits in the three-step workflow. The progress rail says how
  /// far through the tour you are; this says what part of the job you are
  /// being shown.
  final String eyebrow;

  final String title;
  final String body;
}

/// The tour canvas: the page colour plus two accent washes that drift as the
/// pages turn.
///
/// The washes move against each other and slower than the content, which is
/// what sells the depth — the background reads as further away rather than as
/// wallpaper glued to the page.
class OnboardingBackdrop extends StatelessWidget {
  const OnboardingBackdrop({
    super.key,
    required this.page,
    required this.count,
  });

  final double page;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    // Travel across the whole tour, mapped to -1..1.
    final t = count < 2 ? 0.0 : (page / (count - 1)) * 2 - 1;

    return DecoratedBox(
      decoration: BoxDecoration(color: palette.background),
      child: Stack(
        children: [
          Positioned(
            top: -170,
            left: -130 - t * 80,
            right: -30 + t * 80,
            height: 470,
            child: _wash(palette.backgroundTint, 0.66),
          ),
          Positioned(
            bottom: -280,
            left: -70 + t * 100,
            right: -150 - t * 100,
            height: 500,
            child: _wash(palette.accentAlt, 0.14),
          ),
        ],
      ),
    );
  }

  Widget _wash(Color color, double alpha) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        radius: 0.75,
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

/// Progress across the tour, as a segmented rail.
///
/// Sits at the top beside Skip, the way a story progress bar does: it leaves
/// the bottom of the screen to a single action, and the current segment fills
/// with the swipe itself rather than snapping when the page settles.
class OnboardingRail extends StatelessWidget {
  const OnboardingRail({super.key, required this.count, required this.page});

  final int count;
  final double page;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Semantics(
      label: 'Step ${page.round() + 1} of $count',
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: Gap.xxs),
            Expanded(child: _segment(palette, (page - i + 1).clamp(0.0, 1.0))),
          ],
        ],
      ),
    );
  }

  Widget _segment(HozaPalette palette, double fill) {
    return SizedBox(
      height: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.borderStrong.withValues(alpha: 0.5),
          borderRadius: Radii.pillRadius,
        ),
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: fill,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: palette.brandGradient,
              borderRadius: Radii.pillRadius,
            ),
          ),
        ),
      ),
    );
  }
}
