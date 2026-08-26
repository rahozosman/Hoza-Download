import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/theme/status_visuals.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/media_option.dart';
import '../../../../shared/widgets/fade_slide_in.dart';
import '../../../../shared/widgets/press_scale.dart';

/// Media type switch plus the quality tiles for the selected type.
///
/// Only types and variants the source genuinely offers are rendered — a source
/// with no audio rendition simply has no Audio side to the switch, and the
/// quality list is never padded with resolutions that would fail. When there
/// is only one side, the sheet still says which one it is rather than leaving
/// a silent gap where the switch would have been.
///
/// The selected type carries a hue through the whole block — switch, tiles,
/// check marks — so the answer to "am I saving the video or just the sound?"
/// is visible without reading a word. The word is always there too.
class VariantPicker extends StatelessWidget {
  const VariantPicker({
    super.key,
    required this.availableTypes,
    required this.selectedType,
    required this.onTypeSelected,
    required this.variants,
    required this.selectedVariantId,
    required this.onVariantSelected,
  });

  final List<MediaType> availableTypes;
  final MediaType selectedType;
  final ValueChanged<MediaType> onTypeSelected;

  final List<MediaVariant> variants;
  final String? selectedVariantId;
  final ValueChanged<MediaVariant> onVariantSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final visuals = MediaVisuals.of(selectedType, palette);
    final hasChoice = availableTypes.length > 1;
    // A post's photos are a set to pick from, not qualities of one file.
    final heading = switch (selectedType) {
      MediaType.video => 'Quality',
      MediaType.audio => 'Format',
      MediaType.image => 'Photos',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasChoice) ...[
          MediaTypeSwitch(
            types: availableTypes,
            selected: selectedType,
            onSelected: onTypeSelected,
          ),
          const SizedBox(height: Gap.md),
        ],

        // The word for what is being listed sits directly on top of the list,
        // whether or not there is a switch above it. The tiles below are a set
        // of resolutions or bitrates; without the word, nothing on them says
        // which of the two is about to be saved.
        Row(
          children: [
            _TypeBadge(visuals: visuals),
            const SizedBox(width: Gap.xs),
            Text(
              heading,
              style: AppTypography.sectionTitle.copyWith(
                color: palette.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              variants.length == 1 ? '1 option' : '${variants.length} options',
              style: AppTypography.caption.copyWith(
                color: palette.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),

        // The grid resizes and cross-fades as one movement when the user
        // switches between video and audio.
        AnimatedSize(
          duration: context.motion(Motion.base),
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: context.motion(Motion.base),
            switchInCurve: Motion.standard,
            switchOutCurve: Motion.exit,
            layoutBuilder: (current, previous) => Stack(
              alignment: AlignmentDirectional.topStart,
              children: [...previous, ?current],
            ),
            child: _QualityGrid(
              key: ValueKey<MediaType>(selectedType),
              variants: variants,
              visuals: visuals,
              selectedVariantId: selectedVariantId,
              onSelected: onVariantSelected,
            ),
          ),
        ),
      ],
    );
  }
}

/// Segmented Video / Audio switch with a thumb that slides between the sides.
class MediaTypeSwitch extends StatelessWidget {
  const MediaTypeSwitch({
    super.key,
    required this.types,
    required this.selected,
    required this.onSelected,
  });

  final List<MediaType> types;
  final MediaType selected;
  final ValueChanged<MediaType> onSelected;

  static const double _trackHeight = 44;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final visuals = MediaVisuals.of(selected, palette);
    final index = types.indexOf(selected).clamp(0, types.length - 1);

    // -1 is the left edge, 1 the right; evenly spaced for any number of sides.
    final position = types.length < 2
        ? 0.0
        : -1 + 2 * index / (types.length - 1);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: Radii.pillRadius,
        border: Border.all(color: palette.border),
      ),
      child: SizedBox(
        height: _trackHeight,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: context.motion(Motion.base),
              curve: Motion.emphasized,
              // Directional, so the thumb tracks the selected type rather than
              // a fixed side when the layout is mirrored.
              alignment: AlignmentDirectional(position, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / types.length,
                heightFactor: 1,
                // The thumb changes hue as it travels, so the slide and the
                // colour change are one movement rather than two.
                child: AnimatedContainer(
                  duration: context.motion(Motion.base),
                  curve: Motion.standard,
                  decoration: BoxDecoration(
                    gradient: visuals.gradient,
                    borderRadius: Radii.pillRadius,
                    boxShadow: [visuals.halo],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final type in types)
                  Expanded(
                    child: _Segment(
                      type: type,
                      selected: type == selected,
                      onTap: () => onSelected(type),
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

class _Segment extends StatelessWidget {
  const _Segment({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final MediaType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final visuals = MediaVisuals.of(type, palette);
    final target = selected ? 1.0 : 0.0;

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (selected) return;
          HapticFeedback.selectionClick();
          onTap();
        },
        // The label tracks the thumb instead of snapping the moment it is
        // tapped, so the two read as one movement.
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: target, end: target),
          duration: context.motion(Motion.base),
          curve: Motion.standard,
          builder: (context, t, _) {
            final color = Color.lerp(
              palette.textSecondary,
              palette.onAccent,
              t,
            )!;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // A hair of lift as a side becomes the chosen one — enough to
                // feel picked up, not enough to read as a zoom.
                Transform.scale(
                  scale: 1 + 0.06 * t,
                  child: Icon(visuals.icon, size: 17, color: color),
                ),
                const SizedBox(width: Gap.xxs + 2),
                // Flexible, so a narrow share window shortens the word rather
                // than pushing it out of its half of the track.
                Flexible(
                  child: Text(
                    visuals.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.button.copyWith(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.lerp(
                        FontWeight.w500,
                        FontWeight.w700,
                        t,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Names the type the list below belongs to, in that type's own hue.
///
/// Present whether or not there is a switch above: with one, it is the switch's
/// answer repeated where the choice is actually being made; without one, it is
/// the only place the sheet says which of the two it is offering.
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.visuals});

  final MediaVisuals visuals;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: context.motion(Motion.base),
      curve: Motion.standard,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: 3),
      decoration: BoxDecoration(
        color: visuals.tintSoft,
        borderRadius: Radii.pillRadius,
        border: Border.all(color: visuals.tint.withValues(alpha: 0.35)),
      ),
      // Icon and word change together with the hue, so the badge reads as the
      // same badge turning over rather than two badges swapping: the new one
      // rolls in on a quarter turn as the old one rolls out.
      child: AnimatedSwitcher(
        duration: context.motion(Motion.base),
        switchInCurve: Motion.springy,
        switchOutCurve: Motion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: RotationTransition(
            turns: Tween<double>(begin: -0.18, end: 0).animate(animation),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
              child: child,
            ),
          ),
        ),
        child: Row(
          key: ValueKey<String>(visuals.label),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(visuals.icon, size: 12, color: visuals.tint),
            const SizedBox(width: Gap.xxs),
            Text(
              visuals.label,
              style: AppTypography.label.copyWith(color: visuals.tint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every quality the source offers, laid out as tiles a thumb can reach.
class _QualityGrid extends StatelessWidget {
  const _QualityGrid({
    super.key,
    required this.variants,
    required this.visuals,
    required this.selectedVariantId,
    required this.onSelected,
  });

  final List<MediaVariant> variants;
  final MediaVisuals visuals;
  final String? selectedVariantId;
  final ValueChanged<MediaVariant> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A lone option should not sit in a half-width tile; three columns fit
        // only on a wide sheet.
        final columns = variants.length == 1
            ? 1
            : constraints.maxWidth >= 420
            ? 3
            : 2;
        final width = (constraints.maxWidth - Gap.xs * (columns - 1)) / columns;

        return Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: [
            for (var i = 0; i < variants.length; i++)
              SizedBox(
                width: width,
                child: FadeSlideIn(
                  index: i,
                  offset: 10,
                  // Tiles are small and many; a tight cascade reads as one
                  // grid arriving, where the default step would read as a
                  // queue of tiles.
                  step: const Duration(milliseconds: 30),
                  child: _QualityTile(
                    variant: variants[i],
                    visuals: visuals,
                    // The list arrives highest-quality first, so the leader is
                    // genuinely the best the source offers — never a guess.
                    best: i == 0 && variants.length > 1,
                    selected: variants[i].id == selectedVariantId,
                    onTap: () => onSelected(variants[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.variant,
    required this.visuals,
    required this.selected,
    required this.best,
    required this.onTap,
  });

  final MediaVariant variant;
  final MediaVisuals visuals;
  final bool selected;
  final bool best;
  final VoidCallback onTap;

  /// What goes under the headline. The container is dropped when the headline
  /// already names it, so an MP3 tile never reads "MP3 · MP3".
  String get _detail {
    final parts = <String>[];
    if (best) parts.add('Best');
    if (!variant.label.toUpperCase().contains(variant.format.label)) {
      parts.add(variant.format.label);
    }
    // Both tracks of a paired download, so the size matches the saved file.
    final size = variant.totalEstimatedBytes;
    if (size != null) parts.add(Formatters.bytes(size));
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final detail = _detail;

    final base = palette.surfaceMuted;
    // An opaque wash rather than a translucent overlay: the tile sits on the
    // sheet's own gradient, and a see-through fill would pick that up unevenly.
    final wash = Color.alphaBlend(visuals.tint.withValues(alpha: 0.18), base);

    return Semantics(
      button: true,
      selected: selected,
      child: PressScale(
        scale: 0.96,
        onTap: () {
          if (selected) return;
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: context.motion(Motion.base),
          curve: Motion.standard,
          padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.xs, Gap.sm),
          decoration: BoxDecoration(
            // Both states are two-stop ramps so the fill lerps cleanly instead
            // of cutting from a flat colour to a gradient.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected ? [wash, base] : [base, base],
            ),
            borderRadius: Radii.tileRadius,
            border: Border.all(
              color: selected ? visuals.tint : palette.border,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: visuals.tint.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: context.motion(Motion.fast),
                      curve: Motion.standard,
                      style: AppTypography.sectionTitle.copyWith(
                        color: selected ? visuals.tint : palette.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                      child: Text(
                        variant.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      AnimatedDefaultTextStyle(
                        duration: context.motion(Motion.fast),
                        curve: Motion.standard,
                        style: AppTypography.caption.copyWith(
                          color: selected
                              ? visuals.tint.withValues(alpha: 0.85)
                              : palette.textTertiary,
                        ),
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Gap.xxs),
              _SelectionMark(selected: selected, visuals: visuals),
            ],
          ),
        ),
      ),
    );
  }
}

/// The check that lands in a tile as it becomes the chosen one.
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected, required this.visuals});

  final bool selected;
  final MediaVisuals visuals;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return AnimatedContainer(
      duration: context.motion(Motion.fast),
      curve: Motion.standard,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: selected ? visuals.gradient : null,
        border: Border.all(
          color: selected ? Colors.transparent : palette.borderStrong,
          width: 1.4,
        ),
      ),
      child: AnimatedScale(
        scale: selected ? 1 : 0.5,
        duration: context.motion(Motion.fast),
        curve: Motion.springy,
        child: AnimatedOpacity(
          opacity: selected ? 1 : 0,
          duration: context.motion(Motion.fast),
          curve: Motion.standard,
          child: Icon(Icons.check_rounded, size: 13, color: palette.onAccent),
        ),
      ),
    );
  }
}

/// The one-line summary of what pressing Download will produce.
///
/// Says "size unknown" rather than guessing when the source did not report a
/// length — the download still works, the number just is not available yet.
class EstimatedSizeRow extends StatelessWidget {
  const EstimatedSizeRow({super.key, required this.variant});

  final MediaVariant? variant;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final selected = variant;
    final bytes = selected?.totalEstimatedBytes;

    final visuals = MediaVisuals.of(
      selected?.mediaType ?? MediaType.video,
      palette,
    );

    return AnimatedContainer(
      duration: context.motion(Motion.base),
      curve: Motion.standard,
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.sm,
        vertical: Gap.xs + 2,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: Radii.tileRadius,
        border: Border.all(color: visuals.tint.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            selected == null
                ? Icons.search_rounded
                : bytes == null
                ? Icons.help_outline_rounded
                : Icons.save_alt_rounded,
            size: 14,
            color: visuals.tint,
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              // The bar is on screen before the link has been read, so it has
              // to have something honest to say at that point too.
              selected == null
                  ? 'Checking link…'
                  : 'Saves as ${selected.format.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
          // The figure swaps with the selection rather than jumping.
          AnimatedSwitcher(
            duration: context.motion(Motion.fast),
            switchInCurve: Motion.standard,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                axis: Axis.horizontal,
                sizeFactor: animation,
                child: child,
              ),
            ),
            child: Text(
              switch ((selected, bytes)) {
                (null, _) => '—',
                (_, null) => 'Size unknown',
                (_, final int size) => '~ ${Formatters.bytes(size)}',
              },
              key: ValueKey<String>('${selected?.id}|${bytes ?? -1}'),
              style: AppTypography.metric.copyWith(color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
