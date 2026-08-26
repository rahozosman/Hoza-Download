import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/theme/status_visuals.dart';
import '../../../../data/models/download_filter.dart';
import '../../../../data/models/media_option.dart';
import '../../../../shared/widgets/edge_glow.dart';
import '../../../../shared/widgets/hoza_chip.dart';

/// Title row with a search toggle, plus the filter chip rail underneath.
class DownloadsToolbar extends StatelessWidget {
  const DownloadsToolbar({
    super.key,
    required this.searching,
    required this.onToggleSearch,
    required this.searchController,
    required this.onSearchChanged,
    required this.filter,
    required this.onFilterSelected,
    required this.counts,
  });

  final bool searching;
  final VoidCallback onToggleSearch;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final DownloadFilter filter;
  final ValueChanged<DownloadFilter> onFilterSelected;

  /// How many records each chip would show, so the counts are always truthful.
  final Map<DownloadFilter, int> counts;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: Layout.minTouchTarget,
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: context.motion(Motion.base),
                  switchInCurve: Motion.standard,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      axis: Axis.horizontal,
                      alignment: Alignment.centerLeft,
                      sizeFactor: animation,
                      child: child,
                    ),
                  ),
                  child: searching
                      ? _SearchField(
                          key: const ValueKey('search'),
                          controller: searchController,
                          onChanged: onSearchChanged,
                        )
                      : Align(
                          key: const ValueKey('title'),
                          alignment: AlignmentDirectional.centerStart,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // The same accent tick the masthead and every
                              // section heading carry, so this page title
                              // belongs to the same column as the rest.
                              Container(
                                width: 3,
                                height: 20,
                                decoration: BoxDecoration(
                                  gradient: palette.brandGradient,
                                  borderRadius: Radii.pillRadius,
                                ),
                              ),
                              const SizedBox(width: Gap.xs),
                              Text(
                                'Downloads',
                                style: AppTypography.pageTitle.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(width: Gap.xs),
              IconButton(
                onPressed: onToggleSearch,
                tooltip: searching ? 'Close search' : 'Search downloads',
                icon: Icon(
                  searching ? Icons.close_rounded : Icons.search_rounded,
                  color: searching ? palette.accent : palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        SizedBox(
          height: 40,
          // The rail runs off the edge of the screen, and a chip cut in half
          // mid-word reads as a rendering fault. Fading the last few per cent
          // says "there is more this way" instead.
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [0, 0.94, 1],
            ).createShader(bounds, textDirection: TextDirection.ltr),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: DownloadFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.xs),
              itemBuilder: (context, index) {
                final value = DownloadFilter.values[index];
                final count = counts[value] ?? 0;
                return HozaChip(
                  label: value.label,
                  selected: value == filter,
                  // Each kind of media in its own hue — the same blue, green
                  // and amber the tiles below carry.
                  tint: switch (value) {
                    DownloadFilter.all => null,
                    DownloadFilter.video => MediaVisuals.of(
                      MediaType.video,
                      palette,
                    ).tint,
                    DownloadFilter.audio => MediaVisuals.of(
                      MediaType.audio,
                      palette,
                    ).tint,
                    DownloadFilter.image => MediaVisuals.of(
                      MediaType.image,
                      palette,
                    ).tint,
                  },
                  trailingLabel: count == 0 ? null : '$count',
                  onTap: () => onFilterSelected(value),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The search input, lit along its edge while it holds focus.
///
/// Keeps its own [FocusNode] so the light follows focus rather than merely the
/// field existing: tap away to the list and the glow settles down with it.
class _SearchField extends StatefulWidget {
  const _SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return EdgeGlow(
      active: _focusNode.hasFocus,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: AppTypography.body.copyWith(color: palette.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search name, source or format',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.sm,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 18,
            color: palette.textTertiary,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 38,
          ),
        ),
      ),
    );
  }
}
