import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/constants/app_info.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/media_option.dart';
import '../../../data/providers/downloads_provider.dart';
import '../../../data/providers/settings_provider.dart';
import '../../../shared/widgets/hoza_logo.dart';
import '../../../services/platform/network_status.dart';
import '../../../shared/widgets/scroll_reveal.dart';
import '../../../shared/widgets/sheen_text.dart';
import '../../downloader/data/shared_download_storage.dart';
import '../../downloads/presentation/widgets/download_dialogs.dart';
import '../../shell/presentation/app_shell.dart';
import 'widgets/media_type_picker.dart';
import 'widgets/reset_flow.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/storage_panel.dart';
import 'widgets/theme_picker.dart';

/// Preferences, storage information and app details.
///
/// Order follows how often a setting is actually touched: the look of the app
/// first, then how it downloads, then where things land, then the quiet
/// housekeeping.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.maxContentWidth),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Layout.pagePadding,
              Gap.xs,
              Layout.pagePadding,
              shellContentInset(context),
            ),
            children: [
              const ScrollReveal(child: _Masthead()),
              const SizedBox(height: Gap.lg),

              // The theme sits first and shows itself: it is the preference
              // people come here to change, and the one that pays back
              // visually the moment it is tapped.
              ScrollReveal(
                index: 1,
                child: SettingsGroup(
                  title: 'Appearance',
                  children: [
                    ThemePicker(
                      value: settings.themeMode,
                      onSelected: controller.setThemeMode,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),

              ScrollReveal(
                index: 2,
                child: SettingsGroup(
                  title: 'Downloads',
                  children: [
                    // The type a link opens on is the download preference
                    // people actually touch, so it shows itself: two cards
                    // painted in the hue each type carries everywhere else,
                    // with the live one filled and ticked.
                    MediaTypePicker(
                      value: settings.defaultMediaType,
                      onSelected: controller.setDefaultMediaType,
                    ),
                    SettingsChoiceRow<MediaFormat>(
                      icon: Icons.movie_outlined,
                      title: 'Video format',
                      value: settings.defaultVideoFormat,
                      options: MediaFormat.values
                          .where((f) => f.mediaType == MediaType.video)
                          .toList(),
                      labelOf: (format) => format.label,
                      onSelected: controller.setDefaultFormat,
                    ),
                    SettingsChoiceRow<MediaFormat>(
                      icon: Icons.music_note_outlined,
                      title: 'Audio format',
                      value: settings.defaultAudioFormat,
                      options: MediaFormat.values
                          .where((f) => f.mediaType == MediaType.audio)
                          .toList(),
                      labelOf: (format) => format.label,
                      onSelected: controller.setDefaultFormat,
                    ),
                    SettingsChoiceRow<QualityPreference>(
                      icon: Icons.high_quality_outlined,
                      title: 'Default quality',
                      subtitle: 'Used when the source offers it',
                      value: settings.qualityPreference,
                      options: QualityPreference.values,
                      labelOf: (preference) => preference.label,
                      onSelected: controller.setQualityPreference,
                    ),
                    SettingsChoiceRow<int>(
                      icon: Icons.layers_outlined,
                      title: 'Concurrent downloads',
                      subtitle: 'How many transfers run at once',
                      value: settings.maxConcurrentDownloads,
                      options: AppSettings.concurrencyOptions,
                      labelOf: (count) => '$count',
                      onSelected: controller.setMaxConcurrentDownloads,
                    ),
                    SettingsSwitchRow(
                      icon: Icons.wifi_rounded,
                      title: 'Wi-Fi only',
                      subtitle: 'Hold downloads on mobile data',
                      value: settings.wifiOnly,
                      onChanged: controller.setWifiOnly,
                    ),
                    SettingsSwitchRow(
                      icon: Icons.play_arrow_rounded,
                      title: 'Auto-start downloads',
                      subtitle: 'Begin as soon as you confirm',
                      value: settings.autoStartDownloads,
                      onChanged: controller.setAutoStart,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),

              ScrollReveal(
                index: 3,
                child: SettingsGroup(
                  title: 'Storage',
                  children: [
                    const _DownloadLocationRow(),
                    const StoragePanel(),
                    SettingsRow(
                      icon: Icons.delete_sweep_outlined,
                      title: 'Clear history',
                      subtitle: 'Saved files are kept',
                      destructive: true,
                      onTap: () => _clearHistory(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),

              ScrollReveal(
                index: 4,
                child: SettingsGroup(
                  title: 'Notifications',
                  children: [
                    SettingsSwitchRow(
                      icon: Icons.notifications_active_outlined,
                      title: 'Download complete',
                      value: settings.notifyOnComplete,
                      onChanged: controller.setNotifyOnComplete,
                    ),
                    SettingsSwitchRow(
                      icon: Icons.notification_important_outlined,
                      title: 'Download failed',
                      value: settings.notifyOnFailure,
                      onChanged: controller.setNotifyOnFailure,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),

              const ScrollReveal(
                index: 5,
                child: SettingsGroup(
                  title: 'Connection',
                  children: [_ConnectionRow()],
                ),
              ),
              const SizedBox(height: Gap.lg),

              ScrollReveal(
                index: 6,
                child: SettingsGroup(
                  title: 'About',
                  children: [
                    SettingsRow(
                      icon: Icons.person_outline_rounded,
                      title: 'About and developer',
                      subtitle: AppInfo.developer,
                      onTap: () =>
                          Navigator.of(context).pushNamed(Routes.about),
                    ),
                    SettingsRow(
                      icon: Icons.info_outline_rounded,
                      title: AppInfo.name,
                      subtitle: 'Version ${AppInfo.version}',
                    ),
                    SettingsRow(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Welcome tour',
                      subtitle: 'See how Hoza Download works again',
                      onTap: () =>
                          Navigator.of(context).pushNamed(Routes.onboarding),
                    ),
                    SettingsRow(
                      icon: Icons.shield_outlined,
                      title: 'Privacy',
                      subtitle: 'What Hoza Download stores on your device',
                      onTap: () => _showPrivacy(context),
                    ),
                    SettingsRow(
                      icon: Icons.description_outlined,
                      title: 'Open-source licenses',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: AppInfo.name,
                        applicationVersion: AppInfo.version,
                        applicationIcon: const Padding(
                          padding: EdgeInsets.all(Gap.xs),
                          child: HozaLogo(size: 48),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),

              // Last on the page, and the only section wearing the warning
              // colour: nothing in it can be taken back.
              ScrollReveal(
                index: 6,
                child: SettingsGroup(
                  title: 'Danger zone',
                  danger: true,
                  children: [
                    SettingsRow(
                      icon: Icons.restart_alt_rounded,
                      title: 'Reset all data',
                      subtitle:
                          'Erase history, settings and cached data. Saved '
                          'files are kept.',
                      destructive: true,
                      onTap: () => showResetFlow(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xl),
              const ScrollReveal(child: _Colophon()),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Clear download history?',
      message:
          'This removes finished and failed entries from the list. Files '
          'already saved to your device are not deleted, and downloads still '
          'in progress are kept.',
      confirmLabel: 'Clear',
    );
    if (!confirmed || !context.mounted) return;

    ref.read(downloadsProvider.notifier).clearHistory();
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('History cleared')));
  }

  void _showPrivacy(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: AppInfo.name,
      applicationVersion: AppInfo.version,
      applicationIcon: const Padding(
        padding: EdgeInsets.all(Gap.xs),
        child: HozaLogo(size: 48),
      ),
      children: const [
        SizedBox(height: Gap.sm),
        Text(
          'Hoza Download keeps your download history on this device only. '
          'It has no accounts, no cloud sync and no analytics, and it never '
          'uploads the links you paste or share.',
        ),
        SizedBox(height: Gap.sm),
        Text(
          'Only content a source permits you to download is supported. Hoza '
          'Download does not bypass DRM, sign-in walls or platform '
          'restrictions.',
        ),
      ],
    );
  }
}

/// Page title and the one line that says what this screen is for.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // The tick every heading in the app opens with, from the Home
            // masthead down to each group below this one.
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                gradient: palette.brandGradient,
                borderRadius: Radii.pillRadius,
              ),
            ),
            const SizedBox(width: Gap.xs),
            Flexible(
              child: SheenText(
                'Settings',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.pageTitle.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xxs),
        Text(
          'How Hoza looks, what it downloads, and where it puts things.',
          style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
        ),
      ],
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
          AppInfo.tagline,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: palette.textTertiary),
        ),
        const SizedBox(height: Gap.xxs),
        Text(
          AppInfo.copyright,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(
            color: palette.textTertiary.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

/// Shows where finished downloads are actually written.
///
/// The path is read from the storage service rather than a constant, so this
/// row can never advertise a folder the app is not using.
/// Live connection state, read from the same provider the download queue
/// honours — so what this row says is exactly what is holding transfers, not a
/// second opinion about the network.
class _ConnectionRow extends ConsumerWidget {
  const _ConnectionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(networkStatusProvider);
    final palette = context.colors;

    final (title, detail, tint) = status.isOffline
        ? ('Offline', 'Queued downloads wait for a connection', palette.danger)
        : status.metered
        ? (
            'Mobile data',
            'Metered. Wi-Fi only, when on, holds downloads here.',
            palette.warning,
          )
        : ('Connected', 'On an unmetered connection', palette.success);

    return SettingsRow(
      icon: Icons.wifi_tethering_rounded,
      title: title,
      subtitle: detail,
      trailing: _StatusDot(tint: tint),
    );
  }
}

/// A filled dot inside a soft ring of its own colour. It changes with the
/// connection rather than sitting there decoratively, and the row's own words
/// carry the meaning, so nothing depends on the colour alone.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.tint});

  final Color tint;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: context.motion(Motion.base),
      curve: Motion.standard,
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.18),
      ),
      child: AnimatedContainer(
        duration: context.motion(Motion.base),
        curve: Motion.standard,
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
      ),
    );
  }
}

class _DownloadLocationRow extends ConsumerWidget {
  const _DownloadLocationRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(downloadLocationProvider);

    final path = location.maybeWhen(data: (value) => value, orElse: () => null);

    return SettingsRow(
      icon: Icons.folder_outlined,
      title: 'Download location',
      subtitle: path ?? 'Reading…',
      trailing: path == null
          ? null
          : IconButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: path));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Folder path copied')),
                  );
              },
              tooltip: 'Copy folder path',
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
    );
  }
}
