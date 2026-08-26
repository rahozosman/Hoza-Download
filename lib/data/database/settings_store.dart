import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/utils/app_log.dart';

import '../models/app_settings.dart';
import '../models/media_option.dart';
import 'hoza_database.dart';

/// Reads and writes user preferences.
///
/// Stored as plain key/value rows so adding a preference never needs a schema
/// change. Every read validates: a value written by an older build, or one that
/// has been corrupted, falls back to the default instead of throwing.
class SettingsStore {
  const SettingsStore(this._db);

  final Database _db;

  static const String _themeMode = 'theme_mode';
  static const String _defaultMediaType = 'default_media_type';
  static const String _defaultVideoFormat = 'default_video_format';
  static const String _defaultAudioFormat = 'default_audio_format';
  static const String _qualityPreference = 'quality_preference';
  static const String _wifiOnly = 'wifi_only';
  static const String _autoStart = 'auto_start';
  static const String _maxConcurrent = 'max_concurrent';
  static const String _notifyComplete = 'notify_complete';
  static const String _notifyFailure = 'notify_failure';
  static const String _onboardingComplete = 'onboarding_complete';

  Future<AppSettings> load() async {
    Map<String, String> values;
    try {
      final rows = await _db.query(HozaDatabase.preferencesTable);
      values = {
        for (final row in rows)
          row[HozaDatabase.preferenceKey] as String:
              row[HozaDatabase.preferenceValue] as String,
      };
    } catch (error) {
      // Unreadable preferences mean defaults, never a failed launch.
      AppLog.error('Reading preferences', error);
      return const AppSettings();
    }

    const defaults = AppSettings();
    return AppSettings(
      themeMode: _themeFromKey(values[_themeMode]),
      defaultMediaType: values.containsKey(_defaultMediaType)
          ? MediaType.fromStorageKey(values[_defaultMediaType])
          : defaults.defaultMediaType,
      defaultVideoFormat: _formatOr(
        values[_defaultVideoFormat],
        MediaType.video,
        defaults.defaultVideoFormat,
      ),
      defaultAudioFormat: _formatOr(
        values[_defaultAudioFormat],
        MediaType.audio,
        defaults.defaultAudioFormat,
      ),
      qualityPreference: values.containsKey(_qualityPreference)
          ? QualityPreference.fromStorageKey(values[_qualityPreference])
          : defaults.qualityPreference,
      wifiOnly: _boolOr(values[_wifiOnly], defaults.wifiOnly),
      autoStartDownloads: _boolOr(
        values[_autoStart],
        defaults.autoStartDownloads,
      ),
      maxConcurrentDownloads: _concurrencyOr(
        values[_maxConcurrent],
        defaults.maxConcurrentDownloads,
      ),
      notifyOnComplete: _boolOr(
        values[_notifyComplete],
        defaults.notifyOnComplete,
      ),
      notifyOnFailure: _boolOr(
        values[_notifyFailure],
        defaults.notifyOnFailure,
      ),
      onboardingComplete: _boolOr(
        values[_onboardingComplete],
        defaults.onboardingComplete,
      ),
    );
  }

  /// Writes the whole settings object. It is a handful of rows, so a single
  /// batch is simpler and safer than tracking which field changed.
  Future<void> save(AppSettings settings) async {
    final batch = _db.batch();
    void put(String key, String value) {
      batch.insert(
        HozaDatabase.preferencesTable,
        {HozaDatabase.preferenceKey: key, HozaDatabase.preferenceValue: value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    put(_themeMode, settings.themeMode.name);
    put(_defaultMediaType, settings.defaultMediaType.storageKey);
    put(_defaultVideoFormat, settings.defaultVideoFormat.storageKey);
    put(_defaultAudioFormat, settings.defaultAudioFormat.storageKey);
    put(_qualityPreference, settings.qualityPreference.storageKey);
    put(_wifiOnly, settings.wifiOnly.toString());
    put(_autoStart, settings.autoStartDownloads.toString());
    put(_maxConcurrent, settings.maxConcurrentDownloads.toString());
    put(_notifyComplete, settings.notifyOnComplete.toString());
    put(_notifyFailure, settings.notifyOnFailure.toString());
    put(_onboardingComplete, settings.onboardingComplete.toString());

    await batch.commit(noResult: true);
  }

  /// Removes every stored preference, and returns how many there were.
  ///
  /// Emptying the table rather than writing the defaults back means keys left
  /// behind by older builds go too, and [load] already falls back to the
  /// built-in defaults for anything missing.
  Future<int> clear() => _db.delete(HozaDatabase.preferencesTable);

  static ThemeMode _themeFromKey(String? key) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == key,
      orElse: () => ThemeMode.dark,
    );
  }

  /// Guards against a stored format that belongs to the other media type.
  static MediaFormat _formatOr(
    String? key,
    MediaType expected,
    MediaFormat fallback,
  ) {
    if (key == null) return fallback;
    final format = MediaFormat.fromStorageKey(key);
    return format.mediaType == expected ? format : fallback;
  }

  static bool _boolOr(String? value, bool fallback) => switch (value) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };

  /// Clamped to the supported range so a bad row can never uncap concurrency.
  static int _concurrencyOr(String? value, int fallback) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null) return fallback;
    final options = AppSettings.concurrencyOptions;
    return parsed.clamp(options.first, options.last);
  }
}
