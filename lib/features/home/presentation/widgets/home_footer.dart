import 'package:flutter/material.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/constants/app_info.dart';
import '../../../../shared/widgets/press_scale.dart';

/// Signature at the foot of Home: who made the app, and the copyright notice.
///
/// Tapping it opens the About page, so the credit doubles as the way in to the
/// full details rather than being dead text.
class HomeFooter extends StatelessWidget {
  const HomeFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return PressScale(
      semanticLabel: 'About ${AppInfo.name}',
      onTap: () => Navigator.of(context).pushNamed(Routes.about),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Column(
          children: [
            // A hairline that fades out at both ends, so the footer separates
            // from the list without drawing a hard rule across the page.
            Container(
              height: 1,
              margin: const EdgeInsets.only(bottom: Gap.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    palette.border.withValues(alpha: 0),
                    palette.borderStrong,
                    palette.border.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            Text(
              'DEVELOPED BY',
              style: AppTypography.label.copyWith(color: palette.textTertiary),
            ),
            const SizedBox(height: Gap.xxs),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) =>
                  palette.brandGradient.createShader(bounds),
              child: Text(
                AppInfo.developerShort,
                style: AppTypography.title.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              AppInfo.copyright,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: palette.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
