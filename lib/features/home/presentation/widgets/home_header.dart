import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/constants/app_info.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/flight_overlay.dart';
import '../../../../shared/widgets/hoza_logo.dart';
import '../../../../shared/widgets/sheen_text.dart';

/// Home masthead: the mark, the greeting, the name, and what the app is for.
///
/// The mark leads and the words stack beside it, so the top of the page is one
/// block at a glance rather than three lines that happen to be near each
/// other. The greeting sits as an eyebrow directly over the name — the same
/// eyebrow-then-title rhythm the welcome tour uses — and opens with the accent
/// tick every heading in the app carries. That repetition down the left edge
/// is what makes a page of separate blocks read as one column.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  /// Large enough to carry the mark's own detail at a glance, small enough
  /// that the name beside it still leads the page.
  static const double _markSize = 54;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Keyed so the splash's mark can land exactly here, and hidden
            // while it is still on its way — otherwise there would be two.
            //
            // The return is instant rather than a fade: the flying copy is
            // still drawn on top of this, in this exact spot, for the frame
            // the swap happens on. Fading in underneath it would only show as
            // the mark going pale once the copy had gone.
            ValueListenableBuilder<bool>(
              valueListenable: FlightTargets.homeMarkInFlight,
              builder: (context, inFlight, child) =>
                  Opacity(opacity: inFlight ? 0 : 1, child: child),
              child: SizedBox(
                key: FlightTargets.homeMark,
                width: _markSize,
                height: _markSize,
                child: const HozaLogo(size: _markSize),
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 11,
                        decoration: BoxDecoration(
                          gradient: palette.brandGradient,
                          borderRadius: Radii.pillRadius,
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      // The greeting wears the same ramp as the tick beside
                      // it, so the line reads as one mark rather than a dash
                      // and a label.
                      Flexible(
                        child: ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: palette.brandGradient.createShader,
                          child: Text(
                            Formatters.greeting().toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.label.copyWith(
                              color: palette.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.xxs),
                  // The wordmark wears the brand ramp, and the ramp drifts:
                  // everything else on the page stays in the neutral text
                  // colours so only one thing is ever moving.
                  SheenText(
                    AppInfo.name,
                    brand: true,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.pageTitle.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Text(
          AppInfo.tagline,
          style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}
