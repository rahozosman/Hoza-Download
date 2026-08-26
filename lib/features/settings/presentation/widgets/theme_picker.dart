import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../shared/widgets/edge_glow.dart';
import '../../../../shared/widgets/press_scale.dart';

/// Light, Dark and System, shown as three miniature screens.
///
/// A word in a list cannot tell anyone what "Light" will look like. Each option
/// paints itself in the palette it selects — the real background, card, text
/// ramp and brand pill — so the choice is made by looking rather than by
/// guessing and undoing. The live one is outlined and lit along its edge.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, required this.value, required this.onSelected});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onSelected;

  static const List<ThemeMode> _order = [
    ThemeMode.light,
    ThemeMode.dark,
    ThemeMode.system,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _order.length; i++) ...[
            if (i > 0) const SizedBox(width: Gap.sm),
            Expanded(
              child: _ThemeOption(
                mode: _order[i],
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
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  static const double _previewHeight = 76;

  String get _label => switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: _label,
      child: ExcludeSemantics(
        child: PressScale(
          onTap: onTap,
          child: Column(
            children: [
              EdgeGlow(
                active: selected,
                borderRadius: Radii.tileRadius,
                child: AnimatedContainer(
                  duration: context.motion(Motion.base),
                  curve: Motion.standard,
                  height: _previewHeight,
                  decoration: BoxDecoration(
                    borderRadius: Radii.tileRadius,
                    border: Border.all(
                      color: selected ? palette.accent : palette.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    // Inset by the border so the preview never paints over it.
                    borderRadius: BorderRadius.circular(Radii.sm - 1),
                    child: _Preview(mode: mode),
                  ),
                ),
              ),
              const SizedBox(height: Gap.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: context.motion(Motion.fast),
                    curve: Motion.springy,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: Gap.xxs),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: selected
                            ? palette.textPrimary
                            : palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The miniature screen itself. System is split down the middle, because that
/// is exactly what following the phone gives you.
class _Preview extends StatelessWidget {
  const _Preview({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      ThemeMode.light => const _MiniScreen(palette: HozaPalette.light),
      ThemeMode.dark => const _MiniScreen(palette: HozaPalette.dark),
      ThemeMode.system => const Row(
        children: [
          Expanded(child: _MiniScreen(palette: HozaPalette.light, half: true)),
          Expanded(child: _MiniScreen(palette: HozaPalette.dark, half: true)),
        ],
      ),
    };
  }
}

class _MiniScreen extends StatelessWidget {
  const _MiniScreen({required this.palette, this.half = false});

  final HozaPalette palette;

  /// Half-width previews drop the detail that would only turn into mush.
  final bool half;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.background,
      padding: EdgeInsets.all(half ? 5 : 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(palette.textPrimary, half ? 0.8 : 0.5, 5),
          const SizedBox(height: 5),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfaceElevated,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: palette.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(palette.textSecondary, half ? 0.9 : 0.75, 3),
                    if (!half) ...[
                      const SizedBox(height: 4),
                      _bar(palette.textTertiary, 0.45, 3),
                    ],
                    const Spacer(),
                    Container(
                      height: 6,
                      width: half ? 14 : 20,
                      decoration: BoxDecoration(
                        gradient: palette.brandGradient,
                        borderRadius: Radii.pillRadius,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(Color color, double widthFactor, double height) {
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.75),
          borderRadius: Radii.pillRadius,
        ),
      ),
    );
  }
}
