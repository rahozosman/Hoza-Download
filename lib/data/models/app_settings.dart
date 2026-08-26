import 'package:flutter/material.dart';

import 'media_option.dart';

/// Preferred quality applied when a download starts.
///
/// [ask] keeps the choice in the user's hands; the others pick the closest
/// variant a source actually offers and never force an unavailable one.
enum QualityPreference {
  ask('Ask every time'),
  sd480('480p'),
  hd720('720p'),
  fhd1080('1080p'),
  best('Best available');

  const QualityPreference(this.label);

  final String label;

  String get storageKey => name;

  static QualityPreference fromStorageKey(String? key) {
    return QualityPreference.values.firstWhere(
      (value) => value.name == key,
      orElse: () => QualityPreference.ask,
    );
  }

  /// Target vertical resolution, or null when the preference is not a fixed
  /// height.
  int? get targetHeight => switch (this) {
    QualityPreference.sd480 => 480,
    QualityPreference.hd720 => 720,
    QualityPreference.fhd1080 => 1080,
    QualityPreference.ask || QualityPreference.best => null,
  };
}

/// All user preferences, as one immutable value.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.defaultMediaType = MediaType.video,
    this.defaultVideoFormat = MediaFormat.mp4,
    this.defaultAudioFormat = MediaFormat.m4a,
    this.qualityPreference = QualityPreference.ask,
    this.wifiOnly = false,
    this.autoStartDownloads = true,
    this.maxConcurrentDownloads = 2,
    this.notifyOnComplete = true,
    this.notifyOnFailure = true,
    this.onboardingComplete = false,
  });

  final ThemeMode themeMode;
  final MediaType defaultMediaType;
  final MediaFormat defaultVideoFormat;
  final MediaFormat defaultAudioFormat;
  final QualityPreference qualityPreference;

  /// Hold downloads until the device is on Wi-Fi.
  final bool wifiOnly;

  /// Start immediately after the user confirms, instead of only queueing.
  final bool autoStartDownloads;

  /// Hard cap on simultaneous transfers. Never unbounded.
  final int maxConcurrentDownloads;

  final bool notifyOnComplete;
  final bool notifyOnFailure;

  /// Whether the welcome tour has been seen. Defaults to false, so a fresh
  /// install — or a device where preferences could not be read — errs towards
  /// showing the tour rather than dropping someone straight into an empty app.
  final bool onboardingComplete;

  /// Allowed values for the concurrency selector.
  static const List<int> concurrencyOptions = [1, 2, 3];

  AppSettings copyWith({
    ThemeMode? themeMode,
    MediaType? defaultMediaType,
    MediaFormat? defaultVideoFormat,
    MediaFormat? defaultAudioFormat,
    QualityPreference? qualityPreference,
    bool? wifiOnly,
    bool? autoStartDownloads,
    int? maxConcurrentDownloads,
    bool? notifyOnComplete,
    bool? notifyOnFailure,
    bool? onboardingComplete,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      defaultMediaType: defaultMediaType ?? this.defaultMediaType,
      defaultVideoFormat: defaultVideoFormat ?? this.defaultVideoFormat,
      defaultAudioFormat: defaultAudioFormat ?? this.defaultAudioFormat,
      qualityPreference: qualityPreference ?? this.qualityPreference,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      autoStartDownloads: autoStartDownloads ?? this.autoStartDownloads,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      notifyOnComplete: notifyOnComplete ?? this.notifyOnComplete,
      notifyOnFailure: notifyOnFailure ?? this.notifyOnFailure,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }
}
