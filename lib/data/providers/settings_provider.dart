import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_log.dart';

import '../database/hoza_database.dart';
import '../database/settings_store.dart';
import '../models/app_settings.dart';
import '../models/media_option.dart';

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(databaseProvider)),
);

/// Settings read from disk before the first frame.
///
/// Overridden in `main`, so the app opens straight into the user's theme
/// instead of flashing the default and correcting itself.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

/// Single source of truth for user preferences.
///
/// Changes apply to the UI immediately and are written in the background; a
/// failed write degrades to "this session only" rather than blocking the user.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  void _apply(AppSettings next) {
    if (identical(next, state)) return;
    state = next;
    unawaited(_saveQuietly(next));
  }

  /// The change is already live in the UI; persisting it is best-effort. If the
  /// database is unavailable the preference simply lasts for this session.
  Future<void> _saveQuietly(AppSettings settings) async {
    try {
      await ref.read(settingsStoreProvider).save(settings);
    } catch (error) {
      AppLog.warn('Writing preferences', error);
    }
  }

  void setThemeMode(ThemeMode mode) => _apply(state.copyWith(themeMode: mode));

  void setDefaultMediaType(MediaType type) =>
      _apply(state.copyWith(defaultMediaType: type));

  void setDefaultFormat(MediaFormat format) {
    _apply(
      format.mediaType == MediaType.video
          ? state.copyWith(defaultVideoFormat: format)
          : state.copyWith(defaultAudioFormat: format),
    );
  }

  void setQualityPreference(QualityPreference preference) =>
      _apply(state.copyWith(qualityPreference: preference));

  void setWifiOnly(bool value) => _apply(state.copyWith(wifiOnly: value));

  void setAutoStart(bool value) =>
      _apply(state.copyWith(autoStartDownloads: value));

  /// Clamped to the supported range so a bad value can never uncap concurrency.
  void setMaxConcurrentDownloads(int value) {
    final options = AppSettings.concurrencyOptions;
    _apply(
      state.copyWith(
        maxConcurrentDownloads: value.clamp(options.first, options.last),
      ),
    );
  }

  void setNotifyOnComplete(bool value) =>
      _apply(state.copyWith(notifyOnComplete: value));

  void setNotifyOnFailure(bool value) =>
      _apply(state.copyWith(notifyOnFailure: value));

  /// Marks the welcome tour as seen. One-way: the tour is never shown again
  /// once it has been finished or skipped.
  void completeOnboarding() => _apply(state.copyWith(onboardingComplete: true));

  /// Adopts the built-in defaults without writing them back.
  ///
  /// For the reset flow only. The preferences table has already been emptied
  /// by then, so persisting here would just re-create the rows the reset
  /// removed — including the flag that suppresses the welcome tour, which a
  /// reset is meant to bring back.
  void adoptDefaults() => state = const AppSettings();
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Narrow selector so only the theme rebuilds when the mode changes.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(settingsProvider.select((s) => s.themeMode)),
);
