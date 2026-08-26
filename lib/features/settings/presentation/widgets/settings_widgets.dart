import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../shared/widgets/hoza_bottom_sheet.dart';
import '../../../../shared/widgets/hoza_card.dart';

/// Where a settings row's text column starts. Dividers are indented to it so
/// they line up under the copy rather than cutting across the icons.
const double _rowTextInset = Gap.md + 34 + Gap.sm;

/// A titled card holding related settings rows.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;

  /// Marks a section whose actions cannot be undone. The heading and the card
  /// outline both carry the warning colour, so the treatment reaches the user
  /// before the row does.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: Gap.xxs,
            bottom: Gap.xs,
          ),
          child: Row(
            children: [
              // A short accent tick, so section titles read as headings rather
              // than as floating labels.
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: danger ? palette.danger : null,
                  gradient: danger ? null : palette.brandGradient,
                  borderRadius: Radii.pillRadius,
                ),
              ),
              const SizedBox(width: Gap.xs),
              Text(
                title.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: danger ? palette.danger : palette.textTertiary,
                ),
              ),
            ],
          ),
        ),
        HozaCard(
          borderColor: danger ? palette.danger.withValues(alpha: 0.38) : null,
          padding: const EdgeInsets.symmetric(vertical: Gap.xxs),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: _rowTextInset,
                    color: palette.border,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared row layout: leading icon tile, title, optional subtitle, trailing
/// widget.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final tint = destructive ? palette.danger : palette.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          child: Row(
            children: [
              HozaIconTile(
                icon: icon,
                size: 34,
                foreground: destructive ? palette.danger : palette.accent,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.body.copyWith(
                        color: tint,
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
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: Gap.sm),
                trailing!,
              ] else if (onTap != null && !destructive)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: palette.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row whose trailing element is a switch. Tapping anywhere toggles it.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  void _toggle(bool next) {
    HapticFeedback.selectionClick();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: SettingsRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => _toggle(!value),
        trailing: Switch(value: value, onChanged: _toggle),
      ),
    );
  }
}

/// Row showing the current selection as a pill, opening a picker on tap.
class SettingsChoiceRow<T> extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onSelected,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<T> options;
  final String Function(T option) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () async {
        final selected = await showHozaSheet<T>(
          context: context,
          builder: (context) => _ChoiceSheet<T>(
            title: title,
            value: value,
            options: options,
            labelOf: labelOf,
          ),
        );
        if (selected != null) onSelected(selected);
      },
      // The value carries the accent, so the eye finds what a row is set to
      // before it reads the row.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: context.motion(Motion.fast),
            curve: Motion.standard,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.xs,
                vertical: Gap.xxs,
              ),
              decoration: BoxDecoration(
                color: palette.accentSoft,
                borderRadius: Radii.pillRadius,
              ),
              child: Text(
                labelOf(value),
                style: AppTypography.caption.copyWith(color: palette.accent),
              ),
            ),
          ),
          const SizedBox(width: Gap.xxs),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: palette.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// One option in a [SettingsSegmentedRow].
@immutable
class SettingsSegment<T> {
  const SettingsSegment({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

/// An inline segmented picker for short, visual choices.
///
/// Used where opening a sheet to change one word would be more ceremony than
/// the choice deserves: every option is visible, one tap applies it, and the
/// indicator slides so the change is impossible to miss.
class SettingsSegmentedRow<T> extends StatelessWidget {
  const SettingsSegmentedRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.segments,
    required this.onSelected,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<SettingsSegment<T>> segments;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final match = segments.indexWhere((segment) => segment.value == value);
    // An unrecognised value still has to render, so fall back to the first
    // segment rather than leaving the indicator off the track.
    final index = match < 0 ? 0 : match;
    final count = segments.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HozaIconTile(icon: icon, size: 34),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: Radii.pillRadius,
              border: Border.all(color: palette.border),
            ),
            child: SizedBox(
              height: 42,
              child: Stack(
                children: [
                  AnimatedAlign(
                    // Directional: the segment index has to keep meaning the
                    // same segment when the layout is mirrored.
                    alignment: AlignmentDirectional(
                      count == 1 ? 0 : -1 + 2 * index / (count - 1),
                      0,
                    ),
                    duration: context.motion(Motion.base),
                    curve: Motion.emphasized,
                    child: FractionallySizedBox(
                      widthFactor: 1 / count,
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
                      for (final segment in segments)
                        Expanded(
                          child: _Segment<T>(
                            segment: segment,
                            selected: segment.value == value,
                            onTap: () {
                              if (segment.value == value) return;
                              HapticFeedback.selectionClick();
                              onSelected(segment.value);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final SettingsSegment<T> segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final color = selected ? palette.onAccent : palette.textSecondary;
    final duration = context.motion(Motion.base);

    return Semantics(
      button: true,
      selected: selected,
      label: segment.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1 : 0.94,
          duration: duration,
          curve: Motion.springy,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: duration,
                curve: Motion.standard,
                builder: (context, animated, _) =>
                    Icon(segment.icon, size: 16, color: animated),
              ),
              const SizedBox(width: Gap.xxs),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: Motion.standard,
                  style: AppTypography.caption.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.value,
    required this.options,
    required this.labelOf,
  });

  final String title;
  final T value;
  final List<T> options;
  final String Function(T option) labelOf;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return HozaSheet(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            Semantics(
              selected: option == value,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(option),
                borderRadius: Radii.tileRadius,
                child: AnimatedContainer(
                  duration: context.motion(Motion.fast),
                  curve: Motion.standard,
                  margin: const EdgeInsets.only(bottom: Gap.xxs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: Gap.sm,
                  ),
                  decoration: BoxDecoration(
                    color: option == value
                        ? palette.accentSoft
                        : Colors.transparent,
                    borderRadius: Radii.tileRadius,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          labelOf(option),
                          style: AppTypography.body.copyWith(
                            color: option == value
                                ? palette.accent
                                : palette.textPrimary,
                            fontWeight: option == value
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      AnimatedScale(
                        scale: option == value ? 1 : 0,
                        duration: context.motion(Motion.fast),
                        curve: Motion.springy,
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: palette.accent,
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
}
