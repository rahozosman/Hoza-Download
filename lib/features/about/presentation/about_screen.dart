import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/constants/app_info.dart';
import '../../../shared/widgets/edge_glow.dart';
import '../../../shared/widgets/hoza_card.dart';
import '../../../shared/widgets/hoza_logo.dart';
import '../../../shared/widgets/page_background.dart';
import '../../../shared/widgets/scroll_reveal.dart';
import '../../../shared/widgets/sheen_text.dart';

/// Who made Hoza Download, and how to reach them.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Layout.maxContentWidth,
              ),
              child: Column(
                children: [
                  const _TopBar(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        Layout.pagePadding,
                        Gap.xs,
                        Layout.pagePadding,
                        Gap.xxl,
                      ),
                      children: const [
                        ScrollReveal(child: _Hero()),
                        SizedBox(height: Gap.xl),
                        ScrollReveal(index: 1, child: _DeveloperCard()),
                        SizedBox(height: Gap.lg),
                        ScrollReveal(index: 2, child: _AboutAppCard()),
                        SizedBox(height: Gap.xl),
                        ScrollReveal(index: 3, child: _Colophon()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Layout.pagePadding, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back_rounded, color: palette.textSecondary),
          ),
          const SizedBox(width: Gap.xxs),
          Text(
            'About',
            style: AppTypography.pageTitle.copyWith(color: palette.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Column(
      children: [
        const HozaLogo(size: 72),
        const SizedBox(height: Gap.md),
        SheenText(
          AppInfo.name,
          brand: true,
          style: AppTypography.display.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: Gap.xxs),
        Text(
          'Version ${AppInfo.version}',
          style: AppTypography.caption.copyWith(color: palette.textTertiary),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          AppInfo.tagline,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

/// The credit card, lit along its edge so it reads as the point of the page.
class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return EdgeGlow(
      child: HozaCard(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DEVELOPER',
              style: AppTypography.label.copyWith(color: palette.textTertiary),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                const HozaIconTile(icon: Icons.person_rounded, size: 44),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppInfo.developer,
                        style: AppTypography.title.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Design and development',
                        style: AppTypography.caption.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            const _EmailRow(),
          ],
        ),
      ),
    );
  }
}

/// The app has no mail integration, so the useful action here is putting the
/// address on the clipboard rather than promising an app switch.
class _EmailRow extends StatelessWidget {
  const _EmailRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Material(
      color: palette.surfaceMuted,
      borderRadius: Radii.tileRadius,
      child: InkWell(
        onTap: () => _copy(context),
        borderRadius: Radii.tileRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.alternate_email_rounded,
                size: 18,
                color: palette.accent,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Email',
                      style: AppTypography.caption.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppInfo.developerEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.xs),
              Icon(Icons.copy_rounded, size: 18, color: palette.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: AppInfo.developerEmail));
    if (!context.mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Email address copied')));
  }
}

class _AboutAppCard extends StatelessWidget {
  const _AboutAppCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return HozaCard(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ABOUT THE APP',
            style: AppTypography.label.copyWith(color: palette.textTertiary),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Hoza Download saves media from links you paste or share with it. '
            'History stays on this device, with no accounts, no cloud sync and '
            'no analytics, and files land in ${AppInfo.downloadFolder}.',
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Only content a source permits you to download is supported.',
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Colophon extends StatelessWidget {
  const _Colophon();

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Column(
      children: [
        Text(
          AppInfo.copyright,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: palette.textTertiary),
        ),
        const SizedBox(height: Gap.xxs),
        Text(
          AppInfo.packageId,
          style: AppTypography.caption.copyWith(
            color: palette.textTertiary.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
