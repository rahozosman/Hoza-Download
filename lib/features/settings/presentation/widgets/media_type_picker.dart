import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/theme/status_visuals.dart';
import '../../../../data/models/media_option.dart';
import '../../../../shared/widgets/press_scale.dart';

/// Video or Audio, shown as two cards that each carry their own colour.
///
/// The type a link opens on is the most-touched download preference, so it
/// gets the same treatment as the theme: every option is visible, painted in
/// the hue it carries everywhere else in the app (video on the brand accent,
/// audio on the green), and the live one is filled, lit and ticked so the
/// current choice is readable from across the room.
class MediaTypePicker extends StatelessWidget {
  const MediaTypePicker({
    super.key,
    required this.value,
    required this.onSelected,
    this.title = 'Default type',
    this.subtitle = 'What a link opens on',
  });

  final MediaType value;
  final ValueChanged<MediaType> onSelected;
  final String title;
  final String? subtitle;

  /// Photos only exist for posts that carry them, so a link opens on video
  /// or audio and offers Image alongside when the post has any.
  static const List<MediaType> _order = [MediaType.video, MediaType.audio];

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.body.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppTypography.caption.copyWith(
                color: palette.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              for (var i = 0; i < _order.length; i++) ...[
                if (i > 0) const SizedBox(width: Gap.sm),
                Expanded(
                  child: _MediaTypeCard(
                    type: _order[i],
                    selected: value == _order[i],
                    onTap: () {
                      if (value == _order[i]) return;
                      HapticFeedback.selectionClick();
                      onSelected(_order[i]);
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaTypeCard extends StatelessWidget {
  const _MediaTypeCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final MediaType type;
  final bool selected;
  final VoidCallback onTap;

  static const double _badgeSize = 52;

  String get _hint => switch (type) {
    MediaType.video => 'Picture and sound',
    MediaType.audio => 'Sound only, smaller',
    MediaType.image => 'Photos from the post',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final visuals = MediaVisuals.of(type, palette);
    final duration = context.motion(Motion.base);

    // Selected: the card fills with the type's wash, the badge goes solid on
    // the type's ramp and casts its halo. Idle: a quiet muted surface with a
    // tinted outline badge, so the hue still says which card is which.
    final titleColor = selected ? palette.textPrimary : palette.textSecondary;
    final hintColor = selected ? palette.textSecondary : palette.textTertiary;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: '${visuals.label}, $_hint',
      child: ExcludeSemantics(
        child: PressScale(
          onTap: onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: Motion.standard,
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.md, Gap.sm, Gap.sm),
            decoration: BoxDecoration(
              color: selected ? visuals.tintSoft : palette.surfaceMuted,
              borderRadius: Radii.cardRadius,
              border: Border.all(
                color: selected
                    ? visuals.tint.withValues(alpha: 0.7)
                    : palette.border,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: visuals.tint.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : const [],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _Badge(visuals: visuals, selected: selected),
                    const SizedBox(height: Gap.sm),
                    AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: Motion.standard,
                      style: AppTypography.body.copyWith(
                        color: titleColor,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                      child: Text(
                        visuals.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: Motion.standard,
                      style: AppTypography.caption.copyWith(color: hintColor),
                      child: Text(
                        _hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                // The tick sits in the corner, not on the badge, so the icon
                // stays the icon and the tick reads as a state.
                PositionedDirectional(
                  top: -Gap.xs,
                  end: -Gap.xxs,
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: context.motion(Motion.fast),
                    curve: Motion.springy,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: visuals.tint,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.surface, width: 2),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: palette.onAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The big icon. Solid on the type's ramp when live, an outlined wash when
/// idle — same silhouette either way so the switch is a change of light, not
/// of shape.
class _Badge extends StatelessWidget {
  const _Badge({required this.visuals, required this.selected});

  final MediaVisuals visuals;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final duration = context.motion(Motion.base);

    return AnimatedContainer(
      duration: duration,
      curve: Motion.standard,
      width: _MediaTypeCard._badgeSize,
      height: _MediaTypeCard._badgeSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: selected ? visuals.gradient : null,
        color: selected ? null : visuals.tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_MediaTypeCard._badgeSize * 0.32),
        border: selected
            ? null
            : Border.all(color: visuals.tint.withValues(alpha: 0.28)),
        boxShadow: selected ? [visuals.halo] : const [],
      ),
      child: AnimatedScale(
        scale: selected ? 1 : 0.9,
        duration: duration,
        curve: Motion.springy,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: selected ? palette.onAccent : visuals.tint),
          duration: duration,
          curve: Motion.standard,
          builder: (context, color, _) =>
              Icon(visuals.icon, size: 28, color: color),
        ),
      ),
    );
  }
}
