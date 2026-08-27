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
import '../../../../shared/widgets/media_thumbnail.dart';
import '../../../../shared/widgets/press_scale.dart';

/// Media type switch plus the tiles for the selected type.
///
/// Only types and variants the source genuinely offers are rendered — a source
/// with no audio rendition simply has no Audio side to the switch, and the
/// quality list is never padded with resolutions that would fail. When there
/// is only one side, the sheet still says which one it is rather than leaving
/// a silent gap where the switch would have been.
///
/// Two kinds of choice live here. A video or a soundtrack is one file in
/// several renditions, so picking one replaces the last. A post's photos are
/// several files, and which of them the user wants is not a question with one
/// answer — so those are shown as the pictures themselves, any number of them
/// tickable, in [_PhotoGrid]. [multiSelect] is what tells the two apart.
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
    required this.selectedIds,
    required this.onVariantSelected,
    this.multiSelect = false,
    this.onToggleAll,
  });

  final List<MediaType> availableTypes;
  final MediaType selectedType;
  final ValueChanged<MediaType> onTypeSelected;

  final List<MediaVariant> variants;

  /// Everything currently picked. Exactly one id unless [multiSelect].
  final Set<String> selectedIds;

  /// Tapping a tile. The sheet decides whether that replaces the selection or
  /// adds to it; this widget only reports the tap.
  final ValueChanged<MediaVariant> onVariantSelected;

  /// Whether any number of these may be picked at once. True only for a post
  /// with more than one photo in it.
  final bool multiSelect;

  /// Ticks everything, or clears it when everything is already ticked. Null
  /// when there is nothing to tick in bulk.
  final VoidCallback? onToggleAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final visuals = MediaVisuals.of(selectedType, palette);
    final hasChoice = availableTypes.length > 1;
    final allPicked = multiSelect && selectedIds.length == variants.length;
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
            // The heading takes the slack rather than a spacer, so it is the
            // one thing that gives way when the count and the All button need
            // the room — on a narrow sheet, and at any text scale.
            Expanded(
              child: Text(
                heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sectionTitle.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: Gap.xs),
            // With several photos on offer the count has to say how many are
            // ticked, not how many exist: that number is what the Download
            // button is about to act on.
            Text(
              multiSelect
                  ? '${selectedIds.length} of ${variants.length}'
                  : variants.length == 1
                  ? '1 option'
                  : '${variants.length} options',
              style: AppTypography.caption.copyWith(
                color: palette.textTertiary,
              ),
            ),
            if (multiSelect && onToggleAll != null) ...[
              const SizedBox(width: Gap.xxs),
              _ToggleAllButton(
                label: allPicked ? 'Clear' : 'All',
                visuals: visuals,
                onTap: onToggleAll!,
              ),
            ],
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
            child: multiSelect
                ? _PhotoGrid(
                    key: ValueKey<MediaType>(selectedType),
                    variants: variants,
                    visuals: visuals,
                    selectedIds: selectedIds,
                    onToggled: onVariantSelected,
                  )
                : _QualityGrid(
                    key: ValueKey<MediaType>(selectedType),
                    variants: variants,
                    visuals: visuals,
                    selectedIds: selectedIds,
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
    required this.selectedIds,
    required this.onSelected,
  });

  final List<MediaVariant> variants;
  final MediaVisuals visuals;
  final Set<String> selectedIds;
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
                    selected: selectedIds.contains(variants[i].id),
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
    // Both tracks of a paired download, and the written size of a re-encoded
    // one, so the number matches the file that ends up on the phone.
    final size = variant.savedBytes;
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
                    Row(
                      children: [
                        _TileGlyph(visuals: visuals, selected: selected),
                        const SizedBox(width: Gap.xxs + 1),
                        Flexible(
                          child: AnimatedDefaultTextStyle(
                            duration: context.motion(Motion.fast),
                            curve: Motion.standard,
                            style: AppTypography.sectionTitle.copyWith(
                              color: selected
                                  ? visuals.tint
                                  : palette.textPrimary,
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
                        ),
                      ],
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

/// Ticks every photo at once, or clears them all.
///
/// A post can carry a dozen pictures. Without this, "I want all of them" and
/// "I want just that one" both cost a tap per photo; with it, either is two
/// taps from wherever the selection happens to be.
class _ToggleAllButton extends StatelessWidget {
  const _ToggleAllButton({
    required this.label,
    required this.visuals,
    required this.onTap,
  });

  final String label;
  final MediaVisuals visuals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: PressScale(
        scale: 0.94,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.xs,
            vertical: Gap.xxs,
          ),
          decoration: BoxDecoration(
            color: visuals.tintSoft,
            borderRadius: Radii.pillRadius,
            border: Border.all(color: visuals.tint.withValues(alpha: 0.3)),
          ),
          child: Text(
            label,
            style: AppTypography.label.copyWith(color: visuals.tint),
          ),
        ),
      ),
    );
  }
}

/// The pictures of a post, any number of them tickable.
///
/// Shown as the pictures rather than as a list of names, because "Photo 3" is
/// not something anyone can choose between — the whole question here is which
/// of these images the user wants, and only the images answer it. Each cell
/// carries its number as well, so the tick and the file that arrives are
/// plainly the same thing.
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    super.key,
    required this.variants,
    required this.visuals,
    required this.selectedIds,
    required this.onToggled,
  });

  final List<MediaVariant> variants;
  final MediaVisuals visuals;
  final Set<String> selectedIds;
  final ValueChanged<MediaVariant> onToggled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Three across on a phone: big enough to tell two photos of the same
        // scene apart, small enough that a long slideshow does not turn the
        // sheet into a scroll.
        final columns = constraints.maxWidth >= 420 ? 4 : 3;
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
                  step: const Duration(milliseconds: 30),
                  child: _PhotoTile(
                    variant: variants[i],
                    number: i + 1,
                    visuals: visuals,
                    selected: selectedIds.contains(variants[i].id),
                    onTap: () => onToggled(variants[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.variant,
    required this.number,
    required this.visuals,
    required this.selected,
    required this.onTap,
  });

  final MediaVariant variant;

  /// Where this picture comes in the post, counting from one.
  final int number;

  final MediaVisuals visuals;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: false,
      selected: selected,
      label: variant.label,
      child: PressScale(
        scale: 0.94,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AspectRatio(
          aspectRatio: 1,
          child: AnimatedContainer(
            duration: context.motion(Motion.base),
            curve: Motion.standard,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: Radii.tileRadius,
              border: Border.all(
                color: selected ? visuals.tint : palette.border,
                width: selected ? 2 : 1,
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaThumbnail.expand(
                  mediaType: MediaType.image,
                  imageUrl: variant.url.toString(),
                  headers: variant.headers,
                  borderRadius: Radii.tileRadius,
                ),

                // A picture nobody has ticked is veiled, so the set that is
                // about to be saved reads as a group rather than as whichever
                // cells happen to carry a mark.
                IgnorePointer(
                  child: AnimatedOpacity(
                    duration: context.motion(Motion.base),
                    curve: Motion.standard,
                    opacity: selected ? 0 : 0.45,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: Radii.tileRadius,
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 4,
                  left: 4,
                  child: _PhotoNumber(number: number),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _SelectionMark(
                    selected: selected,
                    visuals: visuals,
                    square: true,
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

/// Which picture of the post this is, on a dark plate so it stays readable on
/// a photo of any colour.
class _PhotoNumber extends StatelessWidget {
  const _PhotoNumber({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: Radii.pillRadius,
      ),
      child: Text(
        '$number',
        style: AppTypography.label.copyWith(color: Colors.white),
      ),
    );
  }
}

/// The play or note mark every quality tile leads its headline with.
///
/// A tile reads `1080p` or `M4A 320 kbps`, and neither says on its own whether
/// a picture or only sound is about to be saved. The glyph does, at a glance
/// and without colour: the same play mark and note the switch above uses, so a
/// tile and the side of the switch it belongs to are plainly the same thing.
///
/// It sits on the headline rather than beside the tile because the line under
/// it — best, container, size — is the one with no width to spare on a
/// two-column sheet, and a badge in the margin was truncating it.
class _TileGlyph extends StatelessWidget {
  const _TileGlyph({required this.visuals, required this.selected});

  final MediaVisuals visuals;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final target = selected ? 1.0 : 0.0;

    // Lerped rather than swapped, so the glyph comes up to full strength with
    // the tile's own fill instead of snapping ahead of it.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: target, end: target),
      duration: context.motion(Motion.fast),
      curve: Motion.standard,
      builder: (context, t, _) => Icon(
        visuals.icon,
        size: 16,
        color: visuals.tint.withValues(alpha: 0.62 + 0.38 * t),
      ),
    );
  }
}

/// The check that lands in a tile as it becomes the chosen one.
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({
    required this.selected,
    required this.visuals,
    this.square = false,
  });

  final bool selected;
  final MediaVisuals visuals;

  /// A rounded square rather than a circle, which is how a tick that may be
  /// one of several differs from one that replaces the last.
  final bool square;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return AnimatedContainer(
      duration: context.motion(Motion.fast),
      curve: Motion.standard,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(6) : null,
        gradient: selected ? visuals.gradient : null,
        // Over a photo the empty mark needs a ground of its own; on a tile it
        // sits on the tile's fill and needs none.
        color: selected
            ? null
            : square
            ? Colors.black.withValues(alpha: 0.35)
            : null,
        border: Border.all(
          color: selected
              ? Colors.transparent
              : square
              ? Colors.white
              : palette.borderStrong,
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
/// A set of photos is summed the same way, and the sum is unknown as soon as
/// any one of them is: a total that quietly left a file out would read as a
/// smaller download than the one about to start.
class EstimatedSizeRow extends StatelessWidget {
  const EstimatedSizeRow({super.key, required this.selection});

  /// What is ticked. Null while the link is still being read, which is not
  /// the same as ticked nothing.
  final List<MediaVariant>? selection;

  /// What the whole selection weighs once written, or null when any part of
  /// it did not report a length.
  static int? _weight(List<MediaVariant> chosen) {
    var total = 0;
    for (final variant in chosen) {
      final bytes = variant.savedBytes;
      if (bytes == null) return null;
      total += bytes;
    }
    return total;
  }

  static String _describe(List<MediaVariant> chosen) {
    final format = chosen.first.format.label;
    return chosen.length == 1
        ? 'Saves as $format'
        : 'Saves ${chosen.length} files as $format';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final chosen = selection;
    final empty = chosen == null || chosen.isEmpty;
    final bytes = empty ? null : _weight(chosen);

    final visuals = MediaVisuals.of(
      chosen?.firstOrNull?.mediaType ?? MediaType.video,
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
            empty
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
              // The bar is on screen before the link has been read, so it
              // has to have something honest to say at that point too — and
              // again once a photo set has been cleared.
              chosen == null
                  ? 'Checking link…'
                  : chosen.isEmpty
                  ? 'Nothing selected'
                  : _describe(chosen),
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
              switch ((empty, bytes)) {
                (true, _) => '—',
                (_, null) => 'Size unknown',
                (_, final int size) => '~ ${Formatters.bytes(size)}',
              },
              key: ValueKey<String>(
                '${chosen?.length ?? -1}|${chosen?.firstOrNull?.id}'
                '|${bytes ?? -1}',
              ),
              style: AppTypography.metric.copyWith(color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
